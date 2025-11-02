import 'package:shared_preferences/shared_preferences.dart';

class LimitManager {
  static const double DAILY_LIMIT_HOURS = 6.0;
  static const double SESSION_LIMIT_MINUTES = 60.0;
  static const int UNLOCK_LIMIT = 50;
  static const int BASE_COOLDOWN_SECONDS = 180; // 3 minutes
  static const int BREAK_DURATION_MINUTES = 5; // 5 minutes break required for session reset

  /// Check if daily limit exceeded
  static Future<bool> isDailyLimitExceeded(double currentHours) async {
    return currentHours >= DAILY_LIMIT_HOURS;
  }

  /// Check if session limit exceeded
  static Future<bool> isSessionLimitExceeded() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs == null) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final sessionMinutes = (now - sessionStartMs) / 1000 / 60;

    return sessionMinutes >= SESSION_LIMIT_MINUTES;
  }

  /// Get current session duration in minutes
  static Future<double> getCurrentSessionMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs == null) return 0.0;

    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - sessionStartMs) / 1000 / 60;
  }

  /// Check if unlock limit exceeded
  static Future<bool> isUnlockLimitExceeded(int currentUnlocks) async {
    return currentUnlocks >= UNLOCK_LIMIT;
  }

  /// Get current cooldown duration (increases with violations)
  static Future<int> getCooldownSeconds(String limitType) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '${limitType}_violations_$today';
    
    final violations = prefs.getInt(key) ?? 0;
    
    // Each violation adds 3 minutes: 3, 6, 9, 12...
    return BASE_COOLDOWN_SECONDS * (violations + 1);
  }

  /// Record a violation (ONLY for session and unlock limits, NOT daily)
  static Future<void> recordViolation(String limitType) async {
    // Don't record violations for daily limit
    if (limitType == 'daily_limit') {
      print("ℹ️ Daily limit reached - no violation recorded");
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '${limitType}_violations_$today';
    
    final violations = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, violations + 1);
    
    print("🚨 $limitType violation recorded. Total: ${violations + 1}");
  }

  /// Decrease violation count if user behaves well
  static Future<void> decreaseViolations(String limitType) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '${limitType}_violations_$today';
    
    final violations = prefs.getInt(key) ?? 0;
    if (violations > 0) {
      await prefs.setInt(key, violations - 1);
      print("✅ $limitType violations decreased to ${violations - 1}");
    }
  }

  /// Start or update continuous session tracking (works across ALL selected apps)
  static Future<void> updateSessionActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if user needs a break
    final lastBreakEnd = prefs.getInt('last_break_end_$today');
    final sessionStartMs = prefs.getInt('session_start_$today');
    
    // If there's a break requirement, check if break is complete
    if (lastBreakEnd != null && sessionStartMs == null) {
      final breakMinutes = (now - lastBreakEnd) / 1000 / 60;
      
      if (breakMinutes >= BREAK_DURATION_MINUTES) {
        // Break complete, can start new session
        await prefs.remove('last_break_end_$today');
        await prefs.setInt('session_start_$today', now);
        await prefs.setInt('last_activity_$today', now);
        print("✅ Break complete (${breakMinutes.toInt()}m) - New session started");
        return;
      } else {
        // Still in break period
        print("⏸️ Break in progress: ${(BREAK_DURATION_MINUTES - breakMinutes).toInt()}m remaining");
        return;
      }
    }
    
    // Update last activity time
    await prefs.setInt('last_activity_$today', now);
    
    // Start new session if none exists
    if (sessionStartMs == null) {
      await prefs.setInt('session_start_$today', now);
      print("📱 New session started");
    } else {
      // Session continues
      final sessionMinutes = (now - sessionStartMs) / 1000 / 60;
      print("⏱️ Session continues: ${sessionMinutes.toStringAsFixed(1)} min");
    }
  }

  /// Force break (called when session limit reached)
  static Future<void> forceBreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // End current session
    await prefs.remove('session_start_$today');
    
    // Mark when break started
    await prefs.setInt('last_break_end_$today', now);
    
    print("🛑 Session ended - 5 minute break required");
  }

  /// Check if user is in required break period
  static Future<bool> isInBreakPeriod() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final lastBreakEnd = prefs.getInt('last_break_end_$today');
    if (lastBreakEnd == null) return false;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final breakMinutes = (now - lastBreakEnd) / 1000 / 60;
    
    return breakMinutes < BREAK_DURATION_MINUTES;
  }

  /// Get remaining break time in minutes
  static Future<int> getRemainingBreakMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final lastBreakEnd = prefs.getInt('last_break_end_$today');
    if (lastBreakEnd == null) return 0;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = (now - lastBreakEnd) / 1000 / 60;
    final remaining = (BREAK_DURATION_MINUTES - elapsed).ceil();
    
    return remaining > 0 ? remaining : 0;
  }

  /// Get active cooldown info
  static Future<Map<String, dynamic>?> getActiveCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if daily limit is active (special case - no timer)
    final dailyLocked = prefs.getBool('daily_locked') ?? false;
    if (dailyLocked) {
      return {
        'reason': 'daily_limit',
        'remainingSeconds': -1, // Special value for "until tomorrow"
        'appName': 'All Apps',
        'isDaily': true,
      };
    }
    
    // Check regular cooldown
    final cooldownEndMs = prefs.getInt('cooldown_end');
    if (cooldownEndMs == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingSeconds = ((cooldownEndMs - now) / 1000).ceil();

    if (remainingSeconds <= 0) {
      await prefs.remove('cooldown_end');
      await prefs.remove('cooldown_reason');
      await prefs.remove('cooldown_app');
      return null;
    }

    return {
      'reason': prefs.getString('cooldown_reason') ?? 'unknown',
      'remainingSeconds': remainingSeconds,
      'appName': prefs.getString('cooldown_app') ?? 'App',
      'isDaily': false,
    };
  }

  /// Set daily lock (no timer - unlocks tomorrow)
  static Future<void> setDailyLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('daily_locked', true);
    print("🔒 Daily lock set - unlocks tomorrow");
  }

  /// Set cooldown (for session/unlock limits)
  static Future<void> setCooldown({
    required String reason,
    required int seconds,
    required String appName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = DateTime.now().millisecondsSinceEpoch + (seconds * 1000);

    await prefs.setInt('cooldown_end', endTime);
    await prefs.setString('cooldown_reason', reason);
    await prefs.setString('cooldown_app', appName);

    print("🔒 Cooldown set: $reason for ${seconds}s");
  }

  /// Clear cooldown
  static Future<void> clearCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cooldown_end');
    await prefs.remove('cooldown_reason');
    await prefs.remove('cooldown_app');
    await prefs.remove('daily_locked');
    print("🔓 Cooldown cleared");
  }

  /// Reset daily counters
  static Future<void> resetDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    await prefs.remove('session_violations_$today');
    await prefs.remove('unlock_violations_$today');
    await prefs.remove('session_start_$today');
    await prefs.remove('last_activity_$today');
    await prefs.remove('last_break_end_$today');
    await prefs.remove('daily_locked');
    
    print("🌅 Daily limits reset");
  }

  /// Check all limits and return violation info
  static Future<Map<String, dynamic>?> checkLimits({
    required double dailyHours,
    required int totalUnlocks,
  }) async {
    // Priority 1: Check daily limit FIRST
    if (await isDailyLimitExceeded(dailyHours)) {
      return {
        'type': 'daily_limit',
        'message': 'Daily limit reached - unlocks tomorrow',
      };
    }

    // Priority 2: Check if in required break period
    if (await isInBreakPeriod()) {
      final remaining = await getRemainingBreakMinutes();
      return {
        'type': 'break_required',
        'message': 'Take a $remaining minute break',
        'remainingMinutes': remaining,
      };
    }

    // Priority 3: Check session limit
    if (await isSessionLimitExceeded()) {
      return {
        'type': 'session_limit',
        'message': 'Continuous usage limit reached',
      };
    }

    // Priority 4: Check unlock limit
    if (await isUnlockLimitExceeded(totalUnlocks)) {
      return {
        'type': 'unlock_limit',
        'message': 'Unlock limit reached',
      };
    }

    return null;
  }
}