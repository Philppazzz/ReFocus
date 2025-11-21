import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/hybrid_lock_manager.dart';
import 'package:refocus_app/services/app_lock_manager.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/emergency_service.dart';
import 'package:refocus_app/services/app_name_service.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/pages/home_page.dart'; // For AppState
import 'package:refocus_app/utils/category_mapper.dart';

/// Background service for category-based usage monitoring and locking
/// Runs every minute to track usage and enforce limits
class UsageMonitoringService {
  static const platform = MethodChannel('com.example.refocus/monitor');

  // Singleton pattern
  static final UsageMonitoringService _instance = UsageMonitoringService._internal();
  factory UsageMonitoringService() => _instance;
  UsageMonitoringService._internal();

  // Monitoring state
  Timer? _monitorTimer;
  bool _isMonitoring = false;
  
  // ✅ CRITICAL: Add synchronization lock to prevent race conditions
  bool _isLocking = false;

  // Category tracking (in minutes)
  final Map<String, int> _dailyUsage = {
    'Social': 0,
    'Games': 0,
    'Entertainment': 0,
    'Others': 0,
  };

  final Map<String, int> _sessionUsage = {
    'Social': 0,
    'Games': 0,
    'Entertainment': 0,
    'Others': 0,
  };

  final Map<String, DateTime?> _lastUsedTime = {
    'Social': null,
    'Games': null,
    'Entertainment': null,
    'Others': null,
  };

  // Lock state
  int _violationCount = 0;
  bool _isLocked = false;
  DateTime? _lockUntil;
  String? _lockReason;
  Timer? _unlockTimer;
  Timer? _midnightTimer;
  
  // ✅ Store lock result info for feedback notifications
  String? _lastLockAppName;
  String? _lastLockPredictionSource;
  String? _lastLockReason;
  double? _lastLockModelConfidence;

  // Limits (in minutes)
  static const int SESSION_LIMIT = 60; // 60 mins continuous
  static const int DAILY_LIMIT = 240; // 240 mins total

  // Progressive lock durations (in minutes): 3→5→10→15→20→40→80→160→daily
  static const List<int> LOCK_PROGRESSION = [3, 5, 10, 15, 20, 40, 80, 160];

  // Monitored categories (Others is never locked)
  static const List<String> MONITORED_CATEGORIES = ['Social', 'Games', 'Entertainment'];

