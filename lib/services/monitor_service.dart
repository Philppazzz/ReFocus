import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/selected_apps.dart';
import 'package:refocus_app/services/lstm_bridge.dart';
import 'package:refocus_app/database_helper.dart';
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
  
  // Cache to reduce database calls
  // ✅ Reduced to 1 second for faster usage accumulation (especially for small limits like 1.1 minutes)
  static Map<String, dynamic>? _cachedStats;
  static DateTime? _lastStatsFetch;
  static const _statsCacheDuration = Duration(seconds: 1);
  
  // Cache stats for 1 second to avoid excessive database queries
  static Future<bool> _shouldUseCache() async {
    return true; // Always use cache (1 second duration)
  }

  /// Manually trigger limit check (for testing)
  /// Clears cache to ensure fresh data check
  static Future<void> checkLimits() async {
    // Clear cache to force fresh stats fetch
    _cachedStats = null;
    _lastStatsFetch = null;
    
    // Reset lock visibility flag to allow new lock screen if needed
    _lockVisible = false;
    
    // Trigger check immediately
    await _checkForegroundApp();
  }
  
  /// Clear lock state (allows lock screen to be re-shown)
  static void clearLockState() {
    _lockVisible = false;
    print("🔓 Lock state cleared in MonitorService");
  }
  
  /// Clear stats cache (force fresh data fetch)
  static void clearStatsCache() {
    _cachedStats = null;
    _lastStatsFetch = null;
    print("🔄 Stats cache cleared");
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

    print("🔍 Starting app monitor service...");
    _isMonitoring = true;

    // Ensure usage permission for foreground detection
    _usagePermissionGranted = await UsageService.requestPermission();
    if (!_usagePermissionGranted) {
      print('⚠️ Usage access not granted – foreground detection may fail');
    }

    // Start a foreground service to keep the Dart isolate alive in background
    // This is the proper Android way to keep app running in background
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'ReFocus is monitoring',
          notificationText: 'Keeping you focused on your goals',
        );
        print("✅ Foreground service started");
      } else {
        print("ℹ️ Foreground service already running");
      }
    } catch (e) {
      print('⚠️ Unable to start foreground service: $e');
      // Continue even if service fails - timer will still work while app is in memory
    }

    // Start monitoring with optimized intervals
    // Check every 1 second for more reliable locking (faster response to violations)
    _monitorTimer?.cancel(); // Cancel any existing timer first
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isMonitoring) {
        print("⚠️ Monitoring timer running but _isMonitoring is false - canceling");
        timer.cancel();
        return;
      }
      
      try {
        await _checkForegroundApp();
      } catch (e) {
        print("⚠️ Error in monitoring loop: $e");
        // Continue monitoring even if one check fails
      }
    });
    
    print("✅ Monitoring timer started - will check every 1 second");
    
    // Start periodic LSTM training snapshot logging (every 5 minutes)
    _startLSTMTrainingLogger();
    
    print("✅ Monitoring service started - tracking active");
  }

  /// Start periodic LSTM training data logger
  static Timer? _lstmLoggerTimer;
  static void _startLSTMTrainingLogger() {
    _lstmLoggerTimer?.cancel();
    // Log training snapshot every 5 minutes
    _lstmLoggerTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      try {
        await LSTMBridge.logTrainingSnapshot();
      } catch (e) {
        print("⚠️ Error logging LSTM training snapshot: $e");
      }
    });
  }

  /// Stop monitoring
  static void stopMonitoring() {
    print("ℹ️ Stopping app monitor service...");
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _lstmLoggerTimer?.cancel();
    _lstmLoggerTimer = null;
    _cachedStats = null;
    _lastStatsFetch = null;
    
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
    print("🔄 RestartMonitoring called - _isMonitoring = $_isMonitoring");
    
    if (_isMonitoring) {
      // Service is already running, just verify foreground service is active
      try {
        final isServiceRunning = await FlutterForegroundTask.isRunningService;
        if (!isServiceRunning) {
          print("⚠️ Service was killed - restarting foreground service...");
          // Restart foreground service without stopping monitoring
          try {
            await FlutterForegroundTask.startService(
              notificationTitle: 'ReFocus is monitoring',
              notificationText: 'Keeping you focused on your goals',
            );
            print("✅ Foreground service restarted");
          } catch (e) {
            print("⚠️ Could not restart foreground service: $e");
          }
        } else {
          print("✅ Foreground service is running");
        }
      } catch (e) {
        print("⚠️ Error checking service status: $e");
        // Try to restart foreground service anyway
        try {
          await FlutterForegroundTask.startService(
            notificationTitle: 'ReFocus is monitoring',
            notificationText: 'Keeping you focused on your goals',
          );
          print("✅ Foreground service started");
        } catch (e2) {
          print("⚠️ Could not restart service: $e2");
        }
      }
      
      // ✅ CRITICAL: Verify timer is running
      if (_monitorTimer == null || !_monitorTimer!.isActive) {
        print("⚠️ Monitoring timer is not active - recreating timer...");
        _monitorTimer?.cancel();
        _monitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
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
      print("🔄 Forcing immediate check after restart...");
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

  /// Get cached stats or fetch fresh ones
  /// ✅ CRITICAL: Pass currentForegroundApp for real-time usage tracking
  static Future<Map<String, dynamic>> _getStats({
    bool updateSessionTracking = true,
    String? currentForegroundApp,
  }) async {
    final now = DateTime.now();
    final useCache = await _shouldUseCache();
    
    // Return cached if still valid
    if (useCache && 
        _cachedStats != null && 
        _lastStatsFetch != null &&
        now.difference(_lastStatsFetch!) < _statsCacheDuration) {
      return _cachedStats!;
    }

    // Fetch fresh stats (when cache expired)
    // ✅ CRITICAL: Pass currentForegroundApp for real-time usage accumulation
    // Pass updateSessionTracking flag to prevent session restart during cooldown
    _cachedStats = await UsageService.getUsageStatsWithEvents(
      SelectedAppsManager.selectedApps,
      currentForegroundApp: currentForegroundApp, // ✅ Enable real-time tracking!
      updateSessionTracking: updateSessionTracking,
    );
    _lastStatsFetch = now;
    
    return _cachedStats!;
  }

  /// Check foreground app and enforce limits
  static Future<void> _checkForegroundApp() async {
    try {
      // ✅ CRITICAL: If lock screen is visible, STOP all tracking to prevent usage accumulation
      if (_lockVisible) {
        print("🔒 Lock screen visible - PAUSING all tracking (preventing usage accumulation)");
        return;
      }
      
      // ✅ CRITICAL: If Emergency Override is enabled, stop all tracking and skip violations
      final isOverrideEnabled = AppState().isOverrideEnabled;
      if (isOverrideEnabled) {
        print("🚨 Emergency Override: ON - All tracking paused, no violations enforced");
        return; // Don't track usage, don't check violations, don't show lock screens
      }
      
      // ✅ DEBUG: Log when override is OFF (only occasionally to avoid spam)
      // Removed constant logging - only log when override is ON
      
      final prefs = await SharedPreferences.getInstance();
      
      // DEBUG: Show current session status
      final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      final isSessionLimitExceeded = await LockStateManager.isSessionLimitExceeded();
      print("🔍 Session: ${sessionMinutes.toStringAsFixed(1)}m | Exceeded: $isSessionLimitExceeded");
      
      // Get current foreground app
      final foregroundApp = await platform.invokeMethod<String>('getForegroundApp');

      if (foregroundApp == null || foregroundApp.isEmpty) {
        // No app in foreground - user might be on home screen
        return;
      }

      // Identify our own app and selected apps
      final isOwnApp = foregroundApp == 'com.example.refocus_app';

      final selectedPackages = SelectedAppsManager.selectedApps
          .map((a) => a['package'])
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toSet();
      final isSelected = selectedPackages.contains(foregroundApp);

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
      // This must work even when user is in other apps
      // ALSO: Determine if session tracking should be updated (NO during cooldown)
      final cooldownInfo = await LockStateManager.getActiveCooldown();
      final hasActiveCooldown = cooldownInfo != null;
      final updateSessionTracking = !hasActiveCooldown; // Only update session if no cooldown active
      if (cooldownInfo != null) {
        print("🔒 Active cooldown detected: ${cooldownInfo['reason']}");
        
        // ALWAYS bring app to foreground if user is on ANY selected app (even if locked)
        // This ensures lock screen appears reliably
        if (isSelected && !isOwnApp) {
          print("🚨 User on locked app - bringing ReFocus to front immediately");
          await _bringAppToForeground();
          await Future.delayed(const Duration(milliseconds: 500)); // Reduced delay for faster response
        }
        
        // ✅ CRITICAL: Only show lock screen when user tries to open selected apps
        // Don't force show in ReFocus app - let user navigate freely to view stats
        if (!_lockVisible) {
          if (!isOwnApp && isSelected) {
            // User is on a locked app - MUST show lock screen to block access
            Future.delayed(const Duration(milliseconds: 200), () {
              _showLockScreen(cooldownInfo, force: true, allowBackNavigation: false);
            });
          }
          // ✅ REMOVED: Auto-showing lock screen in ReFocus app
          // User can navigate freely in ReFocus to view stats, lock screen will show if they try selected apps
        }
        return; // Don't check for new violations if already locked
      } else {
        // No active cooldown - reset lock visibility flag
        if (_lockVisible) {
          _lockVisible = false;
        }
      }

      // PRIORITY 2: Update session activity ONLY for selected apps
      // ✅ CRITICAL: Session tracking ONLY happens for selected apps (not all phone apps)
      // IMPORTANT: Session continues across app switches - switching between selected apps
      // doesn't reset the session timer. Only switching to unselected apps or cooldown resets it.
      if (isSelected) {
        await LockStateManager.updateSessionActivity();
        print("📱 Session activity updated for $foregroundApp (selected app only - session continues across switches)");
      }
      // ✅ NO session tracking for ReFocus app or non-selected apps!

      // PRIORITY 2.5: Check and send warnings ONLY for selected apps
      if (isSelected) {
        final stats = await _getStats(
          updateSessionTracking: updateSessionTracking,
          currentForegroundApp: foregroundApp, // ✅ Pass for real-time tracking
        );
        final dailyHours = (stats['daily_usage_hours'] as num?)?.toDouble() ?? 0.0;
        final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
        final totalUnlocks = (stats['most_unlock_count'] as num?)?.toInt() ?? 0;
        String? mostUnlockedAppName = (stats['most_unlock_app'] as String?)?.trim();
        if (mostUnlockedAppName != null &&
            (mostUnlockedAppName.isEmpty || mostUnlockedAppName.toLowerCase() == 'none')) {
          mostUnlockedAppName = null;
        }
        final remainingUnlocks = await LockStateManager.getRemainingUnlocks(totalUnlocks);

        String? currentAppName;
        if (isSelected) {
          try {
            final app = SelectedAppsManager.selectedApps.firstWhere(
              (app) => app['package'] == foregroundApp,
            );
            currentAppName = app['name'] ?? app['package'];
          } catch (_) {
            currentAppName = null;
          }
        }

        // Get thresholds from LockStateManager
        final thresholds = await LockStateManager.getThresholds();
        final dailyLimit = thresholds['dailyHours'] as double;
        final sessionLimit = thresholds['sessionMinutes'] as double;
        final unlockLimit = thresholds['unlockLimit'] as int;

        // ✅ PRIORITY: Check and send warnings BEFORE checking violations
        // This ensures users are ALWAYS warned before they get locked
        await NotificationService.checkAndSendWarnings(
          dailyHours: dailyHours,
          sessionMinutes: sessionMinutes,
          unlockCount: totalUnlocks,
          dailyLimit: dailyLimit,
          sessionLimit: sessionLimit,
          unlockLimit: unlockLimit,
          currentAppName: currentAppName,
          mostUnlockedAppName: mostUnlockedAppName,
          remainingUnlocks: remainingUnlocks,
        );
        
        // ✅ CRITICAL: Send final warning if user is VERY close to limit (95%+)
        // This is a last-minute alert right before violation occurs
        final dailyPercentage = dailyHours / dailyLimit;
        final sessionPercentage = sessionMinutes / sessionLimit;
        final unlockPercentage = totalUnlocks / unlockLimit;
        
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
        
        // Final warning for unlock limit (95%+)
        if (unlockPercentage >= 0.95 && unlockPercentage < 1.0) {
          final warningKey = 'unlock_final_warning_$today';
          if (!(prefs.getBool(warningKey) ?? false)) {
            await NotificationService.showUnlockLimitWarning(
              totalUnlocks,
              unlockLimit,
              warningLevel: 95,
              mostUnlockedAppName: mostUnlockedAppName,
              remainingUnlocks: remainingUnlocks,
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
      }

      // PRIORITY 3: Check for violations
      // ✅ CRITICAL: Check in order of severity (most severe first)
      // 1. Daily limit (most severe - locks until tomorrow)
      // 2. Session limit (medium - locks for cooldown)
      // 3. Unlock limit (medium - locks for cooldown)
      Map<String, dynamic>? violation;
      
      // Get thresholds first (for logging)
      final thresholds = await LockStateManager.getThresholds();
      
      // ✅ CRITICAL: Clear cache before violation checks to ensure fresh unlock counts
      // Unlocks can happen quickly and cache might have stale data
      clearStatsCache();
      
      // Get stats first (needed for daily limit check)
      // ✅ CRITICAL: Pass foregroundApp for real-time usage tracking
      final stats = await _getStats(
        updateSessionTracking: updateSessionTracking,
        currentForegroundApp: foregroundApp, // ✅ Enable real-time tracking!
      );
      final dailyHours = (stats['daily_usage_hours'] as num?)?.toDouble() ?? 0.0;
      final totalUnlocks = (stats['most_unlock_count'] as num?)?.toInt() ?? 0;

      print("📊 Current stats - Daily: ${dailyHours.toStringAsFixed(4)}h (${(dailyHours * 60).toStringAsFixed(1)}m) / ${thresholds['dailyHours']}h (${(thresholds['dailyHours'] * 60).toStringAsFixed(1)}m), Unlocks: $totalUnlocks / ${thresholds['unlockLimit']}");
      print("   🔍 Foreground app: $foregroundApp | Is selected: $isSelected");
      print("   🔍 Checking unlock limit: $totalUnlocks unlocks (limit: ${thresholds['unlockLimit']})");

      // Check limits using hybrid system: LSTM if enabled, fallback to rule-based
      // This checks daily and unlock limits
      violation = await LSTMBridge.checkLimitsHybrid(
        dailyHours: dailyHours,
        totalUnlocks: totalUnlocks,
      );
      
      // If no daily/unlock violation, check session limit
      if (violation == null && await LockStateManager.isSessionLimitExceeded()) {
        violation = {
          'type': 'session_limit',
          'message': 'Continuous usage limit reached',
        };
        print("🚨 SESSION LIMIT EXCEEDED!");
      }

      // PRIORITY 4: Handle violation if detected - MUST TRIGGER INSTANTLY
      if (violation != null) {
        final limitType = violation['type'];
        print("🚨🚨🚨 VIOLATION DETECTED: $limitType 🚨🚨🚨");

        // Get stats for logging
        final stats = await _getStats(
          updateSessionTracking: updateSessionTracking,
          currentForegroundApp: foregroundApp, // ✅ Pass for real-time tracking
        );
        final dailyHours = (stats['daily_usage_hours'] as num?)?.toDouble() ?? 0.0;
        final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
        final totalUnlocks = (stats['most_unlock_count'] as num?)?.toInt() ?? 0;
        
        if (limitType == 'unlock_limit') {
          print("   📱 Unlock limit reached! User opened an app $totalUnlocks times (limit: ${thresholds['unlockLimit']})");
        }

        // Resolve app name (use most unlocked app for unlock limit, current app for session)
        String appName = 'App';
        String? appPackage;
        
        if (limitType == 'unlock_limit') {
          // For unlock limit, use the most unlocked app
          appName = stats['most_unlock_app'] ?? 'App';
          // Find package for this app
          final app = SelectedAppsManager.selectedApps.firstWhere(
            (a) => a['name'] == appName,
            orElse: () => {'package': ''},
          );
          appPackage = app['package'];
        } else if (limitType == 'session_limit') {
          // For session limit, use current foreground app
          final app = SelectedAppsManager.selectedApps.firstWhere(
            (app) => app['package'] == foregroundApp,
            orElse: () => {'name': 'App', 'package': ''},
          );
          appName = app['name'] ?? 'App';
          appPackage = app['package'];
        } else if (limitType == 'daily_limit') {
          appName = 'All Apps';
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

          print("🔒 Daily lock activated (silent - will show when user tries selected app)");

          // ✅ FIX: Don't show lock screen immediately!
          // Instead, let PRIORITY 1 (active cooldown enforcement) handle it
          // The lock screen will appear when user tries to open a selected app
          // This prevents showing the lock screen when user is in ReFocus app or non-selected apps
          
          // ✅ CRITICAL: Only show lock screen when user tries to open selected apps
          // Don't force show in ReFocus app - let user navigate freely to view stats
          if (isSelected && !isOwnApp) {
            await _bringAppToForeground();
            await Future.delayed(const Duration(milliseconds: 500));
            
            // User is on selected app - MUST show lock screen to block access
            _showLockScreen({
              'reason': 'daily_limit',
              'remainingSeconds': -1,
              'appName': appName,
            }, force: true, allowBackNavigation: false);
          }
          // ✅ REMOVED: Auto-showing lock screen in ReFocus app for daily limit
          // User can navigate freely in ReFocus to view stats, lock screen will show if they try selected apps
          
          return;
        }

        // Handle session/unlock violations
        print("📝 Recording violation for $limitType");
        await LockStateManager.recordViolation(limitType);

        // Get cooldown duration
        final cooldownSeconds = await LockStateManager.getCooldownSeconds(limitType);
        print("⏱️ Cooldown duration: ${cooldownSeconds}s");

        // Apply side-effects (reset session timer or unlock base)
        await LockStateManager.onViolationApplied(
          limitType: limitType,
          currentMostUnlockedCount: limitType == 'unlock_limit' ? totalUnlocks : 0,
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
          sessionMinutes: limitType == 'session_limit' ? sessionMinutes : null,
          unlockCount: limitType == 'unlock_limit' ? totalUnlocks : null,
          cooldownSeconds: cooldownSeconds,
        );

        // Notify
        await NotificationService.showLimitReachedNotification(limitType);
        await NotificationService.showCooldownNotification(cooldownSeconds ~/ 60);

        print("🔒 Cooldown set - showing lock screen immediately");

        // ✅ CRITICAL: For unlock_limit, ALWAYS bring app to foreground
        // Unlock violations trigger when user OPENS an app, so we must intercept immediately
        // For session_limit, only bring to foreground if user is on a selected app
        if (limitType == 'unlock_limit') {
          // Unlock limit: ALWAYS bring to foreground (happens when opening ANY app)
          await _bringAppToForeground();
          await Future.delayed(const Duration(milliseconds: 500));
          print("🚨 Unlock limit: Brought app to foreground to show lock");
        } else if (isSelected && !isOwnApp) {
          // Session limit: Only bring to foreground if user is on selected app
          await _bringAppToForeground();
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        // Show lock screen immediately - don't wait for user to be in our app
        _showLockScreen({
          'reason': limitType,
          'remainingSeconds': cooldownSeconds,
          'appName': appName,
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

  static void _showLockScreen(Map<String, dynamic> cooldown, {bool force = false, bool allowBackNavigation = false}) {
    // ✅ CRITICAL: Prevent duplicate lock screens to stop glitching timer
    if (_lockVisible) {
      print("⚠️ Lock screen already visible - BLOCKING duplicate (force=$force)");
      return;
    }
    
    final navigator = Nav.navigatorKey.currentState;
    if (navigator == null) {
      print("⚠️ Navigator not available - cannot show lock screen");
      return;
    }
    
    _lockVisible = true;
    print("🔒 Showing lock screen for ${cooldown['reason']} - app: ${cooldown['appName']} (allowBackNavigation: $allowBackNavigation)");
    
    // ✅ CRITICAL: Clear active app cache to STOP usage accumulation while lock screen is visible
    _clearActiveAppCache();
    
    // ✅ FIX: Use different navigation strategy based on context
    // - If allowBackNavigation=true: Use push() so users can go back to see stats
    // - If allowBackNavigation=false: Use pushAndRemoveUntil() to block selected apps
    try {
      final lockScreenRoute = MaterialPageRoute(
        builder: (_) => LockScreen(
          reason: cooldown['reason'],
          cooldownSeconds: cooldown['remainingSeconds'],
          appName: cooldown['appName'],
        ),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/lock_screen'),
      );
      
      if (allowBackNavigation) {
        // ✅ In ReFocus app: Allow back navigation to see stats/homepage
        navigator.push(lockScreenRoute).then((_) {
          _lockVisible = false;
          print("🔓 Lock screen dismissed - user can view stats");
        }).catchError((error) {
          _lockVisible = false;
          print("⚠️ Error showing lock screen: $error");
        });
      } else {
        // ✅ On selected app: Block navigation, clear stack to prevent app access
        navigator.pushAndRemoveUntil(
          lockScreenRoute,
          (route) => false, // Clear all previous routes
        ).then((_) {
          _lockVisible = false;
          print("🔓 Lock screen dismissed");
        }).catchError((error) {
          _lockVisible = false;
          print("⚠️ Error showing lock screen: $error");
        });
      }
    } catch (e) {
      _lockVisible = false;
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