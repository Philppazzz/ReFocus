import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/pages/home_page.dart'; // For AppState

/// Comprehensive Emergency Override Service
/// Handles emergency unlock with once-per-day limit and proper state management
class EmergencyService {
  static const String KEY_EMERGENCY_USED_TODAY = 'emergency_used_today';
  static const String KEY_EMERGENCY_DATE = 'emergency_date';
  static const String KEY_EMERGENCY_OVERRIDE_ENABLED = 'emergency_override_enabled';

  /// Check if emergency has been used today
  static Future<bool> hasUsedEmergencyToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastUsedDate = prefs.getString(KEY_EMERGENCY_DATE);
    final usedToday = prefs.getBool(KEY_EMERGENCY_USED_TODAY) ?? false;
    
    // If it's a new day, reset the flag
    if (lastUsedDate != today) {
      await prefs.setBool(KEY_EMERGENCY_USED_TODAY, false);
      await prefs.setString(KEY_EMERGENCY_DATE, today);
      return false;
    }
    
    return usedToday;
  }

  /// Activate emergency override
  /// This stops all tracking, clears locks, and resets session/unlock counters
  /// Daily usage is preserved
  static Future<Map<String, dynamic>> activateEmergency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      // Check if already used today
      if (await hasUsedEmergencyToday()) {
        return {
          'success': false,
          'message': 'Emergency override already used today. Available again tomorrow.',
        };
      }
      
      print("🚨 EMERGENCY OVERRIDE ACTIVATED");
      
      // Mark emergency as used today
      await prefs.setBool(KEY_EMERGENCY_USED_TODAY, true);
      await prefs.setString(KEY_EMERGENCY_DATE, today);
      await prefs.setBool(KEY_EMERGENCY_OVERRIDE_ENABLED, true);
      
      // Mark timestamp when override is turned ON
      await prefs.setInt('emergency_override_start_time', DateTime.now().millisecondsSinceEpoch);
      
      // Get current daily usage BEFORE clearing anything (we want to preserve this)
      final currentDailyUsage = prefs.getDouble('cached_daily_usage_$today') ?? 0.0;
      
      // Clear ALL locks and cooldowns
      await LockStateManager.clearCooldown();
      await prefs.remove('daily_locked');
      MonitorService.clearLockState();
      
      // Reset session timer (but keep daily usage)
      await prefs.remove('session_start_$today');
      await prefs.remove('last_activity_$today');
      await prefs.remove('session_accumulated_ms_$today');
      
      // Reset unlock counter base (effectively resets unlock count to 0)
      final currentUnlockCount = prefs.getInt('cached_most_unlock_count_$today') ?? 0;
      await prefs.setInt('unlock_base_$today', currentUnlockCount);
      
      // Reset warning flags
      await prefs.remove('session_warning_sent_$today');
      await prefs.remove('session_warning_50_$today');
      await prefs.remove('session_warning_75_$today');
      await prefs.remove('session_warning_90_$today');
      await prefs.remove('session_final_warning_$today');
      await prefs.remove('unlock_warning_sent_$today');
      await prefs.remove('unlock_warning_50_$today');
      await prefs.remove('unlock_warning_75_$today');
      await prefs.remove('unlock_warning_90_$today');
      await prefs.remove('unlock_final_warning_$today');
      
      // Cache current daily usage (preserve it)
      await prefs.setDouble('cached_daily_usage_$today', currentDailyUsage);
      
      // Update last_check to skip events during emergency period
      await prefs.setInt('last_check_$today', DateTime.now().millisecondsSinceEpoch);
      
      // Log emergency activation to database
      await DatabaseHelper.instance.logEmergencyUnlock(
        method: 'emergency_override',
        reason: 'Emergency override activated',
      );
      
      // ✅ CRITICAL: Update AppState immediately to ensure all services see the change
      AppState().isOverrideEnabled = true;
      print("✅ AppState.isOverrideEnabled set to TRUE");
      
      print("✅ Emergency activated:");
      print("   - All locks cleared");
      print("   - Session timer reset");
      print("   - Unlock counter reset");
      print("   - Daily usage preserved: ${currentDailyUsage}h");
      print("   - Tracking stopped");
      print("   - AppState.isOverrideEnabled = TRUE");
      
      return {
        'success': true,
        'message': 'Emergency override activated for 24 hours. All restrictions lifted temporarily.',
        'expires_in_hours': 24,
      };
    } catch (e) {
      print("⚠️ Error activating emergency: $e");
      return {
        'success': false,
        'message': 'Failed to activate emergency override: $e',
      };
    }
  }

  /// Deactivate emergency override
  /// This resumes normal tracking and monitoring
  static Future<void> deactivateEmergency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      print("🚨 EMERGENCY OVERRIDE DEACTIVATED");
      
      // Disable emergency override
      await prefs.setBool(KEY_EMERGENCY_OVERRIDE_ENABLED, false);
      
      // Update last_check to NOW so events during emergency are skipped
      await prefs.setInt('last_check_$today', DateTime.now().millisecondsSinceEpoch);
      await prefs.remove('emergency_override_start_time');
      
      // Clear stats cache to force fresh fetch
      MonitorService.clearStatsCache();
      
      // ✅ CRITICAL: Update AppState immediately to ensure all services see the change
      AppState().isOverrideEnabled = false;
      print("✅ AppState.isOverrideEnabled set to FALSE");
      
      // Wait a moment to ensure state is updated
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Restart monitoring
      await MonitorService.restartMonitoring();
      
      print("✅ Emergency deactivated:");
      print("   - Tracking resumed");
      print("   - Monitoring restarted");
      print("   - Events during emergency skipped");
      print("   - AppState.isOverrideEnabled = FALSE");
      
    } catch (e) {
      print("⚠️ Error deactivating emergency: $e");
    }
  }

  /// Check if emergency override is currently active
  /// Automatically deactivates after 24 hours
  static Future<bool> isEmergencyActive() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(KEY_EMERGENCY_OVERRIDE_ENABLED) ?? false;
    
    if (!isEnabled) return false;
    
    // Check if emergency override has been active for more than 24 hours
    final startTime = prefs.getInt('emergency_override_start_time');
    if (startTime != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedHours = (now - startTime) / (1000 * 60 * 60);
      
      if (elapsedHours >= 24) {
        print('🚨 Emergency override expired (24 hours limit) - Auto-deactivating');
        await deactivateEmergency();
        return false;
      }
    }
    
    return true;
  }
  
  /// Get remaining time for current emergency override (in hours)
  /// Returns 0 if not active
  static Future<double> getRemainingEmergencyHours() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(KEY_EMERGENCY_OVERRIDE_ENABLED) ?? false;
    
    if (!isEnabled) return 0.0;
    
    final startTime = prefs.getInt('emergency_override_start_time');
    if (startTime == null) return 24.0; // Default to full 24 hours if start time not recorded
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedHours = (now - startTime) / (1000 * 60 * 60);
    final remaining = 24.0 - elapsedHours;
    
    return remaining.clamp(0.0, 24.0);
  }

  /// Get time until emergency is available again (in hours)
  /// Returns 0 if available now
  static Future<int> getHoursUntilAvailable() async {
    if (!await hasUsedEmergencyToday()) {
      return 0;
    }
    
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final difference = tomorrow.difference(now);
    
    return difference.inHours;
  }

  /// Reset emergency usage (for testing purposes only)
  static Future<void> resetEmergencyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_EMERGENCY_USED_TODAY);
    await prefs.remove(KEY_EMERGENCY_DATE);
  }
}

