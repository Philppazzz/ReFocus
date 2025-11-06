import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';

class LockStateManager {
  // Default thresholds (can be overridden via SharedPreferences)
  // ✅ TESTING MOST_UNLOCK: Set session and daily VERY HIGH to focus on unlock testing
static const double DEFAULT_DAILY_LIMIT_HOURS = 0.0194; // 1 minute 10 seconds
static const double DEFAULT_SESSION_LIMIT_MINUTES = 0.3333; // 20 seconds
static const int DEFAULT_UNLOCK_LIMIT = 5; // stays the same for testing

  // Progressive cooldowns for session/unlock violations
  // Punishment increases with each violation: 5s → 10s → 15s → 20s → 30s → 60s (then caps)
  static const List<int> DEFAULT_COOLDOWN_TIERS_SECONDS = [5, 10];

  // Legacy break model is no longer used; cooldown governs resets
  static const int BREAK_DURATION_MINUTES = 0;
  
  // Session inactivity threshold: 5 minutes
  // If user doesn't use any selected app for threshold time, session ends
  static const int SESSION_INACTIVITY_MINUTES = 5;

  /// Fixed inactivity threshold: session ONLY restarts after 5 minutes
  /// without any selected app activity. This prevents "cheating" by quickly
  /// closing and reopening apps to reset the session.
  static Future<double> _getEffectiveInactivityThresholdMinutes() async {
    return SESSION_INACTIVITY_MINUTES.toDouble();
  }
  
  // Keys for configurable limits (set via SharedPreferences for testing)
  static const String KEY_DAILY_LIMIT_HOURS = 'config_daily_limit_hours';
  static const String KEY_SESSION_LIMIT_MINUTES = 'config_session_limit_minutes';
  static const String KEY_UNLOCK_LIMIT = 'config_unlock_limit';

  /// Check if daily limit exceeded
  static Future<bool> isDailyLimitExceeded(double currentHours) async {
    final thresholds = await _getThresholds();
    final exceeded = currentHours >= thresholds['dailyHours'];
    if (exceeded) {
      print("⚠️ Daily limit exceeded: ${currentHours.toStringAsFixed(2)}h >= ${thresholds['dailyHours']}h");
    }
    return exceeded;
  }

