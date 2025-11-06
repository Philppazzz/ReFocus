import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'dart:convert';

class UsageService {
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

  /// ✅ TRACKS ONLY SELECTED APPS
  /// 
  /// IMPORTANT: Stats tracking behavior:
  /// - ONLY selected apps are tracked and saved to database
  /// - Selected apps count toward usage limits (Daily Usage, Max Session, Most Unlock)
  /// - Stats persist throughout the day and accumulate (DO NOT reset during cooldowns or app switches)
  /// - Stats only reset at midnight when new day is detected
  /// - App switching does NOT reset or affect usage counters - tracking continues seamlessly
  /// - Session tracking continues across app switches (switching between selected apps doesn't reset session)
  /// - Daily limit violation does NOT reset stats - only midnight reset does
  /// - Session/unlock violations reset their respective counters but NOT overall stats
  /// 
  /// @param currentForegroundApp - The package name of the currently foreground app (for real-time tracking)
  /// @param updateSessionTracking - Set to false during cooldowns to prevent session restart
  static Future<Map<String, dynamic>> getUsageStatsWithEvents(
    List<Map<String, String>> selectedApps, {
    String? currentForegroundApp,
    bool updateSessionTracking = true,
  }) async {
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
        };
      }
      
      // ✅ CRITICAL: If there's an active cooldown or daily lock, skip ALL tracking
      // This prevents usage/unlocks from accumulating while user is locked out
      final cooldownEnd = prefs.getInt('cooldown_end');
      final hasCooldown = cooldownEnd != null && DateTime.now().millisecondsSinceEpoch < cooldownEnd;
      final dailyLocked = prefs.getBool('daily_locked') ?? false;
      
      if (hasCooldown || dailyLocked) {
        print("🔒 LOCK ACTIVE - Skipping all tracking (cooldown: $hasCooldown, daily: $dailyLocked)");
        
        // Return current stats WITHOUT processing any new events
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
        
        // Calculate totals from existing data
        double totalSeconds = 0.0;
        double longestSessionMins = 0.0;
        String longestApp = 'None';
        String mostUnlocked = 'None';
        int maxUnlocks = 0;
        
        for (var entry in perAppUsage.entries) {
          totalSeconds += entry.value;
        }
        
        for (var entry in perAppLongest.entries) {
          if (entry.value > longestSessionMins * 60) {
            longestSessionMins = entry.value / 60;
            longestApp = entry.key;
          }
        }
        
        for (var entry in perAppUnlocks.entries) {
          if (entry.value > maxUnlocks) {
            maxUnlocks = entry.value;
            mostUnlocked = entry.key;
          }
        }
        
        final packageToName = {
          for (var app in selectedApps)
            if (app['package']!.isNotEmpty) app['package']!: app['name']!
        };
        
        return {
          'daily_usage_hours': totalSeconds / 3600,
          'max_session': longestSessionMins,
          'current_session': 0.0,
          'longest_session_app': packageToName[longestApp] ?? longestApp,
          'most_unlock_app': packageToName[mostUnlocked] ?? mostUnlocked,
          'most_unlock_count': maxUnlocks,
          'per_app_usage': perAppUsage,
        };
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

      print("\n🔍 Checking NEW events since: ${lookback.toString().substring(11, 19)}");

      // Get selected packages FIRST - we only track these apps
      final selectedPackages = selectedApps
          .map((a) => a['package']!)
          .where((p) => p.isNotEmpty)
          .toSet();

      final packageToName = {
        for (var app in selectedApps)
          if (app['package']!.isNotEmpty) app['package']!: app['name']!
      };

      // Query ALL events, but filter to ONLY selected apps
      List<dynamic> allEvents = await UsageStats.queryEvents(lookback, now);
      
      // Filter events to ONLY selected apps (user requested this)
      List<dynamic> events = allEvents.where((event) {
        String? pkg = event.packageName;
        return pkg != null && pkg.isNotEmpty && selectedPackages.contains(pkg);
      }).toList();
      
      if (allEvents.length != events.length) {
        print("📱 Filtered ${allEvents.length - events.length} events from non-selected apps");
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
        print("📊 Found ${events.length} new events");

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
                // ✅ Track ALL apps in database (for week-long tracking and LSTM)
                perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + duration;
                if (duration > (perAppLongest[currentActiveApp] ?? 0)) {
                  perAppLongest[currentActiveApp] = duration;
                }
                
                // Log usage (all events are from selected apps now)
                print("   ➕ ${packageToName[currentActiveApp] ?? currentActiveApp}: +${(duration/60).toStringAsFixed(1)}m");
              }
            }

            // Start new session
            currentActiveApp = pkg;
            currentActiveStart = timestamp;
            activeAccumulatedSeconds = 0.0;
            
            // Track unlocks (all events are from selected apps now)
            final oldCount = perAppUnlocks[pkg] ?? 0;
            perAppUnlocks[pkg] = oldCount + 1;
            print("   🔓🔓🔓 ${packageToName[pkg] ?? pkg} opened (${oldCount} → ${perAppUnlocks[pkg]} unlocks) 🔓🔓🔓");
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
                print(
                    "   ➕ ${packageToName[pkg] ?? pkg}: +${(delta / 60).toStringAsFixed(1)}m (finalizing session)");
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
      
      // ✅ CRITICAL FIX: Only track if currentForegroundApp is a SELECTED app
      // If user is in ReFocus app or home screen, STOP tracking (don't use cached app)
      String? activeApp = currentForegroundApp;
      
      // If current foreground app is NOT a selected app, finalize any active session
      if (activeApp == null || !selectedPackages.contains(activeApp)) {
        // User switched away from selected apps - finalize current session
        if (currentActiveApp != null && currentActiveStart != null && selectedPackages.contains(currentActiveApp)) {
          // Calculate final duration and add to usage
          final double delta = (nowMs - lastCheck) / 1000.0;
          if (delta > 0 && delta < 7200) {
            perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + delta;
            activeAccumulatedSeconds += delta;
            
            final double totalDuration = (nowMs - currentActiveStart) / 1000.0;
            if (totalDuration > (perAppLongest[currentActiveApp] ?? 0)) {
              perAppLongest[currentActiveApp] = totalDuration;
            }
            
            print("   ⏸️ Finalizing ${packageToName[currentActiveApp] ?? currentActiveApp}: +${(delta / 60).toStringAsFixed(1)}m (user left selected apps)");
          }
          
          // Clear active session
          currentActiveApp = null;
          currentActiveStart = null;
          activeAccumulatedSeconds = 0.0;
        }
        
        // Don't continue tracking - user is not on a selected app
        activeApp = null;
      }
      
      if (activeApp != null && selectedPackages.contains(activeApp)) {
        // Get or initialize session start time
        final int startReference = currentActiveStart ?? activeStartMs ?? nowMs;
        
        // If this is a brand new session (no stored start), initialize it
        bool isNewSession = false;
        if (currentActiveStart == null && activeStartMs == null) {
          currentActiveApp = activeApp;
          currentActiveStart = nowMs;
          activeAccumulatedSeconds = 0.0;
          isNewSession = true;
          print("   🆕 Starting real-time tracking for ${packageToName[activeApp] ?? activeApp}");
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

            print(
                "   🔄 ${packageToName[activeApp] ?? activeApp} active: +${(deltaSeconds / 60).toStringAsFixed(1)}m (real-time${isNewSession ? ', NEW SESSION' : ''})");
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
        
        // CRITICAL: Also update LockStateManager session tracking
        // This ensures session limit checking works in real-time
        // BUT ONLY if updateSessionTracking is true AND no cooldown is active
        if (updateSessionTracking && !hasCooldown) {
          try {
            // Check if session tracking exists in LockStateManager
            final sessionStart = prefs.getInt('session_start_$today');
            if (sessionStart == null) {
              // Initialize session tracking if it doesn't exist
              await prefs.setInt('session_start_$today', currentActiveStart);
              await prefs.setInt('last_activity_$today', nowMs);
              print("   ✅ Session tracking initialized (start: ${DateTime.fromMillisecondsSinceEpoch(currentActiveStart).toString().substring(11, 19)})");
            } else {
              // Update last activity time to keep session alive
              await prefs.setInt('last_activity_$today', nowMs);
              final sessionMinutes = (nowMs - sessionStart) / 1000 / 60;
              print("   ✅ Session tracking updated (${sessionMinutes.toStringAsFixed(1)}m total)");
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

      // ✅ RECALCULATE totals from unified database for SELECTED apps only
      double totalSeconds = 0.0;
      double longestSessionMins = 0.0;
      String longestApp = 'None';
      String mostUnlocked = 'None';
      int maxUnlocks = 0;

      print("\n📊 Calculating totals for SELECTED apps...");
      for (var pkg in selectedPackages) {
        // Add usage from this app
        double usage = perAppUsage[pkg] ?? 0.0;
        totalSeconds += usage;
        
        // Check if this is longest session
        double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
        if (sessionMins > longestSessionMins) {
          longestSessionMins = sessionMins;
          longestApp = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
        }

        // Check if most unlocked
        int count = perAppUnlocks[pkg] ?? 0;
        if (count > maxUnlocks) {
          maxUnlocks = count;
          mostUnlocked = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
          print("   🏆🏆🏆 NEW MOST UNLOCKED: ${packageToName[pkg] ?? pkg} (${count}x unlocks) 🏆🏆🏆");
        }

        if (usage > 0 || count > 0) {
          print("   ${packageToName[pkg] ?? pkg}: ${(usage/60).toStringAsFixed(1)}m (${count}x unlocks)");
        }
      }

      double hours = totalSeconds / 3600;
      
      // ✅ Get current global session time from LockStateManager
      final currentSessionMins = await LockStateManager.getCurrentSessionMinutes();

      print("\n✅ FINAL TOTALS (Selected Apps Only):");
      print("   Total: ${(totalSeconds/60).toStringAsFixed(1)}m");
      print("   Current Session: ${currentSessionMins.toStringAsFixed(1)}m (global)");
      print("   Longest: $longestApp (${longestSessionMins.toStringAsFixed(1)}m)");
      print("   Most Unlocked: $mostUnlocked ($maxUnlocks times)");

      // Save to database
      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': hours,
        'max_session': longestSessionMins,
        'longest_session_app': longestApp,
        'most_unlock_app': mostUnlocked,
        'most_unlock_count': maxUnlocks,
      });

      // ✅ Save selected apps to database for week-long tracking and LSTM training
      // Only selected apps are tracked now (as per user request)
      await DatabaseHelper.instance.saveDetailedAppUsage(
        date: today,
        appUsage: perAppUsage, // Selected apps only
        appUnlocks: perAppUnlocks, // Selected apps only
        appLongestSessions: perAppLongest, // Selected apps only
      );

      return {
        "daily_usage_hours": hours,
        "max_session": longestSessionMins,
        "current_session": currentSessionMins, // ✅ Current global session
        "longest_session_app": longestApp,
        "most_unlock_app": mostUnlocked,
        "most_unlock_count": maxUnlocks,
      };

    } catch (e, stack) {
      print("⚠️ ERROR: $e\n$stack");
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await _loadCurrentTotals(
        today, 
        await SharedPreferences.getInstance(),
        selectedApps
      );
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
    SharedPreferences prefs,
    List<Map<String, String>> selectedApps
  ) async {
    final packageToName = {
      for (var app in selectedApps)
        if (app['package']!.isNotEmpty) app['package']!: app['name']!
    };

    final selectedPackages = selectedApps
        .map((a) => a['package']!)
        .where((p) => p.isNotEmpty)
        .toSet();

    // Load unified database
    final perAppUsageJson = prefs.getString('per_app_usage_$date') ?? '{}';
    Map<String, double> perAppUsage = {};
    try {
      perAppUsage = Map<String, double>.from(
        json.decode(perAppUsageJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {}

    final perAppUnlocksJson = prefs.getString('per_app_unlocks_$date') ?? '{}';
    Map<String, int> perAppUnlocks = {};
    try {
      perAppUnlocks = Map<String, int>.from(json.decode(perAppUnlocksJson));
    } catch (e) {}
    
    final perAppLongestJson = prefs.getString('per_app_longest_$date') ?? '{}';
    Map<String, double> perAppLongest = {};
    try {
      perAppLongest = Map<String, double>.from(
        json.decode(perAppLongestJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {}

    // Recalculate from unified database for selected apps
    double totalSeconds = 0.0;
    double longestSessionMins = 0.0;
    String longestApp = 'None';
    String mostUnlocked = 'None';
    int maxUnlocks = 0;

    for (var pkg in selectedPackages) {
      totalSeconds += perAppUsage[pkg] ?? 0.0;
      
      double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
      if (sessionMins > longestSessionMins) {
        longestSessionMins = sessionMins;
        longestApp = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
      }

      int count = perAppUnlocks[pkg] ?? 0;
      if (count > maxUnlocks) {
        maxUnlocks = count;
        mostUnlocked = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
      }
    }

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
}