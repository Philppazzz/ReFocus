import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';
import 'package:refocus_app/services/feedback_logger.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notification IDs for different types
  static const int _dailyWarningId = 1;
  static const int _sessionWarningId = 2;
  static const int _unlockWarningId = 3;
  static const int _limitReachedId = 4;
  static const int _cooldownId = 5;
  static const int _proactiveFeedbackId = 6;
  static const int _lockFeedbackId = 7; // ✅ Lock feedback notification

  /// Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // iOS initialization settings (if needed)
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    await _createNotificationChannels();

    _initialized = true;
    print("✅ Notification service initialized");
  }

  /// Create notification channels for Android (required for Android 8.0+)
  static Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // Channel 1: Warnings (high priority)
    const warningsChannel = AndroidNotificationChannel(
      'refocus_warnings',
      'Usage Warnings',
      description: 'Notifications for usage limit warnings and predictions',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Channel 2: Locks (max priority)
    const locksChannel = AndroidNotificationChannel(
      'refocus_locks',
      'Lock Notifications',
      description: 'Notifications when apps are locked or unlocked',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    // Channel 3: Motivational (low priority)
    const motivationalChannel = AndroidNotificationChannel(
      'refocus_motivational',
      'Motivational Messages',
      description: 'Motivational and achievement notifications',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    // Channel 4: Feedback (medium priority)
    const feedbackChannel = AndroidNotificationChannel(
      'refocus_feedback',
      'Feedback Requests',
      description: 'Notifications for AI learning feedback',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );

    // Create all channels
    await androidPlugin.createNotificationChannel(warningsChannel);
    await androidPlugin.createNotificationChannel(locksChannel);
    await androidPlugin.createNotificationChannel(motivationalChannel);
    await androidPlugin.createNotificationChannel(feedbackChannel);

    print("✅ Notification channels created");
  }

  /// Handle notification tap and actions
  static void _onNotificationTapped(NotificationResponse response) async {
    print("📱 Notification tapped: ${response.id}, action: ${response.actionId}");
    
    // Handle proactive feedback actions
    if (response.id == _proactiveFeedbackId) {
      final actionId = response.actionId;
      
      if (actionId == 'feedback_yes' || actionId == 'feedback_no') {
        final wouldBeHelpful = actionId == 'feedback_yes';
        
        // Parse payload or get from SharedPreferences
        String? appName;
        String? category;
        int? sessionUsage;
        int? dailyUsage;
        
        if (response.payload != null && response.payload!.contains('|')) {
          final parts = response.payload!.split('|');
          if (parts.length >= 5) {
            appName = parts[1];
            category = parts[2];
            sessionUsage = int.tryParse(parts[3]);
            dailyUsage = int.tryParse(parts[4]);
          }
        }
        
        // Fallback to SharedPreferences if payload parsing failed
        if (appName == null || category == null || sessionUsage == null || dailyUsage == null) {
          final prefs = await SharedPreferences.getInstance();
          appName = prefs.getString('pending_feedback_app');
          category = prefs.getString('pending_feedback_category');
          sessionUsage = prefs.getInt('pending_feedback_session');
          dailyUsage = prefs.getInt('pending_feedback_daily');
        }
        
        if (appName != null && category != null && sessionUsage != null && dailyUsage != null) {
          await handleProactiveFeedbackAction(
            wouldBeHelpful: wouldBeHelpful,
            appName: appName,
            category: category,
            sessionUsageMinutes: sessionUsage,
            dailyUsageMinutes: dailyUsage,
          );
        } else {
          print("⚠️ Could not parse feedback data from notification");
        }
      }
    }
    
    // ✅ Handle lock feedback actions (when app is locked)
    if (response.id == _lockFeedbackId) {
      final actionId = response.actionId;
      
      if (actionId == 'lock_feedback_yes' || actionId == 'lock_feedback_no') {
        final wasHelpful = actionId == 'lock_feedback_yes';
        
        // Parse payload or get from SharedPreferences
        String? appName;
        String? category;
        String? lockReason;
        String? predictionSource;
        int? sessionUsage;
        int? dailyUsage;
        double? modelConfidence;
        
        if (response.payload != null && response.payload!.contains('|')) {
          final parts = response.payload!.split('|');
          if (parts.length >= 8) {
            appName = parts[1];
            category = parts[2];
            sessionUsage = int.tryParse(parts[3]);
            dailyUsage = int.tryParse(parts[4]);
            lockReason = parts[5];
            predictionSource = parts[6];
            modelConfidence = double.tryParse(parts[7]);
          }
        }
        
        // Fallback to SharedPreferences if payload parsing failed
        if (appName == null || category == null || sessionUsage == null || dailyUsage == null) {
          final prefs = await SharedPreferences.getInstance();
          appName = prefs.getString('pending_lock_feedback_app');
          category = prefs.getString('pending_lock_feedback_category');
          sessionUsage = prefs.getInt('pending_lock_feedback_session');
          dailyUsage = prefs.getInt('pending_lock_feedback_daily');
          lockReason = prefs.getString('pending_lock_feedback_reason');
          predictionSource = prefs.getString('pending_lock_feedback_source');
          final confidenceStr = prefs.getString('pending_lock_feedback_confidence');
          modelConfidence = confidenceStr != null ? double.tryParse(confidenceStr) : null;
        }
        
        if (appName != null && category != null && sessionUsage != null && dailyUsage != null) {
          await handleLockFeedbackAction(
            wasHelpful: wasHelpful,
            appName: appName,
            category: category,
            sessionUsageMinutes: sessionUsage,
            dailyUsageMinutes: dailyUsage,
            lockReason: lockReason ?? 'App locked',
            predictionSource: predictionSource ?? 'rule_based',
            modelConfidence: modelConfidence,
          );
        } else {
          print("⚠️ Could not parse lock feedback data from notification");
        }
      }
    }
  }

  /// Request notification permission
  static Future<bool> requestPermission() async {
    if (!_initialized) await initialize();

    // For Android 13+ (API 33+), request notification permission
    // Android 11 (API 30) and below don't need explicit permission - notifications are granted by default
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // Check Android version - only request permission on Android 13+
      try {
        final granted = await androidImplementation.requestNotificationsPermission();
        if (granted != null) {
          print("📱 Notification permission: ${granted ? 'granted' : 'denied'}");
          return granted;
        }
        // On Android 11 and below, permission is granted by default
        print("📱 Notification permission: granted by default (Android 11 or below)");
        return true;
      } catch (e) {
        // If method doesn't exist (Android 11 or below), notifications are granted by default
        print("📱 Notification permission: granted by default (Android 11 or below)");
        return true;
      }
    }

    // For iOS, permissions are requested during initialization
    // For Android versions without the implementation, assume granted
    return true;
  }

  /// Show daily limit warning notification
  static Future<void> showDailyLimitWarning(
      double currentHours, double limitHours, {int warningLevel = 50}) async {
    if (!_initialized) await initialize();

    final remainingHours = limitHours - currentHours;
    int remainingSeconds = (remainingHours * 3600).toInt();
    int remainingMinutes = (remainingHours * 60).toInt();
    int currentSeconds = (currentHours * 3600).toInt();
    int currentMinutes = (currentHours * 60).toInt();
    final limitSeconds = (limitHours * 3600).toInt();
    final limitMinutes = (limitHours * 60).toInt();
    if (remainingSeconds < 0) remainingSeconds = 0;
    if (remainingMinutes < 0) remainingMinutes = 0;
    if (currentSeconds < 0) currentSeconds = 0;
    if (currentMinutes < 0) currentMinutes = 0;
    final percentageUsed = ((currentHours / limitHours) * 100).toInt();

    String title;
    String message;
    
    // ✅ Handle small testing limits (< 5 minutes) - show seconds instead
    final isSmallLimit = limitMinutes < 5;
    
    // ✅ More realistic, friendly messages based on warning level
    if (warningLevel == 50) {
      title = '📊 Halfway There!';
      if (isSmallLimit) {
        message = 'You\'ve used ${percentageUsed}% of your daily time (${currentSeconds}s / ${limitSeconds}s).\n'
            'You\'ve still got $remainingSeconds seconds left - use them wisely!';
      } else if (remainingMinutes < 60) {
        message = 'You\'ve used ${percentageUsed}% of your daily time (${currentMinutes}min / ${limitMinutes}min).\n'
            'You\'ve still got $remainingMinutes minutes left - use them wisely!';
      } else {
        message = 'You\'ve used ${percentageUsed}% of your daily time (${currentHours.toStringAsFixed(1)}h / ${limitHours.toStringAsFixed(1)}h).\n'
            'You\'ve still got ${remainingHours.toStringAsFixed(1)} hours left - use them wisely!';
      }
    } else if (warningLevel == 75) {
      title = '📊 Getting Close';
      if (isSmallLimit) {
        message = 'Hey! You\'re at ${percentageUsed}% of your daily limit (${currentSeconds}s / ${limitSeconds}s).\n'
            'Only $remainingSeconds seconds remaining. Consider taking a break soon!';
      } else if (remainingMinutes < 60) {
        message = 'Hey! You\'re at ${percentageUsed}% of your daily limit (${currentMinutes}min / ${limitMinutes}min).\n'
            'Only $remainingMinutes minutes remaining. Consider taking a break soon!';
      } else {
        message = 'Hey! You\'re at ${percentageUsed}% of your daily limit (${currentHours.toStringAsFixed(1)}h / ${limitHours.toStringAsFixed(1)}h).\n'
            'Only ${remainingHours.toStringAsFixed(1)} hours remaining. Consider taking a break soon!';
      }
    } else if (warningLevel == 90) {
      // 90% warning
      title = '📊 Almost There!';
      if (isSmallLimit) {
        message = '⚠️ You\'re at ${percentageUsed}%! Only $remainingSeconds seconds left today!\n'
            'Apps will lock once you reach the limit. Make these last seconds count!\n'
            '⏰ Usage resets at midnight.';
      } else if (remainingMinutes < 60) {
        message = '⚠️ You\'re at ${percentageUsed}%! Only $remainingMinutes minutes left today.\n'
            'Apps will lock once you reach the limit. Make these last minutes count!';
      } else {
        message = '⚠️ You\'re at ${percentageUsed}%! Only ${remainingHours.toStringAsFixed(1)} hours left today.\n'
            'Apps will lock once you reach the limit. Make these last minutes count!';
      }
    } else {
      // 95% final warning - CRITICAL
      title = '📊 FINAL WARNING!';
      if (isSmallLimit) {
        message = '🚨 CRITICAL: You\'re at ${percentageUsed}%! Only $remainingSeconds seconds left!\n'
            'Apps will LOCK IMMEDIATELY when you reach the limit. Take a break NOW!\n'
            '⏰ Usage resets at midnight.';
      } else if (remainingMinutes < 60) {
        message = '🚨 CRITICAL: You\'re at ${percentageUsed}%! Only $remainingMinutes minutes left!\n'
            'Apps will LOCK IMMEDIATELY when you reach the limit. Take a break NOW!\n'
            '⏰ Usage resets at midnight.';
      } else {
        message = '🚨 CRITICAL: You\'re at ${percentageUsed}%! Only ${remainingHours.toStringAsFixed(1)} hours left!\n'
            'Apps will LOCK IMMEDIATELY when you reach the limit. Take a break NOW!\n'
            '⏰ Usage resets at midnight.';
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Daily Usage Warnings',
      channelDescription: 'Notifications for daily usage limit warnings',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF6366F1), // Purple/Blue color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _dailyWarningId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Daily limit warning sent: ${currentHours.toStringAsFixed(1)}h / ${limitHours}h (${percentageUsed}%)");
  }

  /// Show session limit warning notification
  static Future<void> showSessionLimitWarning(
      double currentMinutes, double limitMinutes,
      {int warningLevel = 50, String? currentAppName}) async {
    if (!_initialized) await initialize();

    final remainingMinutes = limitMinutes - currentMinutes;
    int remainingSeconds = (remainingMinutes * 60).toInt();
    int remainingMinsInt = remainingMinutes.toInt();
    int currentSeconds = (currentMinutes * 60).toInt();
    final currentMinsInt = currentMinutes.toInt();
    final limitMinsInt = limitMinutes.toInt();
    final percentageUsed = ((currentMinutes / limitMinutes) * 100).toInt();

    if (remainingSeconds < 0) remainingSeconds = 0;
    if (remainingMinsInt < 0) remainingMinsInt = 0;
    if (currentSeconds < 0) currentSeconds = 0;

    String title;
    String message;
    
    final appLabel = (currentAppName != null && currentAppName.trim().isNotEmpty)
        ? currentAppName.trim()
        : 'this app';

    // ✅ Handle small testing limits (< 1 minute) - show seconds instead
    final isSmallLimit = limitMinutes < 1.0;
    
    // ✅ More realistic, friendly messages based on warning level
    if (warningLevel == 50) {
      title = '⏱️ Halfway Through Your Session';
      if (isSmallLimit) {
        message = 'You\'ve been on $appLabel for ${currentSeconds} seconds (${percentageUsed}%).\n'
            'You\'ve got $remainingSeconds seconds left before a break is needed.';
      } else {
        message = 'You\'ve been on $appLabel for ${currentMinsInt} minutes (${percentageUsed}%).\n'
            'You\'ve got $remainingMinsInt minutes left before a break is needed.';
      }
    } else if (warningLevel == 75) {
      title = '⏱️ Long Session Alert';
      if (isSmallLimit) {
        message = 'You\'ve been on $appLabel for ${currentSeconds} seconds (${percentageUsed}%).\n'
            'Only $remainingSeconds seconds left! Consider taking a short break soon.';
      } else {
        message = 'You\'ve been on $appLabel for ${currentMinsInt} minutes (${percentageUsed}%).\n'
            'Only $remainingMinsInt minutes left! Consider taking a short break soon.';
      }
    } else if (warningLevel == 90) {
      // 90% warning
      title = '⏱️ Break Time Coming Up!';
      if (isSmallLimit) {
        message = '⚠️ $appLabel is nearly at the limit! ${currentSeconds} seconds used (${percentageUsed}%).\n'
            'Only $remainingSeconds seconds left before a cooldown.';
      } else {
        message = '⚠️ $appLabel is nearly at the limit! ${currentMinsInt} minutes used (${percentageUsed}%).\n'
            'Only $remainingMinsInt minutes left before a cooldown.';
      }
    } else {
      // 95% final warning - CRITICAL
      title = '⏱️ FINAL WARNING!';
      if (isSmallLimit) {
        message = '🚨 CRITICAL: $appLabel will lock in $remainingSeconds seconds! (${percentageUsed}% used)\n'
            'Pause now to avoid the forced cooldown.';
      } else {
        message = '🚨 CRITICAL: $appLabel will lock in $remainingMinsInt minutes! (${percentageUsed}% used)\n'
            'Pause now to avoid the forced cooldown.';
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Max Session Warnings',
      channelDescription: 'Notifications for continuous session limit warnings',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF59E0B), // Orange color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _sessionWarningId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Session limit warning sent: ${currentMinsInt}min / ${limitMinsInt}min (${percentageUsed}%)");
  }

  /// Show unlock limit warning notification
  static Future<void> showUnlockLimitWarning(
      int currentUnlocks, int limitUnlocks,
      {int warningLevel = 50, String? mostUnlockedAppName, int? remainingUnlocks}) async {
    if (!_initialized) await initialize();

    final appLabel = (mostUnlockedAppName != null && mostUnlockedAppName.trim().isNotEmpty)
        ? mostUnlockedAppName.trim()
        : 'your top app';
    int remaining = limitUnlocks - currentUnlocks;
    if (remainingUnlocks != null) {
      remaining = remainingUnlocks;
    }
    if (remaining < 0) remaining = 0;
    final percentageUsed = ((currentUnlocks / limitUnlocks) * 100).toInt();

    String title;
    String message;
    
    // ✅ More realistic, friendly messages based on warning level
    if (warningLevel == 50) {
      title = '🔓 Opening Apps Frequently';
      message = '$appLabel has been opened $currentUnlocks times (${percentageUsed}%).\n'
          'You still have $remaining unlocks left today. Try to be mindful of how often you\'re checking.';
    } else if (warningLevel == 75) {
      title = '🔓 Many Unlocks Today';
      message = '$appLabel is tempting you ($currentUnlocks unlocks, ${percentageUsed}%). Only $remaining left!\n'
          'Consider putting your phone down for a bit. You\'re checking quite frequently.';
    } else if (warningLevel == 90) {
      // 90% warning
      title = '🔓 Almost Out of Unlocks';
      message = '⚠️ $appLabel is at ${percentageUsed}%! Only $remaining unlocks left before a lock.\n'
          'Apps will lock after you reach the limit. Maybe take a moment to breathe?';
    } else {
      // 95% final warning - CRITICAL
      title = '🔓 FINAL WARNING!';
      message = '🚨 CRITICAL: $appLabel will trigger a lock after ${remaining == 0 ? 'the next unlock' : '$remaining more unlock${remaining == 1 ? '' : 's'}'}!\n'
          'Put your phone down NOW to avoid the cooldown.';
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Most Unlock Warnings',
      channelDescription: 'Notifications for app unlock limit warnings',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEF4444), // Red color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _unlockWarningId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Unlock limit warning sent: $currentUnlocks / $limitUnlocks (${percentageUsed}%)");
  }

  /// Show limit reached notification
  static Future<void> showLimitReachedNotification(String limitType) async {
    if (!_initialized) await initialize();

    String title;
    String body;
    Color notificationColor;

    switch (limitType) {
      case 'daily_limit':
        title = '🔒 Daily Usage Limit Reached';
        body = '📊 You\'ve used all your daily time!\n'
            'Apps are locked until tomorrow (midnight).\n'
            'Take a break and come back fresh!';
        notificationColor = const Color(0xFF6366F1); // Purple/Blue
        break;
      case 'session_limit':
        title = '🔒 Max Session Limit Reached';
        body = '⏱️ You\'ve been using apps continuously for too long!\n'
            'Take a break. Apps will unlock after cooldown.';
        notificationColor = const Color(0xFFF59E0B); // Orange
        break;
      case 'unlock_limit':
        title = '🔒 Most Unlock Limit Reached';
        body = '🔓 You\'ve opened apps too many times today!\n'
            'Take a moment to breathe. Apps will unlock after cooldown.';
        notificationColor = const Color(0xFFEF4444); // Red
        break;
      default:
        title = '🔒 Limit Reached';
        body = 'You\'ve reached a usage limit.';
        notificationColor = const Color(0xFF6366F1);
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'ReFocus Warnings',
      channelDescription: 'Notifications for usage limit warnings',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: notificationColor,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _limitReachedId,
      title,
      body,
      notificationDetails,
    );

    print("📢 Limit reached notification sent: $limitType");
  }

  /// Show cooldown notification
  static Future<void> showCooldownNotification(int minutes) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'ReFocus Warnings',
      channelDescription: 'Notifications for usage limit warnings',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _cooldownId,
      '⏱️ Cooldown Active',
      'Apps are locked for $minutes more minute${minutes != 1 ? 's' : ''}. Take a break!',
      notificationDetails,
    );

    print("📢 Cooldown notification sent: $minutes minutes");
  }

  /// Show motivational notification
  static Future<void> showMotivationalNotification() async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'ReFocus Warnings',
      channelDescription: 'Notifications for usage limit warnings',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      6,
      '💪 Great Job!',
      'You\'re staying within your limits. Keep it up!',
      notificationDetails,
    );

    print("📢 Motivational notification sent");
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
    print("📢 All notifications cancelled");
  }

  /// Check and send warnings based on thresholds with multiple stages
  /// Unlock count is tracked for stats only - no longer triggers warnings
  static Future<void> checkAndSendWarnings({
    required double dailyHours,
    required double sessionMinutes,
    required double dailyLimit,
    required double sessionLimit,
    String? currentAppName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Multiple warning stages: 50%, 75%, 90%
    const List<double> warningThresholds = [0.5, 0.75, 0.9];

    // Check daily limit warnings at multiple stages
    for (var threshold in warningThresholds) {
      if (dailyHours >= dailyLimit * threshold) {
        final warningKey = 'daily_warning_${(threshold * 100).toInt()}_$today';
        if (!(prefs.getBool(warningKey) ?? false)) {
          await _showDailyWarningAtStage(dailyHours, dailyLimit, threshold);
          await prefs.setBool(warningKey, true);
          break; // Only show one warning at a time
        }
      }
    }

    // Check session limit warnings at multiple stages
    for (var threshold in warningThresholds) {
      if (sessionMinutes >= sessionLimit * threshold) {
        final warningKey = 'session_warning_${(threshold * 100).toInt()}_$today';
        if (!(prefs.getBool(warningKey) ?? false)) {
          await _showSessionWarningAtStage(
            sessionMinutes,
            sessionLimit,
            threshold,
            currentAppName: currentAppName,
          );
          await prefs.setBool(warningKey, true);
          break; // Only show one warning at a time
        }
      }
    }
  }

  /// Show daily warning at specific stage with realistic messages
  static Future<void> _showDailyWarningAtStage(
      double currentHours, double limitHours, double threshold) async {
    if (!_initialized) await initialize();

    final remainingHours = limitHours - currentHours;
    final remainingMinutes = (remainingHours * 60).toInt();
    final currentMinutes = (currentHours * 60).toInt();
    final limitMinutes = (limitHours * 60).toInt();
    final percentageUsed = ((currentHours / limitHours) * 100).toInt();

    String title;
    String message;

    if (threshold == 0.5) {
      // 50% - Friendly reminder
      title = '👋 Halfway There!';
      message = remainingMinutes < 60
          ? 'You\'ve used ${currentMinutes}min of ${limitMinutes}min today.\nYou have ${remainingMinutes} minutes left. Consider taking breaks!'
          : 'You\'ve used ${currentHours.toStringAsFixed(1)}h of ${limitHours.toStringAsFixed(1)}h today.\nYou have ${remainingHours.toStringAsFixed(1)} hours left. Pace yourself!';
    } else if (threshold == 0.75) {
      // 75% - More urgent
      title = '⚠️ Daily Usage Alert';
      message = remainingMinutes < 60
          ? 'You\'ve used ${currentMinutes}min / ${limitMinutes}min today (${percentageUsed}%).\n⏰ Only ${remainingMinutes} minutes remaining!'
          : 'You\'ve used ${currentHours.toStringAsFixed(1)}h / ${limitHours.toStringAsFixed(1)}h today (${percentageUsed}%).\n⏰ Only ${remainingHours.toStringAsFixed(1)} hours remaining!';
    } else {
      // 90% - Final warning
      title = '🚨 Daily Limit Almost Reached!';
      message = remainingMinutes < 60
          ? 'You\'re at ${percentageUsed}% of your daily limit!\nJust ${remainingMinutes} minutes left before apps lock.\nWrap up what you\'re doing!\n⏰ Usage resets at midnight.'
          : 'You\'re at ${percentageUsed}% of your daily limit!\nJust ${remainingHours.toStringAsFixed(1)} hours left before apps lock.\nWrap up what you\'re doing!\n⏰ Usage resets at midnight.';
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Daily Usage Warnings',
      channelDescription: 'Notifications for daily usage limit warnings',
      importance: threshold >= 0.9 ? Importance.max : Importance.high,
      priority: threshold >= 0.9 ? Priority.max : Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF6366F1),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _dailyWarningId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Daily limit warning (${(threshold * 100).toInt()}%) sent: ${currentHours.toStringAsFixed(1)}h / ${limitHours}h");
  }

  /// Show session warning at specific stage with realistic messages
  static Future<void> _showSessionWarningAtStage(
      double currentMinutes, double limitMinutes, double threshold,
      {String? currentAppName}) async {
    if (!_initialized) await initialize();

    final remainingMinutesDouble = limitMinutes - currentMinutes;
    int remainingSeconds = (remainingMinutesDouble * 60).toInt();
    int remainingMinutes = remainingMinutesDouble.toInt();
    int currentSeconds = (currentMinutes * 60).toInt();
    final currentMins = currentMinutes.toInt();
    final limitMins = limitMinutes.toInt();
    final percentageUsed = ((currentMinutes / limitMinutes) * 100).toInt();

    if (remainingSeconds < 0) remainingSeconds = 0;
    if (remainingMinutes < 0) remainingMinutes = 0;
    if (currentSeconds < 0) currentSeconds = 0;

    String title;
    String message;
    final appLabel = (currentAppName != null && currentAppName.trim().isNotEmpty)
        ? currentAppName.trim()
        : 'this app';
    final isSmallLimit = limitMinutes < 1.0;

    if (threshold == 0.5) {
      // 50% - Friendly reminder
      title = '⏱️ Time Check!';
      if (isSmallLimit) {
        message = 'You\'ve been on $appLabel for ${currentSeconds} seconds straight.\n'
            '$remainingSeconds seconds until your break. Gentle reminder to blink!';
      } else {
        message = 'You\'ve been focused on $appLabel for ${currentMins} minutes.\n'
            '$remainingMinutes minutes until your break. Eyes still feeling good?';
      }
    } else if (threshold == 0.75) {
      // 75% - More urgent
      title = '⚠️ Long Session Alert';
      if (isSmallLimit) {
        message = '$appLabel has been active for ${currentSeconds} seconds (${percentageUsed}%).\n'
            '⏰ Only $remainingSeconds seconds left. Time to stretch soon!';
      } else {
        message = 'You\'ve been using $appLabel for ${currentMins}min / ${limitMins}min (${percentageUsed}%).\n'
            '⏰ ${remainingMinutes} minutes left. Time to stretch soon!';
      }
    } else {
      // 90% - Final warning
      title = '🚨 Break Time Coming!';
      if (isSmallLimit) {
        message = '🚨 $appLabel is at ${percentageUsed}%!\nOnly $remainingSeconds seconds before a forced cooldown.\nFinish up now!';
      } else {
        message = '🚨 $appLabel is at ${percentageUsed}% of your session limit!\n'
            'Only ${remainingMinutes} minutes before a mandatory break.\n'
            'Start wrapping up!';
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Max Session Warnings',
      channelDescription: 'Notifications for continuous session limit warnings',
      importance: threshold >= 0.9 ? Importance.max : Importance.high,
      priority: threshold >= 0.9 ? Priority.max : Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF59E0B),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _sessionWarningId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Session limit warning (${(threshold * 100).toInt()}%) sent: ${currentMins}min / ${limitMins}min");
  }

  // ===== CATEGORY-BASED LOCK NOTIFICATIONS =====

  /// Show session lock notification
  static Future<void> showSessionLockNotification(int durationMinutes, int violationNumber, String category) async {
    if (!_initialized) await initialize();

    final title = '🔒 Apps Locked';
    final message = 'Combined session limit exceeded (used $category).\n'
        'Locked for $durationMinutes minutes (Violation #$violationNumber).\n'
        'All monitored apps are now blocked.';

    final androidDetails = AndroidNotificationDetails(
      'refocus_locks',
      'Lock Notifications',
      channelDescription: 'Notifications when apps are locked',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: true, // Persistent notification
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEF4444), // Red color
      playSound: true,
      enableVibration: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _cooldownId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Session lock notification sent: $durationMinutes mins, violation #$violationNumber");
  }

  /// Show daily lock notification
  static Future<void> showDailyLockNotification(String category) async {
    if (!_initialized) await initialize();

    final title = '🔒 Daily Limit Reached';
    final message = 'Combined daily limit exceeded (used $category).\n'
        'All monitored apps locked until midnight.\n'
        'Usage resets at 12:00 AM.';

    final androidDetails = AndroidNotificationDetails(
      'refocus_locks',
      'Lock Notifications',
      channelDescription: 'Notifications when apps are locked',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: true, // Persistent notification
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEF4444), // Red color
      playSound: true,
      enableVibration: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _cooldownId,
      title,
      message,
      notificationDetails,
    );

    print("📢 Daily lock notification sent for $category");
  }

  /// Show unlock notification
  static Future<void> showUnlockNotification() async {
    if (!_initialized) await initialize();

    final title = '✅ Apps Unlocked';
    final message = 'Lock timer ended.\n'
        'All monitored apps are now accessible again.';

    final androidDetails = AndroidNotificationDetails(
      'refocus_locks',
      'Lock Notifications',
      channelDescription: 'Notifications when apps are unlocked',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF10B981), // Green color
      playSound: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    // Cancel ongoing lock notification first
    await _notifications.cancel(_cooldownId);

    await _notifications.show(
      _cooldownId + 1,
      title,
      message,
      notificationDetails,
    );

    print("📢 Unlock notification sent");
  }

  /// Show midnight reset notification
  static Future<void> showMidnightResetNotification(Map<String, int> yesterdayUsage) async {
    if (!_initialized) await initialize();

    final social = yesterdayUsage['Social'] ?? 0;
    final games = yesterdayUsage['Games'] ?? 0;
    final entertainment = yesterdayUsage['Entertainment'] ?? 0;

    final title = '🌙 New Day Started';
    final message = 'All limits have been reset!\n\n'
        'Yesterday\'s usage:\n'
        '  Social: $social mins\n'
        '  Games: $games mins\n'
        '  Entertainment: $entertainment mins\n\n'
        'Have a productive day!';

    final androidDetails = AndroidNotificationDetails(
      'refocus_locks',
      'Daily Reset',
      channelDescription: 'Notifications for daily resets',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF6366F1), // Purple color
      playSound: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _cooldownId + 2,
      title,
      message,
      notificationDetails,
    );

    print("📢 Midnight reset notification sent");
  }

  /// Show proactive feedback notification (learning mode)
  /// Asks "Would a break be helpful now?" with quick action buttons
  static Future<void> showProactiveFeedbackNotification({
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required int usageLevel,
    String? customMessage,
  }) async {
    if (!_initialized) await initialize();

    final title = '🤔 Quick Question';
    final message = customMessage ?? 
        'You\'ve used $appName for $usageLevel minutes.\n'
        'Would a break be helpful now?';

    // Create action buttons for quick feedback
    final androidActions = [
      const AndroidNotificationAction(
        'feedback_yes',
        'Yes, helpful',
        titleColor: Color(0xFF10B981), // Green
      ),
      const AndroidNotificationAction(
        'feedback_no',
        'No, I\'m fine',
        titleColor: Color(0xFF6366F1), // Blue
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      'refocus_feedback',
      'Feedback Requests',
      channelDescription: 'Notifications for AI learning feedback',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF6366F1), // Purple
      playSound: false,
      enableVibration: false,
      actions: androidActions,
      autoCancel: true,
      category: AndroidNotificationCategory.message,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    // Store feedback data for action handler
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_feedback_app', appName);
    await prefs.setString('pending_feedback_category', category);
    await prefs.setInt('pending_feedback_session', sessionUsageMinutes);
    await prefs.setInt('pending_feedback_daily', dailyUsageMinutes);

    try {
      await _notifications.show(
        _proactiveFeedbackId,
        title,
        message,
        notificationDetails,
        payload: 'proactive_feedback|$appName|$category|$sessionUsageMinutes|$dailyUsageMinutes',
      );

      print("✅ NOTIFICATION SENT: Proactive feedback for $appName ($usageLevel min)");
      print("   Category: $category");
      print("   Daily: $dailyUsageMinutes min, Session: $sessionUsageMinutes min");
      print("   ✅ This notification will appear even if user is in another app");
    } catch (e) {
      print("❌ ERROR: Failed to show proactive feedback notification: $e");
      print("   This will prevent feedback collection from other apps");
      rethrow; // Re-throw to let caller know it failed
    }
  }

  /// ✅ Show lock feedback notification (works from any app)
  /// This ensures feedback is collected even when user is outside ReFocus app
  static Future<void> showLockFeedbackNotification({
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required String lockReason,
    String predictionSource = 'rule_based',
    double? modelConfidence,
  }) async {
    if (!_initialized) await initialize();

    final title = '🔒 App Locked';
    final message = '$appName was locked.\nWas this lock helpful?';

    // Create action buttons for quick feedback
    final androidActions = [
      const AndroidNotificationAction(
        'lock_feedback_yes',
        'Yes, helpful',
        titleColor: Color(0xFF10B981), // Green
      ),
      const AndroidNotificationAction(
        'lock_feedback_no',
        'No, not helpful',
        titleColor: Color(0xFFEF4444), // Red
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      'refocus_feedback',
      'Feedback Requests',
      channelDescription: 'Notifications for AI learning feedback',
      importance: Importance.high, // Higher priority for lock feedback
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFEF4444), // Red for lock
      playSound: true, // Sound for lock feedback
      enableVibration: true, // Vibration for lock feedback
      actions: androidActions,
      autoCancel: false, // Don't auto-cancel - user should respond
      category: AndroidNotificationCategory.message,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    // Store feedback data for action handler
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_lock_feedback_app', appName);
    await prefs.setString('pending_lock_feedback_category', category);
    await prefs.setInt('pending_lock_feedback_session', sessionUsageMinutes);
    await prefs.setInt('pending_lock_feedback_daily', dailyUsageMinutes);
    await prefs.setString('pending_lock_feedback_reason', lockReason);
    await prefs.setString('pending_lock_feedback_source', predictionSource);
    if (modelConfidence != null) {
      await prefs.setString('pending_lock_feedback_confidence', modelConfidence.toString());
    } else {
      await prefs.remove('pending_lock_feedback_confidence');
    }
    await prefs.setBool('has_pending_lock_feedback', true); // Flag for app resume check

    // Create payload
    final payload = 'lock_feedback|$appName|$category|$sessionUsageMinutes|$dailyUsageMinutes|$lockReason|$predictionSource|${modelConfidence ?? ''}';

    await _notifications.show(
      _lockFeedbackId,
      title,
      message,
      notificationDetails,
      payload: payload,
    );

    print("📢 Lock feedback notification sent for $appName (Category: $category)");
  }

  /// ✅ Handle lock feedback notification action
  /// Called when user taps "Yes, helpful" or "No, not helpful" on lock notification
  static Future<void> handleLockFeedbackAction({
    required bool wasHelpful,
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required String lockReason,
    String predictionSource = 'rule_based',
    double? modelConfidence,
  }) async {
    try {
      // Log feedback using FeedbackLogger
      await FeedbackLogger.logLockFeedback(
        appName: appName,
        appCategory: category,
        dailyUsageMinutes: dailyUsageMinutes,
        sessionUsageMinutes: sessionUsageMinutes,
        wasHelpful: wasHelpful,
        lockReason: lockReason,
        predictionSource: predictionSource,
        modelConfidence: modelConfidence,
      );

      // Clear pending feedback flag
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_lock_feedback_app');
      await prefs.remove('pending_lock_feedback_category');
      await prefs.remove('pending_lock_feedback_session');
      await prefs.remove('pending_lock_feedback_daily');
      await prefs.remove('pending_lock_feedback_reason');
      await prefs.remove('pending_lock_feedback_source');
      await prefs.remove('pending_lock_feedback_confidence');
      await prefs.setBool('has_pending_lock_feedback', false);

      // Cancel notification
      await _notifications.cancel(_lockFeedbackId);

      print("✅ Lock feedback logged: ${wasHelpful ? "Helpful" : "Not helpful"} | Category: $category | Source: $predictionSource");
    } catch (e, stackTrace) {
      print('❌ Error handling lock feedback action: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Handle proactive feedback notification action
  /// Called when user taps "Yes, helpful" or "No, I'm fine"
  static Future<void> handleProactiveFeedbackAction({
    required bool wouldBeHelpful,
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
  }) async {
    // Log the feedback
    await ProactiveFeedbackService.logProactiveFeedback(
      appName: appName,
      category: category,
      sessionUsageMinutes: sessionUsageMinutes,
      dailyUsageMinutes: dailyUsageMinutes,
      wouldBeHelpful: wouldBeHelpful,
    );

    // Clear pending feedback data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_feedback_app');
    await prefs.remove('pending_feedback_category');
    await prefs.remove('pending_feedback_session');
    await prefs.remove('pending_feedback_daily');

    print("✅ Proactive feedback logged: ${wouldBeHelpful ? "Helpful" : "Not helpful"}");
  }

  /// Show predictive risk warning
  static Future<void> showPeakRiskWarning(String category, int currentUsage) async {
    if (!_initialized) await initialize();

    final title = '🔮 High Overuse Risk';
    final message = 'AI detected high overuse risk for $category.\n'
        'Current usage: $currentUsage mins.\n'
        'You usually exceed limits around this time.\n'
        'Consider taking a break now!';

    final androidDetails = AndroidNotificationDetails(
      'refocus_warnings',
      'Predictive Warnings',
      channelDescription: 'AI-powered usage predictions',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF8B5CF6), // Purple color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _dailyWarningId + 10,
      title,
      message,
      notificationDetails,
    );

    print("📢 Peak risk warning sent for $category");
  }

  /// Show motivational streak notification
  static Future<void> showStreakNotification(int days) async {
    if (!_initialized) await initialize();

    final title = '🔥 Streak Milestone!';
    final message = '$days-day streak with no violations!\n'
        'Keep up the excellent work!';

    final androidDetails = AndroidNotificationDetails(
      'refocus_motivational',
      'Motivational Messages',
      channelDescription: 'Motivational notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF10B981), // Green color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _dailyWarningId + 20,
      title,
      message,
      notificationDetails,
    );

    print("📢 Streak notification sent: $days days");
  }

  /// Show goal achieved notification
  static Future<void> showDailyGoalAchieved() async {
    if (!_initialized) await initialize();

    final title = '🎯 Goal Achieved!';
    final message = 'You stayed under your limits today!\n'
        'Well done!';

    final androidDetails = AndroidNotificationDetails(
      'refocus_motivational',
      'Motivational Messages',
      channelDescription: 'Motivational notifications',
      importance: Importance.low,
      priority: Priority.low,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF10B981), // Green color
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _dailyWarningId + 21,
      title,
      message,
      notificationDetails,
    );

    print("📢 Daily goal achieved notification sent");
  }
}