  /// Start the monitoring service
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      print('✅ UsageMonitoringService already running');
      return;
    }

    print('🚀 Starting UsageMonitoringService...');

    // Load saved state
    await _loadState();
    
    // ✅ CRITICAL: Check for day change on app start (handles app kill scenario)
    await _checkDayChange();

    // Schedule midnight reset
    _scheduleMidnightReset();

    // Start monitoring timer (every 1 minute)
    // ✅ CRITICAL: Use try-finally to ensure timer cleanup on errors
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        await _monitorUsage();
      } catch (e) {
        print('⚠️ Error in monitoring timer: $e');
        // Timer continues even on error
      }
    });

    _isMonitoring = true;
    print('✅ UsageMonitoringService started - monitoring every minute');
  }
  
  /// ✅ CRITICAL: Check if day has changed (handles app kill scenario)
  /// If app was killed before midnight, this ensures daily reset happens on next start
  Future<void> _checkDayChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final lastResetDate = prefs.getString('last_midnight_reset_date');
      
      if (lastResetDate != null && lastResetDate != today) {
        print('🌅 Day change detected ($lastResetDate → $today) - performing reset');
        await _resetAtMidnight();
      } else if (lastResetDate == null) {
        // First run - set today as last reset date
        await prefs.setString('last_midnight_reset_date', today);
      }
    } catch (e) {
      print('⚠️ Error checking day change: $e');
    }
  }

  /// Stop the monitoring service
  /// ✅ CRITICAL: Use try-finally to ensure all timers are cancelled
  void stopMonitoring() {
    print('⏹️ Stopping UsageMonitoringService...');
    try {
      _monitorTimer?.cancel();
      _unlockTimer?.cancel();
      _midnightTimer?.cancel();
      _isMonitoring = false;
      _isLocking = false; // Reset lock flag
      print('✅ UsageMonitoringService stopped');
    } catch (e) {
      print('⚠️ Error stopping monitoring service: $e');
      // Force cleanup even on error
      _monitorTimer?.cancel();
      _unlockTimer?.cancel();
      _midnightTimer?.cancel();
      _isMonitoring = false;
      _isLocking = false;
    }
  }

  /// Core monitoring logic - runs every minute
  Future<void> _monitorUsage() async {
    // ✅ CRITICAL: Prevent concurrent execution to avoid race conditions
    if (_isLocking) {
      print('⚠️ Monitoring already in progress, skipping duplicate call');
      return;
    }
    
    _isLocking = true;
    try {
      // ✅ CRITICAL: Check Emergency Override FIRST - if active, stop ALL tracking
      final isEmergencyActive = await EmergencyService.isEmergencyActive();
      final isOverrideEnabled = AppState().isOverrideEnabled;
      if (isEmergencyActive || isOverrideEnabled) {
        print("🚨 Emergency Override: ACTIVE - All tracking paused");
        return; // Don't track usage, don't check locks, don't update anything
      }
      
      // Get current foreground app
      final String? currentApp = await _getForegroundApp();
      if (currentApp == null || currentApp.isEmpty) {
        print('📱 No foreground app detected');
        return;
      }

      // Skip system apps and ReFocus itself
      // ✅ Messaging apps are now tracked as "Others" category
      if (CategoryMapper.isSystemApp(currentApp) ||
          currentApp == 'com.example.refocus_app') {
        return;
      }

      // Get category from database
      final String category = await _getCategoryFromDB(currentApp);

      // ✅ CRITICAL: Force database update before reading usage (ensures latest data)
      // UsageService processes Android UsageStats and saves to database
      // This ensures we have the most up-to-date usage data before making lock decisions
      try {
        await UsageService.getUsageStatsWithEvents(
          currentForegroundApp: currentApp,
          updateSessionTracking: true,
        );
        print('💾 Forced database update before lock check for $currentApp');
      } catch (e) {
        print('⚠️ Error forcing database update: $e - continuing with existing data');
        // Continue anyway - database might still have recent data
      }

      // Get current hour for Decision Tree
      final int hour = DateTime.now().hour;

      // ✅ Update usage counters (reads from database - source of truth)
      await _updateDailyUsage(category);
      await _updateSessionUsage(category);

      // ✅ Hybrid lock prediction: ML when ready, rule-based as fallback
      final lockResult = await HybridLockManager.shouldLockApp(
        category: category,
        dailyUsageMinutes: _dailyUsage[category] ?? 0,
        sessionUsageMinutes: _sessionUsage[category] ?? 0,
        currentHour: hour,
        appName: currentApp, // Pass app name for feedback
        packageName: currentApp,
      );

      final shouldLock = lockResult['shouldLock'] as bool;
      final shouldAskFeedback = lockResult['shouldAskFeedback'] as bool? ?? false;
      final feedbackUsageLevel = lockResult['feedbackUsageLevel'] as int?;
      
      // ✅ Store lock result info for feedback notifications (used when lock is triggered)
      _lastLockAppName = currentApp;
      _lastLockPredictionSource = lockResult['source'] as String? ?? 'rule_based';
      _lastLockReason = lockResult['reason'] as String? ?? 'App locked';
      _lastLockModelConfidence = lockResult['confidence'] as double?;

      
      // Check for proactive feedback prompt (learning mode)
      if (!shouldLock && shouldAskFeedback && feedbackUsageLevel != null) {
        // UI layer should check this and show ProactiveFeedbackDialog
      }

      // Send predictive risk warning if high risk detected (approaching limit)
      if (shouldLock && (_dailyUsage[category] ?? 0) < 200) {
        // High risk but not locked yet
        await NotificationService.showPeakRiskWarning(
          category,
          _dailyUsage[category] ?? 0,
        );
      }

      // Log usage data to database (for future ML if needed)
      await _logUsageData(category, hour, shouldLock);

      // ✅ CRITICAL: Check and enforce limits (only if not already locked)
      // Also check if MonitorService is already handling a lock to prevent double-lock
      if (!_isLocked) {
        // Check if MonitorService has an active lock
        final cooldownInfo = await LockStateManager.getActiveCooldown();
        final hasActiveLock = cooldownInfo != null;
        if (!hasActiveLock) {
          await _checkAndEnforceLimits(category);
        } else {
          print('⚠️ Active lock detected in LockStateManager, skipping limit check to prevent double-lock');
        }
      }

      // Save state
      await _saveState();

    } catch (e) {
      print('⚠️ Error in monitoring loop: $e');
    } finally {
      // ✅ CRITICAL: Always release lock, even on error
      _isLocking = false;
    }
  }

  /// Update daily usage counter for category
  /// ✅ CRITICAL: Database is the source of truth - always sync from database
  /// This ensures UsageMonitoringService matches what frontend displays and lock decisions use
  Future<void> _updateDailyUsage(String category) async {
    // ✅ CRITICAL: Always get accurate daily usage from database (source of truth)
    // Database is updated by UsageService.getUsageStatsWithEvents() which processes Android UsageStats
    // This ensures UsageMonitoringService matches what frontend displays and what lock decisions use
    try {
      final db = DatabaseHelper.instance;
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      final dbMinutes = (categoryUsage[category] ?? 0.0).round();
      
      // ✅ CRITICAL: Always sync in-memory counter with database (database is source of truth)
      // Don't increment in-memory - database already has the accurate value from UsageService
      // UsageService processes events and saves to database, so we just read from database
      _dailyUsage[category] = dbMinutes;
      print('📈 Daily usage synced from DB - $category: ${_dailyUsage[category]} mins (source of truth)');
    } catch (e) {
      // Fallback: keep current in-memory value (don't increment - might be stale)
      print('⚠️ Daily usage sync failed for $category: $e - keeping current value: ${_dailyUsage[category]} mins');
    }
  }

  /// Update session usage counter with 5-minute inactivity threshold (matches LockStateManager)
  /// ✅ CRITICAL: Session continues across monitored categories (Social/Games/Entertainment)
  /// ✅ Session resets only if NO monitored category has been used for 5+ minutes
  /// ✅ CRITICAL FIX: Now syncs with LockStateManager.getCurrentSessionMinutes() for accuracy
  Future<void> _updateSessionUsage(String category) async {
    final DateTime now = DateTime.now();
    const int inactivityThresholdMinutes = 5; // ✅ Match LockStateManager's 5-minute threshold
    
    // ✅ CRITICAL: For monitored categories, sync with LockStateManager's actual accumulated time
    // This ensures session usage matches what frontend displays and what lock decisions use
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    if (monitoredCategories.contains(category)) {
      // ✅ CRITICAL FIX: Get actual session minutes from LockStateManager (source of truth)
      // This tracks accumulated time in milliseconds, converted to minutes
      final actualSessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      
      // ✅ For monitored categories, session is shared - all 3 categories have the same value
      // LockStateManager already handles the 5-minute inactivity threshold and combined tracking
      final sessionMinutesInt = actualSessionMinutes.round();
      
      // Update all monitored categories with the same value (shared session)
      for (final cat in monitoredCategories) {
        _sessionUsage[cat] = sessionMinutesInt;
        _lastUsedTime[cat] = now; // Update last used time for all monitored categories
      }
      
      print('📊 Session usage synced from LockStateManager - All monitored categories: ${sessionMinutesInt} mins (actual accumulated time)');
    } else {
      // Others category - independent tracking (not part of shared session)
      final DateTime? lastUsed = _lastUsedTime[category];
      if (lastUsed != null && now.difference(lastUsed).inMinutes < inactivityThresholdMinutes) {
        // Continue session for Others category
        _sessionUsage[category] = (_sessionUsage[category] ?? 0) + 1;
      } else {
        // Start new session for Others category
        _sessionUsage[category] = 1;
      }
      _lastUsedTime[category] = now;
    }
  }

  /// Check limits and trigger locks if exceeded
  /// ✅ Now uses AppLockManager for category-specific thresholds
  Future<void> _checkAndEnforceLimits(String category) async {
    // ✅ CRITICAL: Check Emergency Override FIRST - if active, don't enforce limits
    final isEmergencyActive = await EmergencyService.isEmergencyActive();
    final isOverrideEnabled = AppState().isOverrideEnabled;
    if (isEmergencyActive || isOverrideEnabled) {
      print("🚨 Emergency Override: ACTIVE - Skipping limit enforcement");
      return; // Don't enforce any limits during emergency
    }
    
    // Only monitor Social/Games/Entertainment (Others never triggers locks)
    if (!MONITORED_CATEGORIES.contains(category)) {
      print('✅ $category is not monitored - no limit check');
      return;
    }

    // ✅ SHARED LIMITS: Calculate COMBINED usage across ALL monitored categories
    final int combinedDailyMins = (_dailyUsage['Social'] ?? 0) + 
                                   (_dailyUsage['Games'] ?? 0) + 
                                   (_dailyUsage['Entertainment'] ?? 0);
    
    // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
    // This ensures lock decisions use actual accumulated session time with 5-minute inactivity threshold
    final int combinedSessionMins = (await LockStateManager.getCurrentSessionMinutes()).round();
    
    final int currentHour = DateTime.now().hour;

    // ✅ Get shared thresholds (all monitored categories have same limits)
    final thresholds = await AppLockManager.getThresholds(category);
    int dailyLimit = thresholds['daily']!;
    int sessionLimit = thresholds['session']!;

    // Apply peak hours penalty (6 PM - 11 PM)
    if (currentHour >= 18 && currentHour <= 23) {
      dailyLimit = (dailyLimit * 0.85).round();
      sessionLimit = (sessionLimit * 0.85).round();
    }


    // Send warnings at key thresholds for daily usage
    final dailyRemaining = dailyLimit - combinedDailyMins;
    if (dailyRemaining <= 15 && dailyRemaining > 5) {
      // 15 mins remaining - warning handled by existing notification system
    } else if (dailyRemaining <= 5 && dailyRemaining > 1) {
      // 5 mins remaining - warning handled by existing notification system
    } else if (dailyRemaining <= 1) {
      // 1 min remaining - warning handled by existing notification system
    }

    // Send warnings at key thresholds for session usage
    final sessionRemaining = sessionLimit - combinedSessionMins;
    if (sessionRemaining <= 5 && sessionRemaining > 1) {
      // 5 mins remaining - warning handled by existing notification system
    } else if (sessionRemaining <= 1) {
      // 1 min remaining - warning handled by existing notification system
    }

    // ✅ Use stored lock result info from _monitorUsage (set before _checkAndEnforceLimits is called)
    final appName = _lastLockAppName;
    final predictionSource = _lastLockPredictionSource ?? 'rule_based';
    final lockReason = _lastLockReason ?? 'App locked';
    final modelConfidence = _lastLockModelConfidence;

    // VIOLATION 1: Session Limit exceeded (COMBINED across all monitored categories)
    if (combinedSessionMins >= sessionLimit) {
      print('🚨 COMBINED SESSION LIMIT EXCEEDED! (${combinedSessionMins}min >= ${sessionLimit}min)');
      print('   Social: ${_sessionUsage['Social']}min, Games: ${_sessionUsage['Games']}min, Entertainment: ${_sessionUsage['Entertainment']}min');
      _violationCount++;
      await _triggerSessionLock(category, appName: appName, predictionSource: predictionSource, lockReason: lockReason, modelConfidence: modelConfidence);
      return;
    }

    // VIOLATION 2: Daily Limit exceeded (COMBINED across all monitored categories)
    if (combinedDailyMins >= dailyLimit) {
      print('🚨 COMBINED DAILY LIMIT EXCEEDED! (${combinedDailyMins}min >= ${dailyLimit}min)');
      print('   Social: ${_dailyUsage['Social']}min, Games: ${_dailyUsage['Games']}min, Entertainment: ${_dailyUsage['Entertainment']}min');
      await _triggerDailyLock(category, appName: appName, predictionSource: predictionSource, lockReason: lockReason, modelConfidence: modelConfidence);
      return;
    }

    print('✅ No violations (Combined: ${combinedDailyMins}/${dailyLimit}min daily, ${combinedSessionMins}/${sessionLimit}min session)');
  }

  /// Trigger session-based lock with progressive duration
  Future<void> _triggerSessionLock(String category, {String? appName, String? predictionSource, String? lockReason, double? modelConfidence}) async {
    print('🔒 Triggering session lock (violation #$_violationCount)...');

    // Get progressive lock duration
    final int lockMinutes = _getProgressiveLockDuration(_violationCount);

    // If lock duration exceeds last tier, trigger daily lock instead
    if (lockMinutes == 999) {
      print('⚠️ Max violations reached - triggering daily lock');
      await _triggerDailyLock(category, appName: appName, predictionSource: predictionSource, lockReason: lockReason, modelConfidence: modelConfidence);
      return;
    }

    // Set lock state
    _lockUntil = DateTime.now().add(Duration(minutes: lockMinutes));
    _isLocked = true;
    _lockReason = 'session_limit';

    // Lock ALL monitored categories
    await _lockMonitoredApps();

    // Show lock overlay
    await _showLockOverlay(
      reason: 'session_limit',
      duration: lockMinutes,
      violationNumber: _violationCount,
      category: category,
    );

    // Send notification
    await NotificationService.showSessionLockNotification(
      lockMinutes,
      _violationCount,
      category,
    );

    // ✅ Send lock feedback notification (works from any app)
    if (appName != null) {
      try {
        final displayAppName = await AppNameService.getAppName(appName);
        final combinedDailyMins = (_dailyUsage['Social'] ?? 0) + 
                                  (_dailyUsage['Games'] ?? 0) + 
                                  (_dailyUsage['Entertainment'] ?? 0);
        // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
        // This ensures feedback reflects actual accumulated session time with 5-minute inactivity threshold
        final combinedSessionMins = (await LockStateManager.getCurrentSessionMinutes()).round();
        
        await NotificationService.showLockFeedbackNotification(
          appName: displayAppName,
          category: category,
          sessionUsageMinutes: combinedSessionMins,
          dailyUsageMinutes: combinedDailyMins,
          lockReason: lockReason ?? 'Session limit exceeded',
          predictionSource: predictionSource ?? 'rule_based',
          modelConfidence: modelConfidence,
        );
      } catch (e) {
        print('⚠️ Error sending lock feedback notification: $e');
      }
    }

    // Log to database
    await _logLockEvent('session_limit', lockMinutes, _violationCount, category);

    // Schedule automatic unlock
    _scheduleUnlock(lockMinutes);

    // Save state
    await _saveState();

    print('✅ Session lock activated for $lockMinutes minutes');
  }

  /// Trigger daily lock (until midnight)
  Future<void> _triggerDailyLock(String category, {String? appName, String? predictionSource, String? lockReason, double? modelConfidence}) async {
    print('🔒 Triggering daily lock (until midnight)...');

    // Calculate midnight
    final DateTime now = DateTime.now();
    final DateTime midnight = DateTime(now.year, now.month, now.day + 1);

    // Set lock state
    _lockUntil = midnight;
    _isLocked = true;
    _lockReason = 'daily_limit';

    // Lock ALL monitored categories
    await _lockMonitoredApps();

    // Show lock overlay
    await _showLockOverlay(
      reason: 'daily_limit',
      duration: 'until midnight',
      violationNumber: 0,
      category: category,
    );

    // Send notification
    await _sendDailyLimitNotification(midnight, category);

    // ✅ Send lock feedback notification (works from any app)
    if (appName != null) {
      try {
        final displayAppName = await AppNameService.getAppName(appName);
        final combinedDailyMins = (_dailyUsage['Social'] ?? 0) + 
                                  (_dailyUsage['Games'] ?? 0) + 
                                  (_dailyUsage['Entertainment'] ?? 0);
        // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
        // This ensures feedback reflects actual accumulated session time with 5-minute inactivity threshold
        final combinedSessionMins = (await LockStateManager.getCurrentSessionMinutes()).round();
        
        await NotificationService.showLockFeedbackNotification(
          appName: displayAppName,
          category: category,
          sessionUsageMinutes: combinedSessionMins,
          dailyUsageMinutes: combinedDailyMins,
          lockReason: lockReason ?? 'Daily limit exceeded',
          predictionSource: predictionSource ?? 'rule_based',
          modelConfidence: modelConfidence,
        );
      } catch (e) {
        print('⚠️ Error sending lock feedback notification: $e');
      }
    }

    // Log to database
    await _logLockEvent('daily_limit', 'until_midnight', 0, category);

    // Cancel any existing unlock timer
    _unlockTimer?.cancel();

    // Save state
    await _saveState();

    print('✅ Daily lock activated until midnight');
  }

  /// Get progressive lock duration based on violation count
  int _getProgressiveLockDuration(int violation) {
    // Progression: 3→5→10→20→40→80→160→Daily
    if (violation <= LOCK_PROGRESSION.length) {
      return LOCK_PROGRESSION[violation - 1];
    } else {
      return 999; // Trigger daily lock
    }
  }

  /// Lock all monitored apps (Social, Games, Entertainment)
  Future<void> _lockMonitoredApps() async {
    print('🔐 Locking all monitored apps...');

    final List<String> appsToLock = await _getMonitoredApps();

    print('📱 Apps to lock: ${appsToLock.length}');
    for (final packageName in appsToLock) {
      await _blockAppAccess(packageName);
    }

    // Save locked apps list
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('locked_apps', appsToLock);
    await prefs.setBool('is_locked', true);

    print('✅ All monitored apps locked');
  }

  /// Get list of monitored apps from database
  Future<List<String>> _getMonitoredApps() async {
    final db = DatabaseHelper.instance;

    // Query apps_catalog for monitored categories
    final apps = await db.database.then((database) =>
      database.rawQuery('''
        SELECT package_name FROM apps_catalog
        WHERE category IN (?, ?, ?) AND is_monitored = 1
      ''', ['Social', 'Games', 'Entertainment'])
    );

    return apps.map((app) => app['package_name'] as String).toList();
  }

  /// Block access to specific app (mark for interception)
  Future<void> _blockAppAccess(String packageName) async {
    // This will be intercepted by the monitoring service
    // When user tries to open this app, lock screen will be shown
    print('🚫 Blocking access to: $packageName');
  }

  /// Schedule automatic unlock after duration
  void _scheduleUnlock(int minutes) {
    print('⏰ Scheduling unlock in $minutes minutes');

    _unlockTimer?.cancel();
    _unlockTimer = Timer(Duration(minutes: minutes), () async {
      await _unlockApps();
    });
  }

  /// Unlock all apps and reset session counters
  Future<void> _unlockApps() async {

    _isLocked = false;
    _lockUntil = null;
    _lockReason = null;

    // Reset session counters (but keep daily counters)
    _sessionUsage['Social'] = 0;
    _sessionUsage['Games'] = 0;
    _sessionUsage['Entertainment'] = 0;
    _sessionUsage['Others'] = 0;

    // Clear locked apps list
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('locked_apps');
    await prefs.setBool('is_locked', false);

    // Dismiss lock overlay
    await _dismissLockOverlay();

    // Send unlock notification
    await _sendUnlockNotification();

    // Save state
    await _saveState();

    print('✅ Apps unlocked, session counters reset');
  }

  /// Reset all counters at midnight
  Future<void> _resetAtMidnight() async {
    print('🌅 MIDNIGHT RESET - New day starting...');

    // Save yesterday's data to daily_summary
    await _saveDailySummary();

    // Reset all counters
    _dailyUsage['Social'] = 0;
    _dailyUsage['Games'] = 0;
    _dailyUsage['Entertainment'] = 0;
    _dailyUsage['Others'] = 0;

    _sessionUsage['Social'] = 0;
    _sessionUsage['Games'] = 0;
    _sessionUsage['Entertainment'] = 0;
    _sessionUsage['Others'] = 0;

    _violationCount = 0;
    _isLocked = false;
    _lockUntil = null;
    _lockReason = null;

    // Reset last used times
    _lastUsedTime['Social'] = null;
    _lastUsedTime['Games'] = null;
    _lastUsedTime['Entertainment'] = null;
    _lastUsedTime['Others'] = null;

    // Unlock everything
    await _unlockApps();

    // Send notification
    await _sendMidnightResetNotification();

    // Save state
    await _saveState();

    // Schedule next midnight reset
    _scheduleMidnightReset();

    print('✅ Midnight reset complete - fresh start!');
  }

  /// Schedule midnight reset
  void _scheduleMidnightReset() {
    final DateTime now = DateTime.now();
    final DateTime midnight = DateTime(now.year, now.month, now.day + 1);
    final Duration timeUntilMidnight = midnight.difference(now);

    print('🌙 Scheduling midnight reset in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m');

    _midnightTimer?.cancel();
    _midnightTimer = Timer(timeUntilMidnight, () async {
      await _resetAtMidnight();
    });
  }

  /// Get current foreground app
  Future<String?> _getForegroundApp() async {
    try {
      final String? foregroundApp = await platform.invokeMethod('getForegroundApp');
      return foregroundApp;
    } catch (e) {
      print('⚠️ Error getting foreground app: $e');
      return null;
    }
  }

  /// Get category from database
  Future<String> _getCategoryFromDB(String packageName) async {
    try {
    final db = DatabaseHelper.instance;

    final result = await db.database.then((database) =>
      database.query(
        'apps_catalog',
        columns: ['category'],
        where: 'package_name = ?',
        whereArgs: [packageName],
        limit: 1,
      )
    );

      // ✅ NULL SAFETY: Validate result
    if (result.isNotEmpty) {
        final category = result.first['category'] as String?;
        if (category != null && category.isNotEmpty) {
          return category;
        }
    }

    // If not in database, try hardcoded package mapping first
    String? category = CategoryMapper.mapPackageToCategory(packageName);

    // If not in hardcoded list, default to Others
      if (category == null || category.isEmpty) {
      category = CategoryMapper.categoryOthers;
    }

      // Save to database for future lookups (with error handling)
      try {
    await db.database.then((database) =>
      database.insert('apps_catalog', {
        'package_name': packageName,
        'category': category,
        'is_monitored': category != CategoryMapper.categoryOthers ? 1 : 0,
            'last_updated': DateTime.now().millisecondsSinceEpoch,
            'is_system_app': 0,
            'is_from_playstore': 0,
      })
    );
      } catch (e) {
        print('⚠️ Error saving category to database: $e');
        // Continue - category is still valid
      }

    return category;
    } catch (e) {
      print('⚠️ Error getting category for $packageName: $e');
      // ✅ SAFE FALLBACK: Return Others if all else fails
      return CategoryMapper.categoryOthers;
    }
  }

  /// Log usage data to database
  /// ✅ CRITICAL: Added error handling to prevent crashes if database operations fail
  Future<void> _logUsageData(String category, int hour, bool prediction) async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();

      // Insert into usage_logs
      try {
        await db.database.then((database) =>
          database.insert('usage_logs', {
            'timestamp': now.millisecondsSinceEpoch,
            'category': category,
            'duration_seconds': 60, // 1 minute
            'session_id': _generateSessionId(category),
          })
        );
      } catch (e) {
        print('⚠️ Error inserting usage log: $e');
        // Continue - logging failure shouldn't break the app
      }

      // Update daily_summary
      try {
        final today = now.toIso8601String().substring(0, 10);
        await db.database.then((database) =>
          database.rawInsert('''
            INSERT OR REPLACE INTO daily_summary
            (date, category, total_usage_seconds, longest_session_seconds, session_count, last_updated)
            VALUES (?, ?, ?, ?, ?, ?)
          ''', [
            today,
            category,
            (_dailyUsage[category] ?? 0) * 60,
            (_sessionUsage[category] ?? 0) * 60,
            1,
            now.millisecondsSinceEpoch,
          ])
        );
      } catch (e) {
        print('⚠️ Error updating daily summary: $e');
        // Continue - logging failure shouldn't break the app
      }
    } catch (e) {
      print('⚠️ Error in _logUsageData: $e');
      // Don't throw - logging is non-critical
    }
  }

  /// Log lock event to database
  Future<void> _logLockEvent(
    String reason,
    dynamic duration,
    int violationNumber,
    String category,
  ) async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();

    await db.database.then((database) =>
      database.insert('lock_history', {
        'timestamp': now.millisecondsSinceEpoch,
        'category': category,
        'reason': reason,
        'duration_minutes': duration is int ? duration : 999,
        'violation_count': violationNumber,
      })
    );
  }

  /// Save yesterday's data to daily_summary
  Future<void> _saveDailySummary() async {
    final db = DatabaseHelper.instance;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayDate = yesterday.toIso8601String().substring(0, 10);

    for (final category in ['Social', 'Games', 'Entertainment', 'Others']) {
      await db.database.then((database) =>
        database.rawInsert('''
          INSERT OR REPLACE INTO daily_summary
          (date, category, total_usage_seconds, longest_session_seconds, session_count, last_updated)
          VALUES (?, ?, ?, ?, ?, ?)
        ''', [
          yesterdayDate,
          category,
          (_dailyUsage[category] ?? 0) * 60,
          (_sessionUsage[category] ?? 0) * 60,
          1,
          yesterday.millisecondsSinceEpoch,
        ])
      );
    }
  }

  /// Generate session ID for category
  String _generateSessionId(String category) {
    final now = DateTime.now();
    return '${category}_${now.year}${now.month}${now.day}_${now.hour}${now.minute}';
  }

  /// Show lock overlay screen
  Future<void> _showLockOverlay({
    required String reason,
    required dynamic duration,
    required int violationNumber,
    required String category,
  }) async {
    print('📱 Showing lock overlay: $reason (duration: $duration)');
    // This will be handled by the UI layer
  }

  /// Dismiss lock overlay screen
  Future<void> _dismissLockOverlay() async {
    print('📱 Dismissing lock overlay');
    // This will be handled by the UI layer
  }


  /// Send daily limit notification
  Future<void> _sendDailyLimitNotification(DateTime midnight, String category) async {
    print('🔔 Sending daily limit notification for $category (until midnight)');
    await NotificationService.showDailyLockNotification(category);
  }

  /// Send unlock notification
  Future<void> _sendUnlockNotification() async {
    print('🔔 Sending unlock notification');
    await NotificationService.showUnlockNotification();
  }

  /// Send midnight reset notification
  Future<void> _sendMidnightResetNotification() async {
    print('🔔 Sending midnight reset notification');
    final yesterdayUsage = Map<String, int>.from(_dailyUsage);
    await NotificationService.showMidnightResetNotification(yesterdayUsage);
  }

  /// Save state to SharedPreferences
  /// ✅ CRITICAL: Handles SharedPreferences errors gracefully (won't crash app)
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Save daily usage
      await prefs.setInt('daily_usage_social_$today', _dailyUsage['Social'] ?? 0);
      await prefs.setInt('daily_usage_games_$today', _dailyUsage['Games'] ?? 0);
      await prefs.setInt('daily_usage_entertainment_$today', _dailyUsage['Entertainment'] ?? 0);
      await prefs.setInt('daily_usage_others_$today', _dailyUsage['Others'] ?? 0);

      // Save session usage
      await prefs.setInt('session_usage_social_$today', _sessionUsage['Social'] ?? 0);
      await prefs.setInt('session_usage_games_$today', _sessionUsage['Games'] ?? 0);
      await prefs.setInt('session_usage_entertainment_$today', _sessionUsage['Entertainment'] ?? 0);
      await prefs.setInt('session_usage_others_$today', _sessionUsage['Others'] ?? 0);

      // Save violation count
      await prefs.setInt('violation_count_$today', _violationCount);

      // Save lock state
      await prefs.setBool('is_locked', _isLocked);
      if (_lockUntil != null) {
        await prefs.setInt('lock_until', _lockUntil!.millisecondsSinceEpoch);
      }
      if (_lockReason != null) {
        await prefs.setString('lock_reason', _lockReason!);
      }
    } catch (e) {
      // ✅ CRITICAL: Don't crash app if SharedPreferences fails
      // State will be lost but app continues working (will rebuild from database)
      print('⚠️ Error saving state to SharedPreferences: $e');
      print('   App will continue working, state will be rebuilt from database');
    }
  }

  /// Load state from SharedPreferences
  /// ✅ CRITICAL: Handles SharedPreferences corruption gracefully
  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Load daily usage (with safe defaults if corrupted)
      _dailyUsage['Social'] = prefs.getInt('daily_usage_social_$today') ?? 0;
      _dailyUsage['Games'] = prefs.getInt('daily_usage_games_$today') ?? 0;
      _dailyUsage['Entertainment'] = prefs.getInt('daily_usage_entertainment_$today') ?? 0;
      _dailyUsage['Others'] = prefs.getInt('daily_usage_others_$today') ?? 0;

      // Load session usage (with safe defaults if corrupted)
      _sessionUsage['Social'] = prefs.getInt('session_usage_social_$today') ?? 0;
      _sessionUsage['Games'] = prefs.getInt('session_usage_games_$today') ?? 0;
      _sessionUsage['Entertainment'] = prefs.getInt('session_usage_entertainment_$today') ?? 0;
      _sessionUsage['Others'] = prefs.getInt('session_usage_others_$today') ?? 0;

      // Load violation count (with safe default if corrupted)
      _violationCount = prefs.getInt('violation_count_$today') ?? 0;

      // Load lock state (with safe defaults if corrupted)
      _isLocked = prefs.getBool('is_locked') ?? false;
      final lockUntilMs = prefs.getInt('lock_until');
      if (lockUntilMs != null) {
        try {
          _lockUntil = DateTime.fromMillisecondsSinceEpoch(lockUntilMs);

          // Check if lock has expired
          if (_lockUntil!.isBefore(DateTime.now())) {
            await _unlockApps();
          }
        } catch (e) {
          // Invalid timestamp - clear lock state
          print('⚠️ Invalid lock timestamp, clearing lock state: $e');
          _isLocked = false;
          _lockUntil = null;
        }
      }
      _lockReason = prefs.getString('lock_reason');
    } catch (e) {
      // ✅ CRITICAL: If SharedPreferences is corrupted, reset to safe defaults
      print('⚠️ Error loading state from SharedPreferences (may be corrupted): $e');
      print('   Resetting to safe defaults');
      _dailyUsage.clear();
      _dailyUsage.addAll({'Social': 0, 'Games': 0, 'Entertainment': 0, 'Others': 0});
      _sessionUsage.clear();
      _sessionUsage.addAll({'Social': 0, 'Games': 0, 'Entertainment': 0, 'Others': 0});
      _violationCount = 0;
      _isLocked = false;
      _lockUntil = null;
      _lockReason = null;
    }
  }

  /// Check if app should be blocked
  bool shouldBlockApp(String packageName, String category) {
    // Never block Others category
    if (category == 'Others') return false;

    // Never block system apps
    if (CategoryMapper.isSystemApp(packageName)) return false;

    // Never block ReFocus itself
    if (packageName == 'com.example.refocus_app') return false;

    // Never block communication essentials
    const List<String> alwaysAllowed = [
      'com.android.phone',
      'com.android.mms',
      'com.whatsapp',
      'com.android.settings',
    ];

    if (alwaysAllowed.contains(packageName)) return false;

    // Block if locked and app is in monitored category
    return _isLocked && MONITORED_CATEGORIES.contains(category);
  }

  // Getters for UI
  Map<String, int> get dailyUsage => Map.unmodifiable(_dailyUsage);
  Map<String, int> get sessionUsage => Map.unmodifiable(_sessionUsage);
  Map<String, DateTime?> get lastUsedTime => Map.unmodifiable(_lastUsedTime);
  int get violationCount => _violationCount;
  bool get isLocked => _isLocked;
  DateTime? get lockUntil => _lockUntil;
  
  /// ✅ Get effective session usage for a category, accounting for 5-minute inactivity threshold
  /// For monitored categories (Social, Games, Entertainment), uses LockStateManager as source of truth
  /// Returns 0 if no monitored category has been used for 5+ minutes (matches continuous session behavior)
  /// ✅ CRITICAL FIX: Now uses LockStateManager.getCurrentSessionMinutes() directly for accuracy
  /// Note: This is synchronous for backward compatibility, but returns cached value synced from LockStateManager
  int getEffectiveSessionUsage(String category) {
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    
    // ✅ CRITICAL: For monitored categories, use cached value synced from LockStateManager
    // LockStateManager already handles 5-minute inactivity threshold and combined tracking
    // _updateSessionUsage() syncs this value every minute from LockStateManager.getCurrentSessionMinutes()
    if (monitoredCategories.contains(category)) {
      // Since _updateSessionUsage() now syncs all monitored categories with LockStateManager,
      // we can return any monitored category's value (they're all the same - shared session)
      return _sessionUsage['Social'] ?? 0;
    } else {
      // Others category - independent tracking
      final lastUsed = _lastUsedTime[category];
      
      if (lastUsed == null) {
        // Never used - no session
        return 0;
      }
      
      const int inactivityThresholdMinutes = 5;
      final inactivityMinutes = DateTime.now().difference(lastUsed).inMinutes;
      if (inactivityMinutes >= inactivityThresholdMinutes) {
        // Category inactive for 5+ minutes - session should be 0
        return 0;
      }
      
      // Category active - return current session value
      return _sessionUsage[category] ?? 0;
    }
  }
  
  /// ✅ Get effective session usage asynchronously (uses LockStateManager directly for real-time accuracy)
  /// For monitored categories, this is the most accurate method as it reads directly from LockStateManager
  Future<int> getEffectiveSessionUsageAsync(String category) async {
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    
    if (monitoredCategories.contains(category)) {
      // ✅ Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
      // This tracks accumulated time in milliseconds and accounts for 5-minute inactivity threshold
      final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      return sessionMinutes.round();
    } else {
      // Others category - use synchronous method
      return getEffectiveSessionUsage(category);
    }
  }
  
  /// ✅ Public method to sync session usage with LockStateManager (for frontend refresh)
  /// This ensures the cached _sessionUsage values are up-to-date before displaying
  Future<void> syncSessionUsage() async {
    // Sync for any monitored category (all get the same value - shared session)
    await _updateSessionUsage('Social');
  }
  String? get lockReason => _lockReason;
}
