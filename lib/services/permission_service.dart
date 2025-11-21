import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to check and manage all required app permissions
class PermissionService {
  static const platform = MethodChannel('com.example.refocus/monitor');
  static const permissionChannel = MethodChannel('com.example.usage_stats/permission');

  /// Check all required permissions status
  /// Returns a map with permission statuses
  static Future<Map<String, bool>> checkAllPermissions() async {
    final usageAccess = await checkUsageAccess();
    final overlayPermission = await checkOverlayPermission();
    final notificationPermission = await checkNotificationPermission();

    return {
      'usage_access': usageAccess,
      'overlay': overlayPermission,
      'notification': notificationPermission,
      'all_granted': usageAccess && overlayPermission && notificationPermission,
    };
  }

  /// Check if Usage Access permission is granted
  static Future<bool> checkUsageAccess() async {
    try {
      final granted = await UsageStats.checkUsagePermission() ?? false;
      return granted;
    } catch (e) {
      print('⚠️ Error checking usage access: $e');
      return false;
    }
  }

  /// Check if Overlay permission is granted
  static Future<bool> checkOverlayPermission() async {
    try {
      final hasPermission = await platform.invokeMethod<bool>('hasOverlayPermission') ?? false;
      return hasPermission;
    } catch (e) {
      print('⚠️ Error checking overlay permission: $e');
      return false;
    }
  }

  /// Check if Notification permission is granted
  /// On Android 13+, this requires explicit permission
  static Future<bool> checkNotificationPermission() async {
    try {
      // For Android 13+ (API 33+), check notification permission
      final hasPermission = await platform.invokeMethod<bool>('hasNotificationPermission') ?? true;
      return hasPermission;
    } catch (e) {
      // If method not implemented, assume granted (older Android versions)
      print('⚠️ Error checking notification permission: $e');
      return true;
    }
  }

  /// Request Usage Access permission
  static Future<bool> requestUsageAccess() async {
    try {
      final granted = await UsageStats.checkUsagePermission() ?? false;
      if (!granted) {
        await UsageStats.grantUsagePermission();
        // Wait a bit for user to grant permission
        await Future.delayed(const Duration(seconds: 2));
        return await UsageStats.checkUsagePermission() ?? false;
      }
      return granted;
    } catch (e) {
      print('⚠️ Error requesting usage access: $e');
      return false;
    }
  }

  /// Request Overlay permission
  static Future<bool> requestOverlayPermission() async {
    try {
      await platform.invokeMethod('requestOverlayPermission');
      // Wait a bit for user to grant permission
      await Future.delayed(const Duration(seconds: 2));
      return await checkOverlayPermission();
    } catch (e) {
      print('⚠️ Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Request Notification permission
  static Future<bool> requestNotificationPermission() async {
    try {
      await platform.invokeMethod('requestNotificationPermission');
      // Wait a bit for user to grant permission
      await Future.delayed(const Duration(seconds: 2));
      return await checkNotificationPermission();
    } catch (e) {
      print('⚠️ Error requesting notification permission: $e');
      return true; // Assume granted on older Android versions
    }
  }

  /// Check if user has seen the permission request (first time login)
  static Future<bool> hasSeenPermissionRequest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_seen_permission_request') ?? false;
  }

  /// Mark that user has seen the permission request
  static Future<void> markPermissionRequestSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_permission_request', true);
  }

  /// Open app settings
  static Future<void> openAppSettings() async {
    try {
      await platform.invokeMethod('openAppSettings');
    } catch (e) {
      print('⚠️ Error opening app settings: $e');
    }
  }
}

