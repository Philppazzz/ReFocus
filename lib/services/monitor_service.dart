import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/usage_monitoring_service.dart';
import 'package:refocus_app/services/hybrid_lock_manager.dart';
import 'package:refocus_app/services/app_categorization_service.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/app_name_service.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/utils/category_mapper.dart';
import 'package:flutter/material.dart';
import 'package:refocus_app/pages/lock_screen.dart';
import 'package:refocus_app/pages/home_page.dart'; // For AppState
import 'package:refocus_app/main.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class MonitorService {
  static const platform = MethodChannel('com.example.refocus/monitor');
  static Timer? _monitorTimer;
  static bool _isMonitoring = false;
  static bool _lockVisible = false;
  static bool _usagePermissionGranted = false;
  
  // Cache removed - usage stats are now saved directly to database via UsageService

  /// Manually trigger limit check (for testing)
  static Future<void> checkLimits() async {
    // Reset lock visibility flag to allow new lock screen if needed
    _lockVisible = false;
    
    // Trigger check immediately
    await _checkForegroundApp();
  }
  
  /// Clear lock state (allows lock screen to be re-shown)
  static void clearLockState() {
    _lockVisible = false;
  }
  
  /// Clear stats cache (force fresh data fetch)
  /// Note: Cache removed - stats are saved directly to database
  static void clearStatsCache() {
    // No-op: Stats are now saved directly to database via UsageService
  }
  
  /// Clear active app cache (prevent usage accumulation during lock screen)
  static void _clearActiveAppCache() {
    // Fire and forget - clear the cache asynchronously
    SharedPreferences.getInstance().then((prefs) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      prefs.remove('active_app_$today');
      prefs.remove('active_start_$today');
      prefs.remove('active_recorded_$today');
      
      print("🚫 Active app cache cleared - usage accumulation STOPPED");
    }).catchError((e) {
      print("⚠️ Error clearing active app cache: $e");
    });
  }

  /// Start monitoring foreground apps with optimized background tracking
  /// Increased frequency for more reliable locking (every 1 second instead of 2)
  static Future<void> startMonitoring() async {
    if (_isMonitoring) {
      print("ℹ️ Monitoring already active");
      return;
    }

    _isMonitoring = true;

    // ✅ AppLockManager is ready to use (no initialization needed)
    print("✅ AppLockManager ready - using rule-based lock logic");

    // Check usage permission silently (don't request yet - will request when needed)
    _usagePermissionGranted = await UsageStats.checkUsagePermission() ?? false;
    if (!_usagePermissionGranted) {
      print('⚠️ Usage access not granted yet – will request when first needed');
    } else {
      print('✅ Usage access already granted');
    }

    // ✅ Start category-based monitoring service
    print("🚀 Starting category-based monitoring service...");
    final categoryMonitoring = UsageMonitoringService();
    await categoryMonitoring.startMonitoring();

    // Start a foreground service to keep the Dart isolate alive in background
    // This is the proper Android way to keep app running in background
    // ✅ CRITICAL: Foreground service enables proactive feedback from any app
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'ReFocus is monitoring',
          notificationText: 'Keeping you focused on your goals',
        );
        print("✅ Foreground service started - Proactive feedback will work from any app");
      } else {
        print("ℹ️ Foreground service already running - Proactive feedback active");
      }
      
      // ✅ VERIFICATION: Verify service is actually running
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        print("✅ VERIFIED: Foreground service is running - Background monitoring active");
      } else {
        print("⚠️ WARNING: Foreground service reported as not running - Proactive feedback may not work from other apps");
      }
    } catch (e) {
      print('⚠️ ERROR: Unable to start foreground service: $e');
      print('⚠️ WARNING: Proactive feedback will only work when ReFocus is open');
      // Continue even if service fails - timer will still work while app is in memory
    }

    // Start monitoring with optimized intervals
    // ✅ CRITICAL FIX: Check every 200ms for session tracking (matches daily usage speed)
    // Daily usage updates continuously from Android events, so session should update frequently too
    // This ensures session tracking is as accurate and responsive as daily usage
    // ✅ CRITICAL: This timer enables proactive feedback checks from any app
    _monitorTimer?.cancel(); // Cancel any existing timer first
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!_isMonitoring) {
        print("⚠️ Monitoring timer running but _isMonitoring is false - canceling");
        timer.cancel();
        return;
      }
      
      // ✅ VERIFICATION: Periodically check if foreground service is still running
      // Check every 5 seconds (25 ticks at 200ms interval) to avoid excessive logging
      if (timer.tick % 25 == 0) {
        try {
          final isServiceRunning = await FlutterForegroundTask.isRunningService;
          if (!isServiceRunning) {
            print("⚠️ WARNING: Foreground service stopped at tick ${timer.tick} - Attempting restart...");
            // Try to restart foreground service
            try {
              await FlutterForegroundTask.startService(
                notificationTitle: 'ReFocus is monitoring',
                notificationText: 'Keeping you focused on your goals',
              );
              print("✅ Foreground service restarted successfully");
            } catch (e) {
              print("⚠️ ERROR: Failed to restart foreground service: $e");
            }
          }
        } catch (e) {
          print("⚠️ Error checking foreground service status: $e");
        }
      }
      
      try {
        await _checkForegroundApp();
      } catch (e) {
        print("⚠️ Error in monitoring loop: $e");
        // Continue monitoring even if one check fails
      }
    });

    print("✅ Monitoring timer started - will check every 200ms (matches daily usage speed)");
    print("✅ Monitoring service started - tracking active");
  }

  /// Stop monitoring
  static void stopMonitoring() {
    print("ℹ️ Stopping app monitor service...");
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    
    try {
      FlutterForegroundTask.stopService();
      print("✅ Foreground service stopped");
    } catch (e) {
      print("⚠️ Error stopping foreground service: $e");
    }
  }

  /// Restart monitoring (useful after app resumes from background)
  /// Ensures service is running even if it was killed by the system
  static Future<void> restartMonitoring() async {
    
    if (_isMonitoring) {
      // Service is already running, just verify foreground service is active
      try {
        final isServiceRunning = await FlutterForegroundTask.isRunningService;
        if (!isServiceRunning) {
          print("⚠️ WARNING: Service was killed - restarting foreground service...");
          print("⚠️ Without foreground service, proactive feedback will only work when ReFocus is open");
          // Restart foreground service without stopping monitoring
          try {
            await FlutterForegroundTask.startService(
              notificationTitle: 'ReFocus is monitoring',
              notificationText: 'Keeping you focused on your goals',
            );
            print("✅ Foreground service restarted - Proactive feedback restored");
            
            // Verify restart was successful
            final verifyRunning = await FlutterForegroundTask.isRunningService;
            if (verifyRunning) {
              print("✅ VERIFIED: Foreground service is now running");
            } else {
              print("❌ ERROR: Foreground service restart failed - verification failed");
            }
          } catch (e) {
            print("❌ ERROR: Could not restart foreground service: $e");
            print("⚠️ Proactive feedback will only work when ReFocus app is open");
          }
        } else {
          print("✅ VERIFIED: Foreground service is running - Proactive feedback active from any app");
        }
      } catch (e) {
        print("⚠️ Error checking service status: $e");
        // Try to restart foreground service anyway
        // ✅ CRITICAL: Foreground service enables proactive feedback from any app
        try {
          await FlutterForegroundTask.startService(
            notificationTitle: 'ReFocus is monitoring',
            notificationText: 'Keeping you focused on your goals',
          );
          print("✅ Foreground service started - Proactive feedback enabled");
          
          // Verify service started successfully
          final verifyRunning = await FlutterForegroundTask.isRunningService;
          if (verifyRunning) {
            print("✅ VERIFIED: Foreground service is running - Background monitoring active");
          } else {
            print("⚠️ WARNING: Foreground service start reported success but verification failed");
          }
        } catch (e2) {
          print("❌ ERROR: Could not restart service: $e2");
          print("⚠️ Proactive feedback will only work when ReFocus app is open");
        }
      }
      
      // ✅ CRITICAL: Verify timer is running
      if (_monitorTimer == null || !_monitorTimer!.isActive) {
        print("⚠️ Monitoring timer is not active - recreating timer...");
        _monitorTimer?.cancel();
        _monitorTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
          if (!_isMonitoring) {
            print("⚠️ Monitoring timer running but _isMonitoring is false - canceling");
            timer.cancel();
            return;
          }
          
          try {
            await _checkForegroundApp();
          } catch (e) {
            print("⚠️ Error in monitoring loop: $e");
          }
        });
        print("✅ Monitoring timer recreated");
      }
      
      // ✅ CRITICAL: Force an immediate check after restart to ensure tracking resumes
      await _checkForegroundApp();
      print("✅ Immediate check completed - monitoring should be active");
    } else {
      // Monitoring not active - start it
      print("⚠️ Monitoring not active - starting monitoring service...");
      await startMonitoring();
      print("✅ Monitoring service started");
    }
    
    print("✅ RestartMonitoring completed - _isMonitoring = $_isMonitoring, timer active = ${_monitorTimer?.isActive ?? false}");
  }

  /// Check foreground app and enforce limits
  static Future<void> _checkForegroundApp() async {
    try {
      // ✅ CRITICAL: Check for active locks FIRST (before checking _lockVisible)
      // This ensures locks are enforced even when app is closed/reopened
      final cooldownInfo = await LockStateManager.getActiveCooldown();
      final hasActiveLock = cooldownInfo != null;
      
      // ✅ CRITICAL: If Emergency Override is enabled, stop all tracking and skip violations
      final isOverrideEnabled = AppState().isOverrideEnabled;
      if (isOverrideEnabled) {
        print("🚨 Emergency Override: ON - All tracking paused, no violations enforced");
        return; // Don't track usage, don't check violations, don't show lock screens
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Get current foreground app
      String? foregroundApp;
      try {
        foregroundApp = await platform.invokeMethod<String>('getForegroundApp');
      } catch (e) {
        print('⚠️ Error getting foreground app: $e');
        // ✅ EDGE CASE: Permission might be revoked
        // Continue monitoring - will retry next cycle
        return;
      }

      // ✅ NULL SAFETY: Validate foreground app
      if (foregroundApp == null || foregroundApp.isEmpty) {
        // No app in foreground - user might be on home screen
        return;
      }

      // Check if we're tracking this app (exclude system apps and messaging apps)
      final isTracked = !CategoryMapper.isSystemApp(foregroundApp) && 
                        !CategoryMapper.isMessagingApp(foregroundApp);

      // PRIORITY 0: Check for grace period (prevents immediate re-lock)
      final gracePeriodEnd = prefs.getInt('grace_period_end');
      if (gracePeriodEnd != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now < gracePeriodEnd) {
          final remainingSeconds = ((gracePeriodEnd - now) / 1000).ceil();
          print("🛡️ Grace period: ${remainingSeconds}s - no checks");
          return;
        } else {
          await prefs.remove('grace_period_end');
          print("✅ Grace period ended");
        }
      }

      // PRIORITY 1: Always enforce an active cooldown/lock - MOST CRITICAL
      // This must work even when user is in other apps or app is closed
      // ✅ CRITICAL FIX: Check for active lock BEFORE checking _lockVisible
      // This ensures lock screen appears even if app was closed and reopened
      if (hasActiveLock) {
        // cooldownInfo is guaranteed to be non-null when hasActiveLock is true
        final lockInfo = cooldownInfo;
        print("🔒 Active lock detected: ${lockInfo['reason']}");
        
        // ✅ CRITICAL FIX: ALWAYS enforce lock when user is on a tracked app
        // This works even if app was closed/killed and reopened
        // Don't check _lockVisible flag - force show every time to prevent bypass
        if (isTracked) {
          print("🚨 User on locked app ($foregroundApp) during ${lockInfo['reason']} - enforcing lock");
          await _bringAppToForeground();
          await Future.delayed(const Duration(milliseconds: 500));
          
          // ✅ CRITICAL: Always show lock screen when user is on selected app during lock
          // Use force: true to bypass _lockVisible check and ensure it shows every time
          Future.delayed(const Duration(milliseconds: 200), () {
            _showLockScreen(lockInfo, force: true, allowBackNavigation: false);
          });
        }
        
        // ✅ CRITICAL: Don't return early - continue monitoring to catch app switches
        // This ensures if user exits and reopens, lock screen appears again
        // But skip violation checks and tracking during lock
        return; // Don't check for new violations if already locked
      }
      
      // ✅ CRITICAL: Only check _lockVisible flag if no active lock
      // If lock screen is visible but no active lock, clear it
      if (_lockVisible && !hasActiveLock) {
        print("🔒 Lock screen visible but no active lock - clearing lock state");
        _lockVisible = false;
      }
      
      // ✅ CRITICAL: If Emergency Override is enabled, stop all tracking and skip violations
      // (Already checked above, but keeping for clarity)
      
      // ✅ CRITICAL: Track cooldown state for cache clearing when cooldown ends
      final wasInCooldown = prefs.getBool('_was_in_cooldown') ?? false;
      if (hasActiveLock && !wasInCooldown) {
        await prefs.setBool('_was_in_cooldown', true);
      } else if (!hasActiveLock && wasInCooldown) {
        // Cooldown just ended - will be handled below
      }
      
      if (!hasActiveLock) {
        // No active lock - reset lock visibility flag
        if (_lockVisible) {
          _lockVisible = false;
        }
        
        // ✅ CRITICAL FIX: Clear stats cache when cooldown ends to ensure fresh unlock count
        // This ensures unlock tracking resumes immediately after cooldown
        // Check if we just transitioned from cooldown to no cooldown
        if (wasInCooldown) {
          clearStatsCache();
          await prefs.setBool('_was_in_cooldown', false);
          
          // ✅ CRITICAL: Force immediate violation check after cooldown ends
          // This ensures unlock limit is checked immediately when user opens apps
          // The check will happen naturally in the next lines, but we ensure cache is cleared
        }
      }

      // PRIORITY 2: Update session activity ONLY for Social, Games, Entertainment categories
      // ✅ CRITICAL: Session tracking ONLY happens for monitored categories (Social, Games, Entertainment)
      // IMPORTANT: Session continues across app switches between these 3 categories
      // doesn't reset the session timer. Only switching to "Others" or system apps or cooldown resets it.
      // ✅ CRITICAL FIX: Session tracking happens BEFORE early returns for violations
      // This ensures session time accumulates even if we skip violation checks
      if (isTracked && !hasActiveLock) {
        // Check if app is in monitored category (Social, Games, Entertainment)
        final category = await AppCategorizationService.getCategoryForPackage(foregroundApp);
        final monitoredCategories = ['Social', 'Games', 'Entertainment'];
        
        if (monitoredCategories.contains(category)) {
          // ✅ Update LockStateManager (for lock decisions - milliseconds-based, more accurate)
          // This accumulates session time in milliseconds and handles 5-minute inactivity threshold
          // ✅ CRITICAL FIX: This is now called every 200ms (instead of 1 second), matching daily usage speed
          // Daily usage updates continuously from Android events, so session should update frequently too
          try {
            await LockStateManager.updateSessionActivity();
            
            // ✅ OPTIMIZED: Only log every 5 seconds to reduce log spam while maintaining verification
            // Get current session to verify it's updating (but don't log every time)
            final now = DateTime.now();
            if (now.second % 5 == 0 && now.millisecond < 200) {
              final currentSession = await LockStateManager.getCurrentSessionMinutes();
              print("📱 Session activity updated for $foregroundApp ($category) - Current session: ${currentSession.toStringAsFixed(2)}min");
            }
          } catch (e) {
            print("⚠️ Error updating session activity: $e");
            // Continue - don't break monitoring if session update fails
          }
        } else {
          // Not a monitored category - session tracking paused but not reset
          final currentSession = await LockStateManager.getCurrentSessionMinutes();
          if (currentSession > 0) {
            print("📱 Session paused (not reset) for $foregroundApp ($category - not monitored) - Session remains: ${currentSession.toStringAsFixed(2)}min");
          } else {
            print("📱 Skipping session tracking for $foregroundApp ($category - not monitored)");
          }
        }
      } else if (hasActiveLock) {
        // Active lock - session tracking is paused (handled in LockStateManager.updateSessionActivity)
        print("🔒 Session tracking paused - active lock detected");
      }
      // ✅ NO session tracking for ReFocus app, system apps, or "Others" category!
      
      // ✅ CRITICAL: Save usage stats to database (for frontend display)
      // This ensures home_page and dashboard_screen can read accurate data
      // Only save if not in cooldown/lock (to prevent accumulation during lock)
      if (isTracked && !hasActiveLock) {
        try {
          // Call UsageService to process events and save to database
          // This updates SharedPreferences AND saves to SQLite database
          await UsageService.getUsageStatsWithEvents(
            currentForegroundApp: foregroundApp,
            updateSessionTracking: true,
          );
          print("💾 Usage stats saved to database for $foregroundApp");
        } catch (e) {
          print("⚠️ Error saving usage stats: $e");
          // Don't throw - continue with violation checks
        }
      }

      // PRIORITY 2.5: Check and send warnings ONLY for tracked apps
      if (isTracked) {
        // ✅ Calculate daily usage excluding "Others" category (only monitored categories count towards limit)
        final db = DatabaseHelper.instance;
        final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
        final monitoredDailyMinutes = (categoryUsage['Social'] ?? 0.0) +
                                       (categoryUsage['Games'] ?? 0.0) +
                                       (categoryUsage['Entertainment'] ?? 0.0);
        final dailyHours = monitoredDailyMinutes / 60.0;
        
        final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();

        String? currentAppName = foregroundApp;

        // Get thresholds from LockStateManager
        final thresholds = await LockStateManager.getThresholds();
        final dailyLimit = thresholds['dailyHours'] as double;
        final sessionLimit = thresholds['sessionMinutes'] as double;

        // ✅ Check and send warnings BEFORE checking violations
        // This ensures users are ALWAYS warned before they get locked
        await NotificationService.checkAndSendWarnings(
          dailyHours: dailyHours,
          sessionMinutes: sessionMinutes,
          dailyLimit: dailyLimit,
          sessionLimit: sessionLimit,
          currentAppName: currentAppName,
        );
        
        // ✅ Send final warning if user is VERY close to limit (95%+)
        // This is a last-minute alert right before violation occurs
        final dailyPercentage = dailyHours / dailyLimit;
        final sessionPercentage = sessionMinutes / sessionLimit;

        final today = DateTime.now().toIso8601String().substring(0, 10);
        final prefs = await SharedPreferences.getInstance();

        // Final warning for daily limit (95%+)
        if (dailyPercentage >= 0.95 && dailyPercentage < 1.0) {
          final warningKey = 'daily_final_warning_$today';
          if (!(prefs.getBool(warningKey) ?? false)) {
            await NotificationService.showDailyLimitWarning(
              dailyHours,
              dailyLimit,
              warningLevel: 95,
            );
            await prefs.setBool(warningKey, true);
          }
        }

        // Final warning for session limit (95%+)
        if (sessionPercentage >= 0.95 && sessionPercentage < 1.0) {
          final warningKey = 'session_final_warning_$today';
          if (!(prefs.getBool(warningKey) ?? false)) {
            await NotificationService.showSessionLimitWarning(
              sessionMinutes,
              sessionLimit,
              warningLevel: 95,
              currentAppName: currentAppName,
            );
            await prefs.setBool(warningKey, true);
          }
        }

        // Check and reward good behavior (decrease violations if user behaves well)
        // Only check every 5 minutes to avoid excessive checks
        final lastGoodBehaviorCheck = prefs.getInt('last_good_behavior_check') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastGoodBehaviorCheck > 5 * 60 * 1000) { // 5 minutes
          await LockStateManager.checkAndRewardGoodBehavior();
          await prefs.setInt('last_good_behavior_check', now);
        }

        // PRIORITY 2.6: Check for proactive feedback (learning mode only)
        // This works from any app, not just HomePage
        // ✅ CRITICAL: Works in background via foreground service
        if (await LearningModeManager.shouldShowProactiveFeedback()) {
          try {
            // Get category for current app
            final category = await AppCategorizationService.getCategoryForPackage(foregroundApp);
            
            // ✅ CRITICAL: Sync usage from database before checking proactive feedback
            // This ensures we detect 50% threshold accurately, even in background
            // Database is updated by UsageService which processes Android UsageStats
            final db = DatabaseHelper.instance;
            final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
            
            // ✅ For monitored categories (Social/Games/Entertainment), use COMBINED usage
            // This matches how lock decisions work (shared limits system)
            final monitoredCategories = ['Social', 'Games', 'Entertainment'];
            int categoryDailyUsage;
            if (monitoredCategories.contains(category)) {
              // Combined daily usage for monitored categories
              categoryDailyUsage = ((categoryUsage['Social'] ?? 0.0) +
                                   (categoryUsage['Games'] ?? 0.0) +
                                   (categoryUsage['Entertainment'] ?? 0.0)).round();
            } else {
              // Per-category usage for Others
              categoryDailyUsage = (categoryUsage[category] ?? 0.0).round();
            }
            
            // ✅ CRITICAL: Get session usage from LockStateManager (source of truth)
            // LockStateManager tracks continuous session across monitored categories
            // with 5-minute inactivity threshold
            final categorySessionUsage = await LockStateManager.getCurrentSessionMinutes();
            
            print('📊 Proactive feedback check: $category - Daily: $categoryDailyUsage min, Session: ${categorySessionUsage.toStringAsFixed(1)} min');

            // Check if we should show proactive feedback
            final promptResult = await ProactiveFeedbackService.shouldShowPrompt(
              category: category,
              sessionUsageMinutes: categorySessionUsage.round(),
              dailyUsageMinutes: categoryDailyUsage,
            );

            if (promptResult['shouldShow'] as bool) {
              final usageLevel = promptResult['usageLevel'] as int;
              final isOveruse = promptResult['isOveruse'] as bool? ?? false;
              final reason = promptResult['reason'] as String? ?? 'Usage milestone';
              
              // Get app name
              final appName = await AppNameService.getAppName(foregroundApp);

              // ✅ VERIFICATION: Log that we're about to show notification
              print('📢 PROACTIVE FEEDBACK: Showing notification for $appName ($category)');
              print('   Current app: $foregroundApp');
              print('   Usage: ${categoryDailyUsage}min daily, ${categorySessionUsage.toStringAsFixed(1)}min session');
              print('   Reason: $reason');
              
              // Verify foreground service is running before showing notification
              try {
                final isServiceRunning = await FlutterForegroundTask.isRunningService;
                if (!isServiceRunning) {
                  print('⚠️ WARNING: Foreground service not running - Notification may not appear from other apps');
                } else {
                  print('✅ VERIFIED: Foreground service running - Notification will appear from any app');
                }
              } catch (e) {
                print('⚠️ Error checking service status: $e');
              }

              // Show proactive feedback notification (works from any app)
              // Create custom message for overuse detection
              String? customMessage;
              if (isOveruse) {
                customMessage = '$reason\nWould a break be helpful now?';
              }
              
              try {
                await NotificationService.showProactiveFeedbackNotification(
                  appName: appName,
                  category: category,
                  sessionUsageMinutes: categorySessionUsage.round(),
                  dailyUsageMinutes: categoryDailyUsage,
                  usageLevel: usageLevel,
                  customMessage: customMessage,
                );
                print('✅ PROACTIVE FEEDBACK: Notification sent successfully for $appName');
              } catch (e) {
                print('❌ ERROR: Failed to show proactive feedback notification: $e');
                print('   This may prevent feedback collection from other apps');
              }

            } else {
              // Log why feedback wasn't shown (for debugging)
              final reason = promptResult['reason'] as String? ?? 'Unknown';
              if (reason != 'Cooldown active' && reason != 'Session too short') {
                // Only log non-trivial reasons to avoid spam
                print('📊 Proactive feedback skipped: $reason');
              }
            }
          } catch (e) {
            print('⚠️ Error checking proactive feedback: $e');
            // Don't throw - continue with violation checks
          }
        }
      }

      // PRIORITY 3: Check for violations using Decision Tree ML predictions
      // ✅ Decision Tree predicts overuse for each category based on:
      // - Daily usage (in minutes)
      // - Current session usage (in minutes)
      // - Time of day (hour 0-23)
      // - Category (Social, Games, Entertainment)
      Map<String, dynamic>? violation;


      // Clear cache before violation checks
      clearStatsCache();

      // ✅ Calculate daily usage excluding "Others" category (only monitored categories count towards limit)
      final db = DatabaseHelper.instance;
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      final monitoredDailyMinutes = (categoryUsage['Social'] ?? 0.0) +
                                     (categoryUsage['Games'] ?? 0.0) +
                                     (categoryUsage['Entertainment'] ?? 0.0);
      final dailyHours = monitoredDailyMinutes / 60.0;


      // ✅ DECISION TREE INTEGRATION: Check if current app's category should be locked
      if (isTracked) {
        try {
          // Get category for current app
          final category = await AppCategorizationService.getCategoryForPackage(foregroundApp);

          // Get category-specific usage
          final monitoringService = UsageMonitoringService();
          // ✅ FIX: dailyUsage and sessionUsage are already in MINUTES, not seconds!
          final categoryDailyMins = monitoringService.dailyUsage[category] ?? 0;
          final categorySessionMins = monitoringService.sessionUsage[category] ?? 0;

          // Get current time of day
          final now = DateTime.now();
          final timeOfDay = now.hour;


          // ✅ Hybrid lock manager: ML when ready, rule-based as fallback
          final lockResult = await HybridLockManager.shouldLockApp(
            category: category,
            dailyUsageMinutes: categoryDailyMins,
            sessionUsageMinutes: categorySessionMins,
            currentHour: timeOfDay,
            appName: foregroundApp,
            packageName: foregroundApp,
          );

          final shouldLock = lockResult['shouldLock'] as bool;
          final predictionSource = lockResult['source'] as String;
          final lockReason = lockResult['reason'] as String;
          final confidence = lockResult['confidence'] as double;
          final shouldAskFeedback = lockResult['shouldAskFeedback'] as bool? ?? false;
          final feedbackUsageLevel = lockResult['feedbackUsageLevel'] as int?;

          // Check for proactive feedback prompt (learning mode)
          if (!shouldLock && shouldAskFeedback && feedbackUsageLevel != null) {
            // This will be handled by UI layer
            // UI should check lockResult['shouldAskFeedback'] and show dialog
          }

          if (shouldLock) {
            violation = {
              'type': '${predictionSource}_lock',
              'message': lockReason,
              'category': category,
              'prediction_source': predictionSource,
              'confidence': confidence,
            };
            print("🚨🚨🚨 ${predictionSource.toUpperCase()} LOCK: $category! 🚨🚨🚨");
            print("   Reason: $lockReason");
            print("   Confidence: ${(confidence * 100).toStringAsFixed(0)}%");
          }
        } catch (e) {
          print("⚠️ Error in lock check: $e");
          // Continue monitoring even if lock check fails
        }
      }

      // Fallback checks if ML didn't trigger lock
      if (violation == null) {
        // Check daily limit first (most severe)
        if (await LockStateManager.isDailyLimitExceeded(dailyHours)) {
          violation = {
            'type': 'daily_limit',
            'message': 'Daily limit reached - unlocks tomorrow',
          };
          print("🚨🚨🚨 DAILY LIMIT EXCEEDED! 🚨🚨🚨");
        }

        // Check session limit (only if daily limit not exceeded)
        if (violation == null && await LockStateManager.isSessionLimitExceeded()) {
          violation = {
            'type': 'session_limit',
            'message': 'Continuous usage limit reached',
          };
          print("🚨🚨🚨 SESSION LIMIT EXCEEDED! 🚨🚨🚨");
        }
      }

      // PRIORITY 4: Handle violation if detected - MUST TRIGGER INSTANTLY
      if (violation != null) {
        final limitType = violation['type'];
        print("🚨🚨🚨 VIOLATION DETECTED: $limitType 🚨🚨🚨");

        // ✅ Calculate daily usage excluding "Others" category (only monitored categories count towards limit)
        final db = DatabaseHelper.instance;
        final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
        final monitoredDailyMinutes = (categoryUsage['Social'] ?? 0.0) +
                                       (categoryUsage['Games'] ?? 0.0) +
                                       (categoryUsage['Entertainment'] ?? 0.0);
        final dailyHours = monitoredDailyMinutes / 60.0;
        
        final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();

        // Resolve app name based on violation type
        String appName = 'App';
        String? appPackage;

        if (limitType == 'ml_prediction') {
          // For ML predictions, use current foreground app and category
          final category = violation['category'] ?? 'App';
          appName = '$category apps';
          appPackage = foregroundApp;
        } else if (limitType == 'session_limit') {
          // For session limit, use current foreground app
          appName = foregroundApp;
          appPackage = foregroundApp;
        } else if (limitType == 'daily_limit') {
          appName = 'All Apps';
          appPackage = '';
        }

        // Special handling for daily limit
        if (limitType == 'daily_limit') {
          await LockStateManager.setDailyLock();
          await NotificationService.showLimitReachedNotification(limitType);

          // Log violation to database
          await DatabaseHelper.instance.logViolation(
            violationType: limitType,
            appName: appName,
            appPackage: appPackage,
            dailyHours: dailyHours,
            sessionMinutes: null,
            unlockCount: null,
            cooldownSeconds: null, // Daily limit has no cooldown
          );

          print("🔒 Daily lock activated (will show when user tries selected app)");

          // ✅ CRITICAL FIX: Always show lock screen when user opens tracked app during daily lock
          // This ensures user cannot bypass daily lock by exiting and reopening
          // The lock screen will appear every time user tries to open a tracked app
          if (isTracked) {
            print("🚨 User on locked app during daily limit ($foregroundApp) - enforcing lock");
            await _bringAppToForeground();
            await Future.delayed(const Duration(milliseconds: 500));
            
            // User is on selected app - MUST show lock screen to block access
            _showLockScreen({
              'reason': 'daily_limit',
              'remainingSeconds': -1,
              'appName': appName,
              'mlSource': null, // Daily limit is always rule-based
              'mlConfidence': null,
            }, force: true, allowBackNavigation: false);
          }
          
          return;
        }

        // Handle session violation or ML prediction (both use cooldown mechanism)
        await LockStateManager.recordViolation(limitType);

        // Get cooldown duration
        final cooldownSeconds = await LockStateManager.getCooldownSeconds(limitType);

        // Apply side-effects (reset session timer)
        await LockStateManager.onViolationApplied(
          limitType: limitType,
          currentMostUnlockedCount: 0, // Not used anymore
        );

        // Set cooldown
        await LockStateManager.setCooldown(
          reason: limitType,
          seconds: cooldownSeconds,
          appName: appName,
        );

        // Log violation to database
        await DatabaseHelper.instance.logViolation(
          violationType: limitType,
          appName: appName,
          appPackage: appPackage,
          dailyHours: dailyHours,
          sessionMinutes: sessionMinutes,
          unlockCount: null, // Unlock count no longer triggers violations
          cooldownSeconds: cooldownSeconds,
        );

        // Notify
        await NotificationService.showLimitReachedNotification(limitType);
        await NotificationService.showCooldownNotification(cooldownSeconds ~/ 60);

        print("🔒 Cooldown set - showing lock screen immediately");

        // For session_limit or ml_prediction, bring to foreground if user is on a tracked app
        if ((limitType == 'session_limit' || limitType == 'ml_prediction') && isTracked) {
          // Bring to foreground if on tracked app
          await _bringAppToForeground();
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // ✅ CRITICAL: Pass ML source and confidence to lock screen for verification
        final mlSource = violation['prediction_source'] as String?;
        final mlConfidence = violation['confidence'] as double?;
        
        // Show lock screen immediately
        _showLockScreen({
          'reason': limitType,
          'remainingSeconds': cooldownSeconds,
          'appName': appName,
          'mlSource': mlSource, // ✅ Pass ML source (ensemble, rule_based, etc.)
          'mlConfidence': mlConfidence, // ✅ Pass ML confidence (0.0-1.0)
        }, force: true);
      }

    } catch (e, stackTrace) {
      print("⚠️ Monitor error: $e");
      print(stackTrace);
    }
  }

  /// Bring ReFocus app to foreground
  static Future<void> _bringAppToForeground() async {
    try {
      await platform.invokeMethod('bringToForeground');
      print("📱 Brought app to foreground");
    } catch (e) {
      print("⚠️ Error bringing app to foreground: $e");
    }
  }

  // ✅ CRITICAL: Add lock to prevent concurrent lock screen calls
  static bool _isShowingLock = false;
  
  static void _showLockScreen(Map<String, dynamic> cooldown, {bool force = false, bool allowBackNavigation = false}) {
    // ✅ CRITICAL: Prevent concurrent lock screen calls (race condition fix)
    if (_isShowingLock && !force) {
      print("⚠️ Lock screen call already in progress - BLOCKING duplicate");
      return;
    }
    
    // ✅ CRITICAL FIX: If force=true, always show lock screen (even if already visible)
    // This ensures lock screen appears every time user opens selected app during lock
    if (_lockVisible && !force) {
      print("⚠️ Lock screen already visible - BLOCKING duplicate (force=$force)");
      return;
    }
    
    // If force=true and lock is already visible, reset the flag to allow re-showing
    if (_lockVisible && force) {
      _lockVisible = false;
    }
    
    _isShowingLock = true;
    
    try {
      final navigator = Nav.navigatorKey.currentState;
      if (navigator == null) {
        print("⚠️ Navigator not available - cannot show lock screen");
        // ✅ CRITICAL: If navigator is not available, try again after a short delay
        // This handles the case where app is starting up or was closed/reopened
        Future.delayed(const Duration(milliseconds: 500), () {
          final retryNavigator = Nav.navigatorKey.currentState;
          if (retryNavigator != null) {
            print("✅ Navigator available on retry - showing lock screen");
            _lockVisible = true;
            retryNavigator.pushNamed('/lock', arguments: cooldown);
            _isShowingLock = false;
          } else {
            print("⚠️ Navigator still not available after retry");
            _isShowingLock = false;
          }
        });
        return;
      }
      
      _lockVisible = true;
      print("🔒 Showing lock screen for ${cooldown['reason']} - app: ${cooldown['appName']} (allowBackNavigation: $allowBackNavigation)");
      
      // ✅ CRITICAL: Clear active app cache to STOP usage accumulation while lock screen is visible
      _clearActiveAppCache();
      
      // ✅ FIX: Use different navigation strategy based on context
      // - If allowBackNavigation=true: Use push() so users can go back to see stats
      // - If allowBackNavigation=false: Use pushAndRemoveUntil() to block selected apps
      final lockScreenRoute = MaterialPageRoute(
        builder: (_) => LockScreen(
          reason: cooldown['reason'],
          cooldownSeconds: cooldown['remainingSeconds'],
          appName: cooldown['appName'],
          mlSource: cooldown['mlSource'] as String?, // ✅ Pass ML source
          mlConfidence: (cooldown['mlConfidence'] as num?)?.toDouble(), // ✅ Pass ML confidence
        ),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/lock_screen'),
      );
      
      if (allowBackNavigation) {
        // ✅ In ReFocus app: Allow back navigation to see stats/homepage
        navigator.push(lockScreenRoute).then((_) {
          _lockVisible = false;
          _isShowingLock = false;
        }).catchError((error) {
          _lockVisible = false;
          _isShowingLock = false;
          print("⚠️ Error showing lock screen: $error");
        });
      } else {
        // ✅ On selected app: Block navigation, clear stack to prevent app access
        navigator.pushAndRemoveUntil(
          lockScreenRoute,
          (route) => false, // Clear all previous routes
        ).then((_) {
          _lockVisible = false;
          _isShowingLock = false;
        }).catchError((error) {
          _lockVisible = false;
          _isShowingLock = false;
          print("⚠️ Error showing lock screen: $error");
        });
      }
    } catch (e) {
      _lockVisible = false;
      _isShowingLock = false;
      print("⚠️ Exception showing lock screen: $e");
    }
  }

  /// Request overlay permission
  static Future<void> requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
    } catch (e) {
      print("⚠️ Error requesting overlay permission: $e");
    }
  }

  /// Check if monitoring is active
  static bool get isMonitoring => _isMonitoring;
}