import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/utils/category_mapper.dart';
import 'package:refocus_app/services/passive_learning_service.dart';
import 'package:refocus_app/services/app_categorization_service.dart';
import 'dart:convert';

class UsageService {
  // ✅ CRITICAL: Lock to prevent concurrent calls that cause double-counting
  static bool _isUpdating = false;
  static DateTime? _lastUpdateTime;
  static const Duration _minUpdateInterval = Duration(milliseconds: 500); // Max 2 updates per second

  static Future<bool> requestPermission() async {
    bool granted = await UsageStats.checkUsagePermission() ?? false;
    if (!granted) {
      await UsageStats.grantUsagePermission();
      await Future.delayed(const Duration(seconds: 2));
      granted = await UsageStats.checkUsagePermission() ?? false;
    }
    return granted;
  }

  /// Reset today's in-memory aggregates for testing: clears per-app usage,
  /// unlocks, longest session, processed events, and active session markers.
  static Future<void> resetTodayAggregates() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await prefs.setString('per_app_usage_$today', '{}');
    await prefs.setString('per_app_unlocks_$today', '{}');
    await prefs.setString('per_app_longest_$today', '{}');
    await prefs.setString('processed_$today', '[]');
    await prefs.remove('active_app_$today');
    await prefs.remove('active_start_$today');
    await prefs.remove('active_recorded_$today');

