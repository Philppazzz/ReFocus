import 'dart:async';
import 'package:flutter/services.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/limit_manager.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/pages/app_picker_page.dart';

class MonitorService {
  static const platform = MethodChannel('com.example.refocus/monitor');
  static Timer? _monitorTimer;
  static bool _isMonitoring = false;
  static String? _lastForegroundApp;

  /// Start monitoring foreground apps
  static Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    print("🔍 Starting app monitor service...");
    _isMonitoring = true;

    // Check every 2 seconds
    _monitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _checkForegroundApp();
    });
  }

  /// Stop monitoring
  static void stopMonitoring() {
    print("⏹️ Stopping app monitor service...");
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// Check foreground app and enforce limits
  static Future<void> _checkForegroundApp() async {
    try {
      // Get current foreground app
      final foregroundApp = await platform.invokeMethod<String>('getForegroundApp');
      
      if (foregroundApp == null || foregroundApp.isEmpty) {
        // No app in foreground - user might be on home screen
        return;
      }
      
      if (foregroundApp == 'com.example.refocus_app') {
        // Don't block our own app
        return;
      }

      // Check if it's a selected app
      final selectedPackages = SelectedAppsManager.selectedApps
          .map((a) => a['package'])
          .where((p) => p != null && p.isNotEmpty)
          .toSet();

      if (!selectedPackages.contains(foregroundApp)) {
        // User is using a non-tracked app - don't update session
        return;
      }

      // ✅ User is using a tracked app - update session activity
      await LimitManager.updateSessionActivity();

      // Check if there's an active cooldown
      final cooldownInfo = await LimitManager.getActiveCooldown();
      if (cooldownInfo != null) {
        print("🔒 Active cooldown detected, bringing app to foreground");
        await _bringAppToForeground();
        return;
      }

      // Get current stats
      final stats = await UsageService.getUsageStatsWithEvents(
        SelectedAppsManager.selectedApps
      );

      final dailyHours = stats['daily_usage_hours'] ?? 0.0;
      final totalUnlocks = stats['most_unlock_count'] ?? 0;

      // Check limits
      final violation = await LimitManager.checkLimits(
        dailyHours: dailyHours,
        totalUnlocks: totalUnlocks,
      );

      if (violation != null) {
        final limitType = violation['type'];
        print("🚨 Limit violation detected: $limitType");

        // Record violation
        await LimitManager.recordViolation(limitType);

        // Get cooldown duration
        final cooldownSeconds = await LimitManager.getCooldownSeconds(limitType);

        // Get app name
        final appName = SelectedAppsManager.selectedApps
            .firstWhere(
              (app) => app['package'] == foregroundApp,
              orElse: () => {'name': 'App'},
            )['name'] ?? 'App';

        // Set cooldown
        await LimitManager.setCooldown(
          reason: limitType,
          seconds: cooldownSeconds,
          appName: appName,
        );

        // Show notification
        await NotificationService.showLimitReachedNotification(limitType);
        await NotificationService.showCooldownNotification(cooldownSeconds ~/ 60);

        // Bring our app to foreground
        await _bringAppToForeground();
      }

      _lastForegroundApp = foregroundApp;
    } catch (e) {
      print("⚠️ Monitor error: $e");
    }
  }

  /// Bring ReFocus app to foreground
  static Future<void> _bringAppToForeground() async {
    try {
      await platform.invokeMethod('bringToForeground');
    } catch (e) {
      print("⚠️ Error bringing app to foreground: $e");
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