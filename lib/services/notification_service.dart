// lib/services/notification_service.dart (NO NOTIFICATIONS VERSION)
// Use this if you want to skip notifications completely

import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  /// Initialize notification service (does nothing in this version)
  static Future<void> initialize() async {
    print("✅ Notification service disabled (not needed)");
  }

  /// Request notification permission (does nothing)
  static Future<bool> requestPermission() async {
    return true;
  }

  /// Show warning notification - DISABLED
  static Future<void> showDailyLimitWarning(double currentHours, double limitHours) async {
    print("📢 Daily limit warning: ${currentHours.toStringAsFixed(1)}h / ${limitHours}h");
  }

  /// Show warning notification - DISABLED
  static Future<void> showSessionLimitWarning(double currentMinutes, double limitMinutes) async {
    print("📢 Session limit warning: ${currentMinutes.toInt()}m / ${limitMinutes.toInt()}m");
  }

  /// Show warning notification - DISABLED
  static Future<void> showUnlockLimitWarning(int currentUnlocks, int limitUnlocks) async {
    print("📢 Unlock limit warning: $currentUnlocks / $limitUnlocks");
  }

  /// Show limit reached notification - DISABLED
  static Future<void> showLimitReachedNotification(String limitType) async {
    print("📢 Limit reached: $limitType");
  }

  /// Show cooldown notification - DISABLED
  static Future<void> showCooldownNotification(int minutes) async {
    print("📢 Cooldown: $minutes minutes");
  }

  /// Show motivational notification - DISABLED
  static Future<void> showMotivationalNotification() async {
    print("📢 Motivational message");
  }

  /// Cancel all notifications - DISABLED
  static Future<void> cancelAll() async {
    // Do nothing
  }

  /// Check and send warnings - DISABLED
  static Future<void> checkAndSendWarnings({
    required double dailyHours,
    required double sessionMinutes,
    required int unlockCount,
    required double dailyLimit,
    required double sessionLimit,
    required int unlockLimit,
  }) async {
    // Just log to console instead of showing notifications
    if (dailyHours >= dailyLimit * 0.9) {
      print("⚠️ Approaching daily limit: ${dailyHours.toStringAsFixed(1)}h / ${dailyLimit}h");
    }
    if (sessionMinutes >= sessionLimit * 0.9) {
      print("⚠️ Approaching session limit: ${sessionMinutes.toInt()}m / ${sessionLimit.toInt()}m");
    }
    if (unlockCount >= (unlockLimit * 0.9).toInt()) {
      print("⚠️ Approaching unlock limit: $unlockCount / $unlockLimit");
    }
  }
}