    // Anchor last_check to NOW so past events are not reprocessed
    await prefs.setInt('last_check_$today', DateTime.now().millisecondsSinceEpoch);
    print('🧪 UsageService: Today\'s aggregates reset for testing');
  }

  /// ✅ TRACKS ALL NON-SYSTEM APPS
  ///
  /// IMPORTANT: Stats tracking behavior:
  /// - ALL non-system apps are tracked and saved to database
  /// - Non-system apps count toward usage limits (Daily Usage, Max Session, Most Unlock)
  /// - Stats persist throughout the day and accumulate (DO NOT reset during cooldowns or app switches)
  /// - Stats only reset at midnight when new day is detected
  /// - App switching does NOT reset or affect usage counters - tracking continues seamlessly
  /// - Session tracking continues across app switches (switching between apps doesn't reset session)
  /// - Daily limit violation does NOT reset stats - only midnight reset does
  /// - Session/unlock violations reset their respective counters but NOT overall stats
  ///
  /// @param currentForegroundApp - The package name of the currently foreground app (for real-time tracking)
  /// @param updateSessionTracking - Set to false during cooldowns to prevent session restart
  static Future<Map<String, dynamic>> getUsageStatsWithEvents({
    String? currentForegroundApp,
    bool updateSessionTracking = true,
  }) async {
    // ✅ CRITICAL FIX: Prevent concurrent calls that cause double-counting
    // If an update is in progress, wait for it to complete
    if (_isUpdating) {
      print("⏳ Update in progress, waiting...");
      int waitCount = 0;
      while (_isUpdating && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        waitCount++;
      }
      // If still updating after 1 second, proceed anyway (prevent deadlock)
      if (_isUpdating) {
        print("⚠️ Update taking too long, proceeding anyway");
        _isUpdating = false;
      }
    }
    
    // ✅ CRITICAL FIX: Rate limiting - don't update more than once per 500ms
    final now = DateTime.now();
    if (_lastUpdateTime != null) {
      final timeSinceLastUpdate = now.difference(_lastUpdateTime!);
      if (timeSinceLastUpdate < _minUpdateInterval) {
        // Too soon - return cached data from database instead
        print("⏸️ Rate limiting: Only ${timeSinceLastUpdate.inMilliseconds}ms since last update");
        try {
          final db = DatabaseHelper.instance;
          final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
          final combinedDailyMinutes = (categoryUsage['Social'] ?? 0.0) +
                                     (categoryUsage['Games'] ?? 0.0) +
                                     (categoryUsage['Entertainment'] ?? 0.0);
          final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
          
          return {
            'daily_usage_hours': combinedDailyMinutes / 60.0,
            'max_session': 0.0,
            'current_session': sessionMinutes,
            'longest_session_app': 'None',
            'most_unlock_app': 'None',
            'most_unlock_count': 0,
            'per_app_usage': {},
            'top_unlocked_apps': [],
            'category_usage_minutes': categoryUsage,
          };
        } catch (e) {
          print('⚠️ Error getting cached data: $e');
          // Continue with full update
        }
      }
    }
    
    _isUpdating = true;
    _lastUpdateTime = now;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      // ✅ CRITICAL: If Emergency Override is enabled, return cached stats without updating
      // This prevents usage from accumulating when the user has emergency override ON
      final isOverrideEnabled = prefs.getBool('emergency_override_enabled') ?? false;
      if (isOverrideEnabled) {
        print("🚨 Emergency Override: ON - Returning cached stats, no new tracking");

        // Return the last cached stats without any updates
        final cachedDailyUsage = prefs.getDouble('cached_daily_usage_$today') ?? 0.0;
        final cachedMaxSession = prefs.getDouble('cached_max_session_$today') ?? 0.0;
        final cachedMostUnlockApp = prefs.getString('cached_most_unlock_app_$today') ?? 'None';
        final cachedMostUnlockCount = prefs.getInt('cached_most_unlock_count_$today') ?? 0;

        return {
          'daily_usage_hours': cachedDailyUsage,
          'max_session': cachedMaxSession,
          'current_session': 0.0, // No active session during override
          'longest_session_app': 'None',
          'most_unlock_app': cachedMostUnlockApp,
          'most_unlock_count': cachedMostUnlockCount,
          'per_app_usage': {},
          'top_unlocked_apps': [], // Empty during override
        };
      }
      
      // ✅ CRITICAL: If there's an active cooldown or daily lock, skip violation tracking
      // BUT: Still process events for statistics (screen time tracking)
      // This ensures statistics show accurate overall usage even during locks
      final cooldownEnd = prefs.getInt('cooldown_end');
      final hasCooldown = cooldownEnd != null && DateTime.now().millisecondsSinceEpoch < cooldownEnd;
      final dailyLocked = prefs.getBool('daily_locked') ?? false;
      final skipViolationTracking = hasCooldown || dailyLocked;
      
      if (skipViolationTracking) {
        print("🔒 LOCK ACTIVE - Skipping violation tracking (cooldown: $hasCooldown, daily: $dailyLocked)");
        print("📊 BUT: Statistics tracking will continue for accurate screen time");
        
        // ✅ CRITICAL: Still process events for statistics, but skip violation checks
        // This ensures statistics page shows accurate overall usage
        // We'll process events but not use them for violation checking
      }

      // Check for new day - ONLY resets at midnight
      if (await _checkAndResetNewDay(today, prefs)) {
        print("🌅 NEW DAY - Stats reset (daily limit also unlocks)");
      }

      // Get last processed timestamp
      final lastCheck = prefs.getInt('last_check_$today') ?? 
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
              .millisecondsSinceEpoch;

      DateTime now = DateTime.now();
      DateTime lookback = DateTime.fromMillisecondsSinceEpoch(lastCheck);


      // Query ALL events and filter out system apps only
      // Messaging apps are now tracked as "Others" category
      List<dynamic> allEvents = await UsageStats.queryEvents(lookback, now);

      // Filter events to exclude system apps only (messaging apps are tracked as "Others")
      List<dynamic> events = allEvents.where((event) {
        String? pkg = event.packageName;
        if (pkg == null || pkg.isEmpty) return false;
        // Exclude system apps only
        if (CategoryMapper.isSystemApp(pkg)) return false;
        // ✅ Messaging apps are now included (tracked as "Others" category)
        return true;
      }).toList();

      final filteredCount = allEvents.length - events.length;
      if (filteredCount > 0) {
        print("📱 Filtered $filteredCount events (system apps only)");
      }

      // ✅ Load UNIFIED per-app data (ALL apps share this)
      final perAppUsageJson = prefs.getString('per_app_usage_$today') ?? '{}';
      Map<String, double> perAppUsage = {};
      try {
        perAppUsage = Map<String, double>.from(
          json.decode(perAppUsageJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        );
      } catch (e) {
        print("⚠️ Error loading per_app_usage: $e");
      }
      
      final perAppUnlocksJson = prefs.getString('per_app_unlocks_$today') ?? '{}';
      Map<String, int> perAppUnlocks = {};
      try {
        perAppUnlocks = Map<String, int>.from(json.decode(perAppUnlocksJson));
      } catch (e) {
        print("⚠️ Error loading per_app_unlocks: $e");
      }
      
      final perAppLongestJson = prefs.getString('per_app_longest_$today') ?? '{}';
      Map<String, double> perAppLongest = {};
      try {
        perAppLongest = Map<String, double>.from(
          json.decode(perAppLongestJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        );
      } catch (e) {
        print("⚠️ Error loading per_app_longest: $e");
      }

      // Load processed session IDs
      final processedJson = prefs.getString('processed_$today') ?? '[]';
      Set<String> processed = Set<String>.from(json.decode(processedJson));

      // Load active session
      final activeAppKey = prefs.getString('active_app_$today');
      final activeStartMs = prefs.getInt('active_start_$today');
      double activeAccumulatedSeconds =
          prefs.getDouble('active_recorded_$today') ?? 0.0;
      
      String? currentActiveApp = activeAppKey;
      int? currentActiveStart = activeStartMs;

      if (events.isNotEmpty) {

        // Sort events by timestamp
        events.sort((a, b) {
          int tsA = a.timeStamp is String ? int.parse(a.timeStamp) : a.timeStamp as int;
          int tsB = b.timeStamp is String ? int.parse(b.timeStamp) : b.timeStamp as int;
          return tsA.compareTo(tsB);
        });

        // Process ALL events (track everything in one database)
        for (var event in events) {
          String? pkg = event.packageName;
          if (pkg == null || pkg.isEmpty) continue;

          int timestamp = event.timeStamp is String
              ? int.parse(event.timeStamp)
              : event.timeStamp as int;

          int eventType = event.eventType is String
              ? int.parse(event.eventType)
              : event.eventType as int;

          // ✅ CRITICAL: Use consistent session ID format to prevent duplicate processing
          String sessionId = '${pkg}_$timestamp';
          if (processed.contains(sessionId)) {
            print("   ⏭️ Skipping already processed event: $sessionId");
            continue;
          }

          // Event type 1 = MOVE_TO_FOREGROUND
          if (eventType == 1) {
            // ✅ CRITICAL: Mark this event as processed IMMEDIATELY to prevent double-counting
            processed.add(sessionId);
            
            // Close previous session if exists
            if (currentActiveApp != null && currentActiveStart != null) {
              double duration = (timestamp - currentActiveStart) / 1000.0;
              if (duration > 0 && duration < 7200) {
                // ✅ Track ALL non-system apps in database
                perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + duration;
                if (duration > (perAppLongest[currentActiveApp] ?? 0)) {
                  perAppLongest[currentActiveApp] = duration;
                }

              }
            }

            // Start new session
            currentActiveApp = pkg;
            currentActiveStart = timestamp;
            activeAccumulatedSeconds = 0.0;

            // ✅ Track unlocks for all non-system apps
            final oldCount = perAppUnlocks[pkg] ?? 0;
            perAppUnlocks[pkg] = oldCount + 1;
          }
          // Event type 2 = MOVE_TO_BACKGROUND
          else if (eventType == 2 && currentActiveApp == pkg && currentActiveStart != null) {
            // ✅ CRITICAL: Mark this event as processed IMMEDIATELY
            processed.add(sessionId);
            
            double totalDuration = (timestamp - currentActiveStart) / 1000.0;
            if (totalDuration > 0 && totalDuration < 7200) {
              double delta = totalDuration - activeAccumulatedSeconds;
              if (delta > 0) {
                perAppUsage[pkg] = (perAppUsage[pkg] ?? 0) + delta;
              }
              if (totalDuration > (perAppLongest[pkg] ?? 0)) {
                perAppLongest[pkg] = totalDuration;
              }
            }

            currentActiveApp = null;
            currentActiveStart = null;
            activeAccumulatedSeconds = 0.0;
          }
        }
      } else {
        print("⏸️ No new events");
      }

      // ✅ REAL-TIME TRACKING: Use currentForegroundApp to track ongoing usage
      // This ensures we track usage even when user is continuously inside an app (no events fire)
      final nowMs = now.millisecondsSinceEpoch;

      // ✅ Track all non-system apps in real-time
      // Messaging apps are now tracked as "Others" category
      String? activeApp = currentForegroundApp;

      // Filter out system apps only (messaging apps are tracked as "Others")
      if (activeApp != null) {
        if (CategoryMapper.isSystemApp(activeApp)) {
          activeApp = null;
        }
        // ✅ Messaging apps are now included (tracked as "Others" category)
      }

      // ✅ Handle app switching between non-system apps
      // When switching from one app to another:
      // 1. Finalize previous app's session
      // 2. Start new app's session immediately
      // 3. Session tracking continues (doesn't reset)
      // 4. Unlock count increments (only if not already counted by event)
      if (activeApp != null) {
        // User is on a non-system app

        // If switching from one app to another, finalize previous app
        if (currentActiveApp != null &&
            currentActiveStart != null &&
            currentActiveApp != activeApp) {
          // Switching between apps - finalize previous app
          final double delta = (nowMs - lastCheck) / 1000.0;
          if (delta > 0 && delta < 7200) {
            perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + delta;
            activeAccumulatedSeconds += delta;

            final double totalDuration = (nowMs - currentActiveStart) / 1000.0;
            if (totalDuration > (perAppLongest[currentActiveApp] ?? 0)) {
              perAppLongest[currentActiveApp] = totalDuration;
            }

            
            // ✅ PASSIVE LEARNING: Track app switch for learning
            try {
              final fromCategory = await _getCategoryForPackage(currentActiveApp);
              final toCategory = await _getCategoryForPackage(activeApp);
              final fromSessionMinutes = (totalDuration / 60).round();
              final fromDailyUsage = (perAppUsage[currentActiveApp] ?? 0) / 60;
              
              await PassiveLearningService.onAppSwitch(
                fromPackageName: currentActiveApp,
                toPackageName: activeApp,
                fromCategory: fromCategory,
                toCategory: toCategory,
                fromSessionMinutes: fromSessionMinutes,
                fromDailyUsageMinutes: fromDailyUsage.round(),
              );
            } catch (e) {
              print('⚠️ Error in passive learning (app switch): $e');
              // Don't throw - passive learning should never break usage tracking
            }
          }

          // ✅ Only increment unlock count if this switch wasn't already counted by an event
          final oldCount = perAppUnlocks[activeApp] ?? 0;
          perAppUnlocks[activeApp] = oldCount + 1;
          
          // ✅ PASSIVE LEARNING: Track app reopen
          try {
            await PassiveLearningService.onAppReopened(activeApp);
          } catch (e) {
            print('⚠️ Error tracking app reopen: $e');
          }

          // Start new session for new app
          currentActiveApp = activeApp;
          currentActiveStart = nowMs;
          activeAccumulatedSeconds = 0.0;
        }
      }

      // If current foreground app is a system app or null, finalize any active session
      if (activeApp == null) {
        // User switched away from non-system apps - finalize current session
        if (currentActiveApp != null && currentActiveStart != null) {
          // Calculate final duration and add to usage
          final double delta = (nowMs - lastCheck) / 1000.0;
          if (delta > 0 && delta < 7200) {
            perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + delta;
            activeAccumulatedSeconds += delta;

            final double totalDuration = (nowMs - currentActiveStart) / 1000.0;
            if (totalDuration > (perAppLongest[currentActiveApp] ?? 0)) {
              perAppLongest[currentActiveApp] = totalDuration;
            }

            
            // ✅ PASSIVE LEARNING: Track app close for learning
            try {
              final category = await _getCategoryForPackage(currentActiveApp);
              final sessionMinutes = (totalDuration / 60).round();
              final dailyUsage = (perAppUsage[currentActiveApp] ?? 0) / 60;
              
              await PassiveLearningService.onAppClosed(
                packageName: currentActiveApp,
                category: category,
                sessionMinutes: sessionMinutes,
                dailyUsageMinutes: dailyUsage.round(),
              );
            } catch (e) {
              print('⚠️ Error in passive learning (app close): $e');
              // Don't throw - passive learning should never break usage tracking
            }
          }

          // Clear active session
          currentActiveApp = null;
          currentActiveStart = null;
          activeAccumulatedSeconds = 0.0;
        }
      }

      if (activeApp != null) {
        // Get or initialize session start time
        final int startReference = currentActiveStart ?? activeStartMs ?? nowMs;

        // If this is a brand new session (no stored start), initialize it
        if (currentActiveStart == null && activeStartMs == null) {
          currentActiveApp = activeApp;
          currentActiveStart = nowMs;
          activeAccumulatedSeconds = 0.0;
        } else {
          currentActiveApp = activeApp;
          if (currentActiveStart == null) {
            currentActiveStart = startReference;
          }
        }

        // Calculate delta since last check
        final int startForDelta = startReference > lastCheck ? startReference : lastCheck;
        if (nowMs > startForDelta) {
          final double deltaSeconds = (nowMs - startForDelta) / 1000.0;
          if (deltaSeconds > 0 && deltaSeconds < 7200) {
            perAppUsage[activeApp] =
                (perAppUsage[activeApp] ?? 0) + deltaSeconds;
            activeAccumulatedSeconds += deltaSeconds;

            final double sessionTotalSeconds =
                (nowMs - startReference) / 1000.0;
            if (sessionTotalSeconds > (perAppLongest[activeApp] ?? 0)) {
              perAppLongest[activeApp] = sessionTotalSeconds;
            }

          }
        }
      }

      // Save unified database and session state
      await prefs.setString('per_app_usage_$today', json.encode(perAppUsage));
      await prefs.setString('per_app_unlocks_$today', json.encode(perAppUnlocks));
      await prefs.setString('per_app_longest_$today', json.encode(perAppLongest));
      await prefs.setString('processed_$today', json.encode(processed.toList()));
      await prefs.setInt('last_check_$today', nowMs);

      if (currentActiveApp != null && currentActiveStart != null) {
        await prefs.setString('active_app_$today', currentActiveApp);
        await prefs.setInt('active_start_$today', currentActiveStart);
        await prefs.setDouble('active_recorded_$today', activeAccumulatedSeconds);
        
        // CRITICAL: Check for active cooldown FIRST (prevents session restart during lock)
        final cooldownEnd = prefs.getInt('cooldown_end');
        final hasCooldown = cooldownEnd != null && DateTime.now().millisecondsSinceEpoch < cooldownEnd;
        
        // ✅ CRITICAL FIX: Update LockStateManager session tracking in REAL-TIME (same as daily usage)
        // This makes session tracking event-driven like daily usage, not timer-based
        // Session accumulates immediately when UsageService processes real-time usage
        // BUT ONLY if updateSessionTracking is true AND no cooldown/lock is active
        // ✅ NOTE: Statistics tracking continues even during cooldown (for accurate screen time)
        // But violation tracking (session limit) is skipped during cooldown/lock
        if (updateSessionTracking && !hasCooldown && !skipViolationTracking) {
          try {
            // ✅ CRITICAL: Check if app is in monitored category (Social/Games/Entertainment)
            // Only track session for monitored categories (matches LockStateManager behavior)
            final category = await AppCategorizationService.getCategoryForPackage(currentActiveApp);
            final monitoredCategories = ['Social', 'Games', 'Entertainment'];
            
            if (monitoredCategories.contains(category)) {
              // ✅ REAL-TIME SESSION TRACKING: Update session accumulation immediately
              // This matches how daily usage is updated - event-driven, not timer-based
              final sessionStart = prefs.getInt('session_start_$today');
              final lastActivityMs = prefs.getInt('last_activity_$today');
              int accMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;
              
              if (sessionStart == null) {
                // Initialize session tracking
                await prefs.setInt('session_start_$today', currentActiveStart);
                await prefs.setInt('last_activity_$today', nowMs);
                await prefs.setInt('session_accumulated_ms_$today', 0);
                accMs = 0;
                
                // ✅ Update cache immediately
                LockStateManager.updateCache(0.0, 0);
                
                print("   ✅ Session tracking initialized (start: ${DateTime.fromMillisecondsSinceEpoch(currentActiveStart).toString().substring(11, 19)})");
              } else if (lastActivityMs != null) {
                // ✅ REAL-TIME ACCUMULATION: Calculate delta and accumulate immediately
                // This is the KEY FIX - session accumulates in real-time like daily usage
                // Matches exactly how daily usage is accumulated (event-driven, not timer-based)
                final deltaMs = nowMs - lastActivityMs;
                
                // ✅ CRITICAL: Only accumulate if delta is reasonable (app is actually open)
                // Same validation as LockStateManager.updateSessionActivity() for consistency
                // Accept range: 50ms - 2000ms (0.05s - 2s) - ensures app is actively open
                if (deltaMs >= 50 && deltaMs <= 2000) {
                  accMs += deltaMs;
                  await prefs.setInt('session_accumulated_ms_$today', accMs);
                  
                  // ✅ CRITICAL: Update cache IMMEDIATELY (synchronous, no delay)
                  // This ensures getCurrentSessionMinutes() returns instantly (same as daily usage)
                  final sessionMinutes = accMs / 1000 / 60;
                  LockStateManager.updateCache(sessionMinutes, accMs);
                  
                  // ✅ DEBUG: Log accumulation for verification (every 5 seconds)
                  final totalSeconds = (accMs / 1000);
                  if (totalSeconds > 0 && totalSeconds % 5 < 0.5) {
                    print("   ⏱️ Session accumulated: +${(deltaMs / 1000).toStringAsFixed(1)}s | Total: ${sessionMinutes.toStringAsFixed(2)}min (event-driven)");
                  }
                } else {
                  // Delta out of range - app might be closed or backgrounded
                  // Don't accumulate, but still update last activity to keep session alive
                  print("   ⚠️ Session delta out of range: ${deltaMs}ms (expected 50-2000ms)");
                }
                
                // ✅ CRITICAL: Always update last activity time (keeps session alive)
                await prefs.setInt('last_activity_$today', nowMs);
              } else {
                // Initialize last activity if missing
                await prefs.setInt('last_activity_$today', nowMs);
              }
            }
          } catch (e) {
            print("   ⚠️ Error updating session tracking: $e");
          }
        } else if (hasCooldown) {
          print("   🔒 Session tracking SKIPPED (cooldown active - preventing restart)");
        } else {
          print("   🔒 Session tracking SKIPPED (updateSessionTracking=false)");
        }
      } else {
        await prefs.remove('active_app_$today');
        await prefs.remove('active_start_$today');
        await prefs.remove('active_recorded_$today');
      }

      // ✅ RECALCULATE totals from unified database for ALL non-system apps
      double totalSeconds = 0.0;
      double longestSessionMins = 0.0;
      String longestApp = 'None';
      String mostUnlocked = 'None';
      int maxUnlocks = 0;

      // ✅ Get top 3 unlocked apps
      List<Map<String, dynamic>> topUnlockedApps = [];

      for (var pkg in perAppUsage.keys) {
        // Add usage from this app
        double usage = perAppUsage[pkg] ?? 0.0;
        totalSeconds += usage;

        // Check if this is longest session
        double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
        if (sessionMins > longestSessionMins) {
          longestSessionMins = sessionMins;
          longestApp = _getAppNameFromPackage(pkg);
        }

        // Check if most unlocked
        int count = perAppUnlocks[pkg] ?? 0;
        if (count > maxUnlocks) {
          maxUnlocks = count;
          mostUnlocked = _getAppNameFromPackage(pkg);
          print("   🏆🏆🏆 NEW MOST UNLOCKED: $pkg (${count}x unlocks) 🏆🏆🏆");
        }

        if (usage > 0 || count > 0) {
          print("   $pkg: ${(usage/60).toStringAsFixed(1)}m (${count}x unlocks)");
          // Add to top unlocked list if it has unlocks
          if (count > 0) {
            topUnlockedApps.add({
              'packageName': pkg,
              'unlockCount': count,
            });
          }
        }
      }

      // ✅ Sort and get top 3
      topUnlockedApps.sort((a, b) => (b['unlockCount'] as int).compareTo(a['unlockCount'] as int));
      topUnlockedApps = topUnlockedApps.take(3).toList();

      double hours = totalSeconds / 3600;

      // ✅ Get current global session time from LockStateManager
      final currentSessionMins = await LockStateManager.getCurrentSessionMinutes();

      print("\n✅ FINAL TOTALS (All Non-System Apps):");
      print("   Total: ${(totalSeconds/60).toStringAsFixed(1)}m");
      print("   Current Session: ${currentSessionMins.toStringAsFixed(1)}m (global)");
      print("   Longest: $longestApp (${longestSessionMins.toStringAsFixed(1)}m)");
      print("   Most Unlocked: $mostUnlocked ($maxUnlocks times)");

      // ✅ CRITICAL: Save statistics to database ALWAYS (even during locks)
      // This ensures statistics page shows accurate overall screen time
      // Statistics tracking is separate from violation tracking
      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': hours,
        'max_session': longestSessionMins,
        'longest_session_app': longestApp,
        'most_unlock_app': mostUnlocked,
        'most_unlock_count': maxUnlocks,
      });

      // ✅ Save all non-system apps to database for week-long tracking
      // This ALWAYS saves, even during locks, for accurate statistics
      await DatabaseHelper.instance.saveDetailedAppUsage(
        date: today,
        appUsage: perAppUsage, // All non-system apps
        appUnlocks: perAppUnlocks, // All non-system apps
        appLongestSessions: perAppLongest, // All non-system apps
      );

      final categoryUsageMinutes =
          await DatabaseHelper.instance.getCategoryUsageForDate(DateTime.now());

      // ✅ CRITICAL: For violation tracking, return stats WITHOUT new events if locked
      // This prevents violations from accumulating during locks
      // But statistics database is already updated above
      if (skipViolationTracking) {
        // Return stats WITHOUT new events for violation checking
        // But statistics database already has the updated data
        return {
          'daily_usage_hours': hours,
          'max_session': longestSessionMins,
          'current_session': 0.0, // No active session during lock
          'longest_session_app': longestApp,
          'most_unlock_app': mostUnlocked,
          'most_unlock_count': maxUnlocks,
          'per_app_usage': perAppUsage,
          'top_unlocked_apps': topUnlockedApps, // ✅ Top 3 unlocked apps
          'category_usage_minutes': categoryUsageMinutes,
        };
      }

      return {
        "daily_usage_hours": hours,
        "max_session": longestSessionMins,
        "current_session": currentSessionMins, // ✅ Current global session
        "longest_session_app": longestApp,
        "most_unlock_app": mostUnlocked,
        "most_unlock_count": maxUnlocks,
        "top_unlocked_apps": topUnlockedApps, // ✅ Top 3 unlocked apps
        "category_usage_minutes": categoryUsageMinutes,
      };

    } catch (e, stack) {
      print("⚠️ ERROR: $e\n$stack");
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await _loadCurrentTotals(
        today,
        await SharedPreferences.getInstance()
      );
    } finally {
      // ✅ CRITICAL: Always release the lock, even on error
      _isUpdating = false;
    }
  }

  static Future<bool> _checkAndResetNewDay(String today, SharedPreferences prefs) async {
    final lastDate = prefs.getString('tracking_date') ?? '';
    if (lastDate != today) {
      print("\n🌅 NEW DAY: $lastDate → $today");
      
      await prefs.setString('tracking_date', today);
      await prefs.setString('per_app_usage_$today', '{}');
      await prefs.setString('per_app_unlocks_$today', '{}');
      await prefs.setString('per_app_longest_$today', '{}');
      await prefs.setString('processed_$today', '[]');
      await prefs.remove('active_app_$today');
      await prefs.remove('active_start_$today');
      await prefs.remove('active_recorded_$today');
      await prefs.setInt('last_check_$today',
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .millisecondsSinceEpoch
      );

      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': 0.0,
        'max_session': 0.0,
        'longest_session_app': 'None',
        'most_unlock_app': 'None',
        'most_unlock_count': 0,
      });

      return true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> _loadCurrentTotals(
    String date,
    SharedPreferences prefs
  ) async {
    // Load unified database
    final perAppUsageJson = prefs.getString('per_app_usage_$date') ?? '{}';
    Map<String, double> perAppUsage = {};
    try {
      perAppUsage = Map<String, double>.from(
        json.decode(perAppUsageJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {
      // Ignore JSON parsing errors
    }

    final perAppUnlocksJson = prefs.getString('per_app_unlocks_$date') ?? '{}';
    Map<String, int> perAppUnlocks = {};
    try {
      perAppUnlocks = Map<String, int>.from(json.decode(perAppUnlocksJson));
    } catch (e) {
      // Ignore JSON parsing errors
    }

    final perAppLongestJson = prefs.getString('per_app_longest_$date') ?? '{}';
    Map<String, double> perAppLongest = {};
    try {
      perAppLongest = Map<String, double>.from(
        json.decode(perAppLongestJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {
      // Ignore JSON parsing errors
    }

    // Recalculate from unified database for all non-system apps
    double totalSeconds = 0.0;
    double longestSessionMins = 0.0;
    String longestApp = 'None';
    String mostUnlocked = 'None';
    int maxUnlocks = 0;

    // ✅ Get top 3 unlocked apps
    List<Map<String, dynamic>> topUnlockedApps = [];

    for (var pkg in perAppUsage.keys) {
      totalSeconds += perAppUsage[pkg] ?? 0.0;

      double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
      if (sessionMins > longestSessionMins) {
        longestSessionMins = sessionMins;
        longestApp = _getAppNameFromPackage(pkg);
      }

      int count = perAppUnlocks[pkg] ?? 0;
      if (count > maxUnlocks) {
        maxUnlocks = count;
        mostUnlocked = _getAppNameFromPackage(pkg);
      }

      // Add to top unlocked list if it has unlocks
      if (count > 0) {
        topUnlockedApps.add({
          'packageName': pkg,
          'unlockCount': count,
        });
      }
    }

    // ✅ Sort and get top 3
    topUnlockedApps.sort((a, b) => (b['unlockCount'] as int).compareTo(a['unlockCount'] as int));
    topUnlockedApps = topUnlockedApps.take(3).toList();

    // Get current global session time
    final currentSessionMins = await LockStateManager.getCurrentSessionMinutes();

    final totalHours = totalSeconds / 3600;

    final result = {
      "daily_usage_hours": totalHours,
      "max_session": longestSessionMins,
      "current_session": currentSessionMins, // ✅ Current global session
      "longest_session_app": longestApp,
      "most_unlock_app": mostUnlocked,
      "most_unlock_count": maxUnlocks,
      "top_unlocked_apps": topUnlockedApps, // ✅ Top 3 unlocked apps
    };

    // ✅ Cache current stats for Emergency Override (so stats stay frozen when override is ON)
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setDouble('cached_daily_usage_$todayStr', totalHours);
    await prefs.setDouble('cached_max_session_$todayStr', longestSessionMins);
    await prefs.setString('cached_most_unlock_app_$todayStr', mostUnlocked);
    await prefs.setInt('cached_most_unlock_count_$todayStr', maxUnlocks);

    return result;
  }

  static String _getAppNameFromPackage(String packageName) {
    final knownApps = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.google.android.youtube': 'YouTube',
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.twitter.android': 'Twitter',
      'com.snapchat.android': 'Snapchat',
      'com.whatsapp': 'WhatsApp',
      'com.linkedin.android': 'LinkedIn',
      'com.reddit.frontpage': 'Reddit',
    };

    return knownApps[packageName] ?? packageName.split('.').last;
  }
  
  /// Helper to get category for a package (for passive learning)
  static Future<String> _getCategoryForPackage(String packageName) async {
    try {
      return await AppCategorizationService.getCategoryForPackage(packageName);
    } catch (e) {
      print('⚠️ Error getting category for $packageName: $e');
      return CategoryMapper.categoryOthers;
    }
  }
}