  /// Check if session limit exceeded
  /// CRITICAL: Uses getCurrentSessionMinutes() to account for inactivity threshold
  static Future<bool> isSessionLimitExceeded() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs == null) {
      print("ℹ️ No active session");
      return false;
    }

    // Use getCurrentSessionMinutes() which accounts for inactivity threshold
    // This ensures we only check active session time, not total elapsed time
    final sessionMinutes = await getCurrentSessionMinutes();
    
    // If session ended due to inactivity, getCurrentSessionMinutes() returns 0
    if (sessionMinutes == 0.0) {
      return false; // No active session to check
    }

    final thresholds = await _getThresholds();
    final sessionLimit = thresholds['sessionMinutes'] as double;
    
    // CRITICAL: Use >= comparison with a small tolerance to account for floating point precision
    // Also trigger slightly early (at 99% of limit) to ensure we catch it reliably
    final exceeded = sessionMinutes >= (sessionLimit * 0.99);
    
    if (exceeded) {
      print("🚨🚨🚨 Session limit EXCEEDED: ${sessionMinutes.toStringAsFixed(2)}m >= ${(sessionLimit * 0.99).toStringAsFixed(2)}m (limit: ${sessionLimit}m)");
    } else {
      print("⏱️ Session: ${sessionMinutes.toStringAsFixed(2)}m / ${sessionLimit}m (${((sessionMinutes / sessionLimit) * 100).toStringAsFixed(1)}%)");
    }
    
    return exceeded;
  }

  /// Get current session duration in minutes
  /// Accounts for inactivity rule - only counts time if session is still active
  static Future<double> getCurrentSessionMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs == null) return 0.0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastActivityMs = prefs.getInt('last_activity_$today');
    final inactivityThreshold = await _getEffectiveInactivityThresholdMinutes();
    
    // Check if session is still active (within inactivity threshold)
    if (lastActivityMs != null) {
      final inactivityMinutes = (now - lastActivityMs) / 1000 / 60;
      if (inactivityMinutes >= inactivityThreshold) {
        // Session has ended due to inactivity - return 0
        return 0.0;
      }
    }
    // Return accumulated active time only (time spent in selected apps)
    final accMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;
    return accMs / 1000 / 60;
  }

  /// Check if unlock limit exceeded
  static Future<bool> isUnlockLimitExceeded(int currentMostUnlockedCount) async {
    // Compare against base since last cooldown to avoid touching analytics
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // ✅ CRITICAL: Initialize unlock_base if it doesn't exist (first unlock of the day)
    if (!prefs.containsKey('unlock_base_$today')) {
      await prefs.setInt('unlock_base_$today', 0);
      print("🔓 Unlock base initialized to 0 for $today");
    }
    
    final base = prefs.getInt('unlock_base_$today') ?? 0;
    final thresholds = await _getThresholds();
    final unlockLimit = thresholds['unlockLimit'] as int;

    final delta = currentMostUnlockedCount - base;
    final exceeded = delta >= unlockLimit;
    
    // ✅ Enhanced logging for debugging
    print("🔍 UNLOCK LIMIT CHECK:");
    print("   Current most unlocked count: $currentMostUnlockedCount");
    print("   Base (from last violation): $base");
    print("   Delta (current - base): $delta");
    print("   Unlock limit: $unlockLimit");
    print("   Exceeded: $exceeded (${delta >= unlockLimit ? '✅ YES' : '❌ NO'})");
    
    if (exceeded) {
      print("🚨🚨🚨 UNLOCK LIMIT EXCEEDED: $delta unlocks >= $unlockLimit (base: $base, current: $currentMostUnlockedCount)");
    } else if (delta > 0) {
      // ✅ CRITICAL: Log when tracking is active (delta > 0 means unlocks are being counted)
      print("✅ Unlock tracking ACTIVE: $delta unlocks counted (will lock at $unlockLimit)");
    }
    
    return exceeded;
  }

  /// Get remaining unlocks before the next limit is hit
  static Future<int> getRemainingUnlocks(int currentMostUnlockedCount) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (!prefs.containsKey('unlock_base_$today')) {
      await prefs.setInt('unlock_base_$today', 0);
    }

    final base = prefs.getInt('unlock_base_$today') ?? 0;
    final thresholds = await _getThresholds();
    final unlockLimit = thresholds['unlockLimit'] as int;

    final delta = currentMostUnlockedCount - base;
    final remaining = unlockLimit - delta;
    return remaining <= 0 ? 0 : remaining;
  }

  /// Get current cooldown duration (increases with violations)
  static Future<int> getCooldownSeconds(String limitType) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '${limitType}_violations_$today';
    
    final violations = prefs.getInt(key) ?? 0;

    // Use default cooldown tiers: [5, 10, 15, 20, 30, 60]
    final tiers = DEFAULT_COOLDOWN_TIERS_SECONDS;

    final index = violations.clamp(0, tiers.length - 1);
    final cooldown = tiers[index];
    
    print("🔍 COOLDOWN CALCULATION:");
    print("   Limit type: $limitType");
    print("   Current violations: $violations");
    print("   Tier index: $index");
    print("   Cooldown: ${cooldown}s");
    print("   Tiers: $tiers");
    print("   ✅ If you see >5s, you have OLD violations! Click 'Reset All Data' button!");
    
    return cooldown;
  }

  /// Record a violation (ONLY for session and unlock limits, NOT daily)
  /// Daily limit violations are tracked separately and reset only at midnight
  static Future<void> recordViolation(String limitType) async {
    // Don't record violations for daily limit - it's a separate daily tracking system
    if (limitType == 'daily_limit') {
      print("ℹ️ Daily limit reached - no violation recorded (resets at midnight)");
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${limitType}_violations_$today';
    
    final oldViolations = prefs.getInt(key) ?? 0;
    final newViolations = oldViolations + 1;
    await prefs.setInt(key, newViolations);
    
    // Track when violation occurred for good behavior tracking
    if (limitType == 'session_limit') {
      await prefs.setInt('last_session_violation_$today', now);
    } else if (limitType == 'unlock_limit') {
      await prefs.setInt('last_unlock_violation_$today', now);
    }
    
    final nextCooldown = DEFAULT_COOLDOWN_TIERS_SECONDS[newViolations.clamp(0, DEFAULT_COOLDOWN_TIERS_SECONDS.length - 1)];
    print("🚨 $limitType violation recorded");
    print("   Violations: $oldViolations → $newViolations");
    print("   Next violation cooldown will be: ${nextCooldown}s");
  }

  /// Apply side-effects for a violation (called before setting cooldown)
  /// - For session: reset session timer to 0
  /// - For unlock: set unlock base so next count starts at 0 relative
  /// - Also resets warning flags so warnings can be shown again after cooldown
  /// Called after a violation is applied to reset appropriate counters
  /// 
  /// CRITICAL TRACKING RULES:
  /// 1. DAILY USAGE: Never resets except at midnight - accumulates across all sessions
  /// 2. SESSION TIMER: Resets only on session violation or cooldown end - tracks continuous usage
  /// 3. UNLOCK COUNTER: Resets only on unlock violation - uses relative base to track from zero
  /// 
  /// Each violation type handles ONLY its own counter:
  /// - Session violation: Reset session timer only (daily usage continues accumulating)
  /// - Unlock violation: Set unlock base only (daily usage continues accumulating)
  /// - Daily violation: Nothing resets, everything locked until midnight
  static Future<void> onViolationApplied({
    required String limitType,
    required int currentMostUnlockedCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;

    // ✅ CRITICAL: Update last_check to NOW to skip all events during lock period
    // This prevents usage/unlocks from accumulating while user is locked out
    await prefs.setInt('last_check_$today', now);
    print('⏭️ Updated last_check to NOW - events during lock will be skipped');

    // Clear active app state (stops current tracking session)
    await prefs.remove('active_app_$today');
    await prefs.remove('active_start_$today');
    
    if (limitType == 'session_limit') {
      // Log session end due to violation
      final sessionStartMs = prefs.getInt('session_start_$today');
      if (sessionStartMs != null) {
        await DatabaseHelper.instance.logSessionEnd(
          sessionStart: sessionStartMs,
          reason: 'violation',
          appsUsed: null,
        );
      }
      
      // Reset ONLY session-specific data (daily usage persists!)
      await prefs.remove('session_start_$today');
      await prefs.remove('last_activity_$today');
      await prefs.remove('session_accumulated_ms_$today');
      
      // Reset session warning flags so they can trigger again after cooldown
      await prefs.remove('session_warning_sent_$today');
      await prefs.remove('session_warning_50_$today');
      await prefs.remove('session_warning_75_$today');
      await prefs.remove('session_warning_90_$today');
      await prefs.remove('session_final_warning_$today');
      
      print('🔄 Session violation - Session timer reset (daily usage continues accumulating)');
    }
    else if (limitType == 'unlock_limit') {
      // Set unlock base to current count (next violation will be relative to this)
      await prefs.setInt('unlock_base_$today', currentMostUnlockedCount);
      
      // Reset unlock warning flags so they can trigger again after cooldown
      await prefs.remove('unlock_warning_sent_$today');
      await prefs.remove('unlock_warning_50_$today');
      await prefs.remove('unlock_warning_75_$today');
      await prefs.remove('unlock_warning_90_$today');
      await prefs.remove('unlock_final_warning_$today');
      
      print('🔄 Unlock violation - Unlock base set to $currentMostUnlockedCount (daily usage continues accumulating)');
    }
    else if (limitType == 'daily_limit') {
      // Daily limit: Nothing resets, all data persists until midnight
      // Daily usage lock remains active until new day
      print('🔒 Daily limit violation - All apps locked until midnight (all data persists, no resets)');
    }
  }

  /// Decrease violation count if user behaves well (no violations for a period)
  /// This reduces cooldown time gradually when user avoids violations
  static Future<void> decreaseViolations(String limitType) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '${limitType}_violations_$today';
    
    final violations = prefs.getInt(key) ?? 0;
    if (violations > 0) {
      await prefs.setInt(key, violations - 1);
      print("✅ $limitType violations decreased to ${violations - 1} (user behaving well)");
    }
  }

  /// Check if user has been behaving well (no violations for a period) and decrease violations
  /// Called periodically to reward good behavior
  static Future<void> checkAndRewardGoodBehavior() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Time threshold: decrease violations after 30 minutes of good behavior
    const goodBehaviorMinutes = 30;
    const goodBehaviorMs = goodBehaviorMinutes * 60 * 1000;
    
    // Check session violations
    final sessionViolations = prefs.getInt('session_violations_$today') ?? 0;
    if (sessionViolations > 0) {
      final lastSessionViolation = prefs.getInt('last_session_violation_$today');
      if (lastSessionViolation != null) {
        final timeSinceViolation = now - lastSessionViolation;
        if (timeSinceViolation >= goodBehaviorMs) {
          // User has been good for 30+ minutes, decrease violation
          await decreaseViolations('session_limit');
          // Reset the timer
          await prefs.setInt('last_session_violation_$today', now);
        }
      }
    }
    
    // Check unlock violations
    final unlockViolations = prefs.getInt('unlock_violations_$today') ?? 0;
    if (unlockViolations > 0) {
      final lastUnlockViolation = prefs.getInt('last_unlock_violation_$today');
      if (lastUnlockViolation != null) {
        final timeSinceViolation = now - lastUnlockViolation;
        if (timeSinceViolation >= goodBehaviorMs) {
          // User has been good for 30+ minutes, decrease violation
          await decreaseViolations('unlock_limit');
          // Reset the timer
          await prefs.setInt('last_unlock_violation_$today', now);
        }
      }
    }
  }

  /// Start or update continuous session tracking (works across ALL selected apps)
  /// 
  /// IMPORTANT: Session tracking behavior with inactivity rule:
  /// - Session continues across app switches (switching between selected apps doesn't reset session)
  /// - Session continues if user briefly leaves and returns within inactivity threshold
  /// - Session RESETS if user doesn't use any selected app for inactivity threshold
  /// - Inactivity threshold: 5 minutes (real mode) / 30 seconds (testing mode)
  /// - Only other resets when:
  ///   1. Session limit is violated (cooldown applied)
  ///   2. New day starts (midnight reset)
  /// - Switching to unselected apps pauses session tracking
  /// - If user returns within threshold, same session continues
  /// - If user returns after threshold, new session starts
  static Future<void> updateSessionActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final inactivityThreshold = await _getEffectiveInactivityThresholdMinutes();
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    final lastActivityMs = prefs.getInt('last_activity_$today');
    int accMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;

    // Check if there was a gap exceeding inactivity threshold
    if (sessionStartMs != null && lastActivityMs != null) {
      final inactivityMinutes = (now - lastActivityMs) / 1000 / 60;
      
      if (inactivityMinutes >= inactivityThreshold) {
        // User was inactive beyond threshold - session has ended
        final sessionDurationMinutes = accMs / 1000 / 60;
        
        // Log the ended session to database
        await DatabaseHelper.instance.logSessionEnd(
          sessionStart: sessionStartMs,
          reason: 'inactivity',
          appsUsed: null, // Could enhance this later to track which apps were used
        );
        
        // Reset session - start new one
        await prefs.remove('session_start_$today');
        await prefs.setInt('session_start_$today', now);
        accMs = 0; // reset accumulated active time for the new session
        
        // Log new session start
        await DatabaseHelper.instance.logSessionStart();
        
        print("🔄 Session ended due to ${inactivityMinutes.toStringAsFixed(1)} min inactivity (threshold: ${inactivityThreshold.toStringAsFixed(1)} min). Active duration was ${sessionDurationMinutes.toStringAsFixed(1)} min. New session started.");
      } else {
        // Within threshold - add active time since last activity
        // ✅ CRITICAL: Only add time if it's reasonable (< 2 seconds)
        // This prevents adding large gaps when switching apps or reopening
        final deltaMs = now - lastActivityMs;
        if (deltaMs > 0) {
          // Only add time if delta is small (< 2 seconds = normal monitoring interval)
          // Larger gaps mean user was away from selected apps
          if (deltaMs <= 2000) {
            accMs += deltaMs;
            final deltaSec = deltaMs / 1000;
            print("   ➕ Adding ${deltaSec.toStringAsFixed(1)}s to session (continuous usage)");
          } else {
            final deltaSec = deltaMs / 1000;
            print("   ⏭️ Skipping ${deltaSec.toStringAsFixed(1)}s gap (user was away from selected apps)");
          }
        }
        final sessionMinutes = accMs / 1000 / 60;
        print("⏱️ Session continues (inactivity: ${inactivityMinutes.toStringAsFixed(1)} min < ${inactivityThreshold.toStringAsFixed(1)} min). Active: ${sessionMinutes.toStringAsFixed(1)} min");
      }
    }
    
    // Update last activity time (this keeps session alive across app switches)
    await prefs.setInt('last_activity_$today', now);
    await prefs.setInt('session_accumulated_ms_$today', accMs);
    
    // Start new session if none exists
    if (sessionStartMs == null || prefs.getInt('session_start_$today') == null) {
      await prefs.setInt('session_start_$today', now);
      await prefs.setInt('session_accumulated_ms_$today', 0);
      await DatabaseHelper.instance.logSessionStart();
      print("📱 New session started at ${DateTime.now().toString().substring(11, 19)}");
    }
  }

  /// Force break (called when session limit reached)
  static Future<void> forceBreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    
    // Log session end due to violation
    if (sessionStartMs != null) {
      await DatabaseHelper.instance.logSessionEnd(
        sessionStart: sessionStartMs,
        reason: 'violation',
        appsUsed: null,
      );
    }
    
    // End current session
    await prefs.remove('session_start_$today');
    await prefs.remove('last_activity_$today');
    await prefs.remove('session_accumulated_ms_$today');
    
    // Legacy: keep a marker in case legacy UI reads it
    await prefs.setInt('last_break_end_$today', now);
    
    print("🛑 Session ended due to violation - cooldown will manage reset");
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
    await _ensureNewDayReset(prefs);
    
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
      // Cooldown expired - call clearCooldown to properly clean up
      print("✅ Cooldown expired - clearing cooldown state");
      await clearCooldown();
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
  /// Daily limit is separate from session/unlock limits:
  /// - Daily limit resets only at midnight
  /// - Session/unlock limits reset immediately after cooldown
  /// - Stats tracking persists throughout the day and only resets at midnight
  static Future<void> setDailyLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('daily_locked', true);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.remove('daily_warning_50_$today');
    await prefs.remove('daily_warning_75_$today');
    await prefs.remove('daily_warning_90_$today');
    await prefs.remove('daily_final_warning_$today');
    print("🔒 Daily lock set - unlocks tomorrow (separate from session/unlock tracking)");
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

    final endDateTime = DateTime.fromMillisecondsSinceEpoch(endTime);
    print("🔒 Cooldown set: $reason for ${seconds}s (until ${endDateTime.toString().substring(11, 19)})");
  }

  /// Clear cooldown (only for session/unlock limits, NOT daily limit)
  /// Daily limit should only be cleared at midnight when new day resets
  /// ✅ CRITICAL: After cooldown ends, tracking resumes immediately
  static Future<void> clearCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // ✅ CRITICAL: Get cooldown reason BEFORE removing it
    final cooldownReason = prefs.getString('cooldown_reason');
    
    // Log session end due to cooldown completion (if session was active)
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs != null) {
      await DatabaseHelper.instance.logSessionEnd(
        sessionStart: sessionStartMs,
        reason: 'cooldown',
        appsUsed: null,
      );
    }
    
    // ✅ CRITICAL: Update last_check to NOW when cooldown ends
    // This ensures events during cooldown period are skipped for violation tracking
    // BUT: Statistics tracking continues (events are still processed for screen time)
    await prefs.setInt('last_check_$today', now);
    print('⏭️ Updated last_check to NOW - events during cooldown skipped for violation tracking');
    
    // ✅ CRITICAL FIX: For unlock_limit cooldown, ensure unlock tracking resumes
    // The unlock_base is already set correctly during violation
    // After cooldown ends, tracking will resume and delta will be calculated correctly
    if (cooldownReason == 'unlock_limit') {
      final currentBase = prefs.getInt('unlock_base_$today') ?? 0;
      print('🔄 Unlock cooldown ended - unlock counter will restart from 0');
      print('   Unlock base preserved: $currentBase (tracking will resume immediately)');
      print('   Next unlock will increment count, delta will be calculated from base');
    }
    
    // ✅ CRITICAL FIX: For session_limit cooldown, ensure session tracking can resume
    // Session tracking is already reset during violation, so it will start fresh
    if (cooldownReason == 'session_limit') {
      print('🔄 Session cooldown ended - session tracking will restart from 0');
      print('   Session timer reset, new session will start when user opens selected app');
    }
    
    await prefs.remove('cooldown_end');
    await prefs.remove('cooldown_reason');
    await prefs.remove('cooldown_app');
    await prefs.remove('session_warning_50_$today');
    await prefs.remove('session_warning_75_$today');
    await prefs.remove('session_warning_90_$today');
    await prefs.remove('session_final_warning_$today');
    await prefs.remove('unlock_warning_50_$today');
    await prefs.remove('unlock_warning_75_$today');
    await prefs.remove('unlock_warning_90_$today');
    await prefs.remove('unlock_final_warning_$today');
    // Note: daily_locked is NOT cleared here - it resets only at midnight
    // This allows daily limit to persist until next day
    print("🔓 Cooldown cleared (session/unlock limits) - tracking will resume from NOW");
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
    await prefs.remove('session_accumulated_ms_$today');
    await prefs.remove('daily_locked');
    await prefs.remove('unlock_base_$today');
    await prefs.remove('daily_warning_50_$today');
    await prefs.remove('daily_warning_75_$today');
    await prefs.remove('daily_warning_90_$today');
    await prefs.remove('daily_final_warning_$today');
    await prefs.remove('session_warning_50_$today');
    await prefs.remove('session_warning_75_$today');
    await prefs.remove('session_warning_90_$today');
    await prefs.remove('session_final_warning_$today');
    await prefs.remove('unlock_warning_50_$today');
    await prefs.remove('unlock_warning_75_$today');
    await prefs.remove('unlock_warning_90_$today');
    await prefs.remove('unlock_final_warning_$today');
    
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

    // Priority 2: Check session limit
    if (await isSessionLimitExceeded()) {
      return {
        'type': 'session_limit',
        'message': 'Continuous usage limit reached',
      };
    }

    // Priority 3: Check unlock limit (relative to base)
    if (await isUnlockLimitExceeded(totalUnlocks)) {
      return {
        'type': 'unlock_limit',
        'message': 'Unlock limit reached',
      };
    }

    return null;
  }

  // ---------- Configurable Limits (for testing) ----------
  /// Set custom limits (useful for testing - just set low values)
  static Future<void> setLimits({
    double? dailyHours,
    double? sessionMinutes,
    int? unlockLimit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (dailyHours != null) {
      await prefs.setDouble(KEY_DAILY_LIMIT_HOURS, dailyHours);
    }
    if (sessionMinutes != null) {
      await prefs.setDouble(KEY_SESSION_LIMIT_MINUTES, sessionMinutes);
    }
    if (unlockLimit != null) {
      await prefs.setInt(KEY_UNLOCK_LIMIT, unlockLimit);
    }
    print("⚙️ Limits updated - Daily: ${dailyHours ?? 'unchanged'}, Session: ${sessionMinutes ?? 'unchanged'}, Unlock: ${unlockLimit ?? 'unchanged'}");
  }

  /// Reset limits to defaults
  static Future<void> resetLimitsToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_DAILY_LIMIT_HOURS);
    await prefs.remove(KEY_SESSION_LIMIT_MINUTES);
    await prefs.remove(KEY_UNLOCK_LIMIT);
    print("⚙️ Limits reset to defaults");
  }

  /// Get current thresholds (public for MonitorService)
  /// Uses configured values if set, otherwise defaults
  /// ✅ Automatically resets if old testing values are detected (10+ hours, 60+ minutes)
  static Future<Map<String, dynamic>> getThresholds() async {
    final prefs = await SharedPreferences.getInstance();
    
    // ✅ AUTO-RESET: If stored values are unreasonably high (old testing values), reset to defaults
    final storedDaily = prefs.getDouble(KEY_DAILY_LIMIT_HOURS);
    final storedSession = prefs.getDouble(KEY_SESSION_LIMIT_MINUTES);
    
    bool needsReset = false;
    if (storedDaily != null && storedDaily > 5.0) {
      // Old testing value detected (10 hours) - reset to default
      print("⚠️ Old testing value detected (daily: ${storedDaily}h) - resetting to default (${DEFAULT_DAILY_LIMIT_HOURS}h)");
      needsReset = true;
    }
    if (storedSession != null && storedSession > 30.0) {
      // Old testing value detected (60 minutes) - reset to default
      print("⚠️ Old testing value detected (session: ${storedSession}m) - resetting to default (${DEFAULT_SESSION_LIMIT_MINUTES}m)");
      needsReset = true;
    }
    
    if (needsReset) {
      await resetLimitsToDefaults();
      print("✅ Limits reset to defaults - Daily: ${DEFAULT_DAILY_LIMIT_HOURS}h, Session: ${DEFAULT_SESSION_LIMIT_MINUTES}m, Unlock: ${DEFAULT_UNLOCK_LIMIT}");
    }
    
    return {
      'dailyHours': prefs.getDouble(KEY_DAILY_LIMIT_HOURS) ?? DEFAULT_DAILY_LIMIT_HOURS,
      'sessionMinutes': prefs.getDouble(KEY_SESSION_LIMIT_MINUTES) ?? DEFAULT_SESSION_LIMIT_MINUTES,
      'unlockLimit': prefs.getInt(KEY_UNLOCK_LIMIT) ?? DEFAULT_UNLOCK_LIMIT,
    };
  }

  static Future<Map<String, dynamic>> _getThresholds() async {
    return await getThresholds();
  }

  static Future<void> _ensureNewDayReset(SharedPreferences prefs) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = prefs.getString('lock_state_date');
    if (lastDate == today) return;

    // New day: reset only lock-related states (analytics handled elsewhere)
    await prefs.setString('lock_state_date', today);
    
    // Log any active session end due to midnight
    if (lastDate != null && lastDate.isNotEmpty) {
      final sessionStartMs = prefs.getInt('session_start_$lastDate');
      if (sessionStartMs != null) {
        await DatabaseHelper.instance.logSessionEnd(
          sessionStart: sessionStartMs,
          reason: 'midnight',
          appsUsed: null,
        );
      }
    }
    
    await prefs.remove('session_violations_$today');
    await prefs.remove('unlock_violations_$today');
    await prefs.remove('session_start_$today');
    await prefs.remove('last_activity_$today');
    await prefs.remove('last_break_end_$today');
    await prefs.remove('daily_locked');
    await prefs.remove('cooldown_end');
    await prefs.remove('cooldown_reason');
    await prefs.remove('cooldown_app');
    await prefs.remove('unlock_base_$today');
    await prefs.remove('daily_warning_50_$today');
    await prefs.remove('daily_warning_75_$today');
    await prefs.remove('daily_warning_90_$today');
    await prefs.remove('daily_final_warning_$today');
    await prefs.remove('session_warning_50_$today');
    await prefs.remove('session_warning_75_$today');
    await prefs.remove('session_warning_90_$today');
    await prefs.remove('session_final_warning_$today');
    await prefs.remove('unlock_warning_50_$today');
    await prefs.remove('unlock_warning_75_$today');
    await prefs.remove('unlock_warning_90_$today');
    await prefs.remove('unlock_final_warning_$today');
    await prefs.remove('daily_warning_sent_$today');
    await prefs.remove('session_warning_sent_$today');
    await prefs.remove('unlock_warning_sent_$today');
    
    // Reset warning flags for new day
    if (lastDate != null && lastDate.isNotEmpty) {
      await prefs.remove('daily_warning_sent_$lastDate');
      await prefs.remove('session_warning_sent_$lastDate');
      await prefs.remove('unlock_warning_sent_$lastDate');
      await prefs.remove('daily_warning_50_$lastDate');
      await prefs.remove('daily_warning_75_$lastDate');
      await prefs.remove('daily_warning_90_$lastDate');
      await prefs.remove('daily_final_warning_$lastDate');
      await prefs.remove('session_warning_50_$lastDate');
      await prefs.remove('session_warning_75_$lastDate');
      await prefs.remove('session_warning_90_$lastDate');
      await prefs.remove('session_final_warning_$lastDate');
      await prefs.remove('unlock_warning_50_$lastDate');
      await prefs.remove('unlock_warning_75_$lastDate');
      await prefs.remove('unlock_warning_90_$lastDate');
      await prefs.remove('unlock_final_warning_$lastDate');
    }
    
    // Reset violation tracking timers
    await prefs.remove('last_session_violation_$today');
    await prefs.remove('last_unlock_violation_$today');
    
    print('🌅 New day detected in LockStateManager → state cleared');
  }
}