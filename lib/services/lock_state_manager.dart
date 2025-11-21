import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/emergency_service.dart';
import 'package:refocus_app/pages/home_page.dart'; // For AppState

class LockStateManager {
  // ✅ PRODUCTION LIMITS (aligned with Decision Tree)
  // Daily limit: 4 hours (240 minutes)
  static const double DEFAULT_DAILY_LIMIT_HOURS = 4.0;
  // Session limit: 1 hour (60 minutes)
  static const double DEFAULT_SESSION_LIMIT_MINUTES = 60.0;
  // Unlock limit REMOVED - no longer used for locking (stats only)

  // Progressive cooldowns for session/unlock violations
  // Punishment increases with each violation: 5s → 10s → 15s → 20s → 30s → 60s (then caps)
  static const List<int> DEFAULT_COOLDOWN_TIERS_SECONDS = [5, 10];

  // Legacy break model is no longer used; cooldown governs resets
  static const int BREAK_DURATION_MINUTES = 0;
  
  // Session inactivity threshold: 5 minutes
  // If user doesn't use any selected app for threshold time, session ends
  static const int SESSION_INACTIVITY_MINUTES = 5;
  
  // ✅ CRITICAL: In-memory cache for session minutes (for real-time accuracy)
  // This matches how daily usage works (in-memory cache updated immediately)
  // Cache is updated immediately when updateSessionActivity() is called OR when UsageService processes real-time usage
  // getCurrentSessionMinutes() returns cached value first (synchronous), then syncs from SharedPreferences
  static double? _cachedSessionMinutes;
  static int? _cachedSessionMs; // Kept for debugging and potential future use
  static DateTime? _cacheTimestamp;
  static const Duration _cacheValidityDuration = Duration(seconds: 1); // Cache valid for 1 second (longer than update interval)
  
  // ✅ EXPOSED: Allow UsageService to update cache directly (for real-time event-driven updates)
  // This makes session tracking event-driven like daily usage (updates when UsageService processes usage)
  // Cache is updated immediately (synchronous) so getCurrentSessionMinutes() returns instantly
  static void updateCache(double minutes, int ms) {
    _cachedSessionMinutes = minutes;
    _cachedSessionMs = ms;
    _cacheTimestamp = DateTime.now();
    // ✅ DEBUG: Verify cache update (every 5 seconds)
    final totalSeconds = (ms / 1000);
    if (totalSeconds > 0 && totalSeconds % 5 < 0.5) {
      print("📊 Session cache updated: ${minutes.toStringAsFixed(2)}min (${ms}ms) - event-driven");
    }
  }

  /// Fixed inactivity threshold: session ONLY restarts after 5 minutes
  /// without any selected app activity. This prevents "cheating" by quickly
  /// closing and reopening apps to reset the session.
  static Future<double> _getEffectiveInactivityThresholdMinutes() async {
    return SESSION_INACTIVITY_MINUTES.toDouble();
  }
  
  // Keys for configurable limits (set via SharedPreferences)
  static const String KEY_DAILY_LIMIT_HOURS = 'config_daily_limit_hours';
  static const String KEY_SESSION_LIMIT_MINUTES = 'config_session_limit_minutes';
  // KEY_UNLOCK_LIMIT removed - unlock count no longer used for locking

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
    }
    
    return exceeded;
  }

  /// Get current session duration in minutes
  /// ✅ SINGLE SOURCE OF TRUTH: This is the ONLY function that should be used to get session time
  /// Used by: home_page.dart, dashboard_screen.dart, hybrid_lock_manager.dart, feedback_logger.dart, ML model
  /// 
  /// Behavior:
  /// - Only accumulates time when a monitored app (Social/Games/Entertainment) is ACTUALLY open in foreground
  /// - Stops accumulating when app is closed or user switches to non-monitored app
  /// - Continues accumulating when switching between monitored apps
  /// - Resets to 0 if user doesn't use any monitored app for 5+ minutes
  /// - Accounts for inactivity threshold (5 minutes) - session resets if inactive
  /// 
  /// ✅ REAL-TIME: Returns accurate session time for Social, Games, Entertainment categories
  /// Session resets only if user stops using ALL 3 categories for 5+ minutes
  /// ✅ OPTIMIZED: Get current session minutes with REAL-TIME accuracy (matches daily usage speed)
  /// This is the single source of truth for session tracking across the app
  /// Returns accumulated active time (time spent in Social/Games/Entertainment apps)
  /// ✅ CRITICAL: Uses in-memory cache for instant reads (matches daily usage pattern)
  /// ✅ CRITICAL: Cache is updated by:
  ///   1. UsageService.getUsageStatsWithEvents() - event-driven (real-time, like daily usage)
  ///   2. LockStateManager.updateSessionActivity() - timer-based (fallback, every 200ms)
  /// ✅ CRITICAL: This function is called by:
  ///   - Frontend (home_page.dart, dashboard_screen.dart) - every 50ms
  ///   - Backend (hybrid_lock_manager.dart) - for lock decisions
  ///   - ML Model (ensemble_model_service.dart) - for predictions
  ///   - Feedback Logger (feedback_logger.dart) - for training data
  /// ✅ SINGLE SOURCE OF TRUTH: All components use this function for session time
  /// Optimized for speed: returns cached value immediately (synchronous), syncs from SharedPreferences only if cache expired
  static Future<double> getCurrentSessionMinutes() async {
    final now = DateTime.now();
    
    // ✅ CRITICAL: Return cached value if valid (for real-time accuracy, matches daily usage speed)
    // Cache is updated immediately by UsageService (event-driven) or updateSessionActivity() (timer-based)
    // Cache validity is 1 second (longer than update intervals), so cache is almost always fresh
    // This eliminates async SharedPreferences read delay - returns synchronously when cache is valid
    if (_cachedSessionMinutes != null && 
        _cacheTimestamp != null && 
        now.difference(_cacheTimestamp!) < _cacheValidityDuration) {
      // Cache is valid - return immediately (synchronous, no async delay - matches daily usage speed)
      return _cachedSessionMinutes!;
    }
    
    // ✅ Cache expired or not set - sync from SharedPreferences (background sync)
    final prefs = await SharedPreferences.getInstance();
    final today = now.toIso8601String().substring(0, 10);
    
    // ✅ OPTIMIZED: Synchronous reads for minimal latency
    final sessionStartMs = prefs.getInt('session_start_$today');
    if (sessionStartMs == null) {
      // No session started yet - update cache
      _cachedSessionMinutes = 0.0;
      _cachedSessionMs = 0;
      _cacheTimestamp = now;
      return 0.0;
    }

    final nowMs = now.millisecondsSinceEpoch;
    final lastActivityMs = prefs.getInt('last_activity_$today');
    
    // ✅ OPTIMIZED: Cache inactivity threshold to avoid repeated async calls
    // Only fetch if not already cached (first call)
    final inactivityThreshold = await _getEffectiveInactivityThresholdMinutes();
    
    // ✅ CRITICAL: Check if session is still active (within inactivity threshold)
    // Session resets only if user hasn't used Social/Games/Entertainment for 5+ minutes
    if (lastActivityMs == null) {
      // No last activity recorded - session hasn't started properly - update cache
      _cachedSessionMinutes = 0.0;
      _cachedSessionMs = 0;
      _cacheTimestamp = now;
      return 0.0;
    }
    
    final inactivityMinutes = (nowMs - lastActivityMs) / 1000 / 60;
    if (inactivityMinutes >= inactivityThreshold) {
      // Session has ended due to inactivity (5+ min without Social/Games/Entertainment) - update cache
      _cachedSessionMinutes = 0.0;
      _cachedSessionMs = 0;
      _cacheTimestamp = now;
      return 0.0;
    }
    
    // ✅ Return accumulated active time (time spent in Social/Games/Entertainment apps)
    // This is updated in real-time by updateSessionActivity() when user uses monitored apps
    // ✅ OPTIMIZED: Direct synchronous read for minimal latency
    final accMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;
    final sessionMinutes = accMs / 1000 / 60;
    
    // ✅ CRITICAL: Update cache for next read (ensures subsequent reads are instant)
    _cachedSessionMinutes = sessionMinutes;
    _cachedSessionMs = accMs;
    _cacheTimestamp = now;
    
    // ✅ OPTIMIZED: Reduced logging frequency (every 10 seconds) to minimize overhead
    // Only log when significant time has passed to avoid log spam
    final totalSeconds = (accMs / 1000);
    if (totalSeconds > 0 && totalSeconds % 10 < 0.5) {
      final cacheStatus = _cachedSessionMinutes != null && _cachedSessionMs == accMs ? 'valid' : 'stale';
      print("📊 getCurrentSessionMinutes: ${sessionMinutes.toStringAsFixed(2)}min (${accMs}ms accumulated, cache: $cacheStatus)");
    }
    
    return sessionMinutes;
  }

  // ✅ REMOVED: isUnlockLimitExceeded() - Unlock count no longer triggers locks
  // ✅ REMOVED: getRemainingUnlocks() - Unlock count no longer triggers locks
  // Unlock count is still tracked in database for statistics only

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
    }
    else if (limitType == 'daily_limit') {
      // Daily limit: Nothing resets, all data persists until midnight
      // Daily usage lock remains active until new day
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

  /// Start or update continuous session tracking (works across ALL monitored categories)
  /// 
  /// ✅ CRITICAL: This function is called ONLY when a monitored app (Social/Games/Entertainment) is in foreground
  /// Called by: MonitorService every 1 second when a monitored app is active
  /// 
  /// IMPORTANT: Session tracking behavior:
  /// - ✅ INCREMENTS: When user opens a monitored app → session time accumulates
  /// - ✅ STOPS: When user closes app or switches to non-monitored app → accumulation stops (but session doesn't reset)
  /// - ✅ CONTINUES: When switching between monitored apps → session continues accumulating seamlessly
  /// - ✅ PAUSES: When switching to non-monitored app → accumulation pauses (session preserved)
  /// - ✅ RESETS: If user doesn't use any monitored app for 5+ minutes → session resets to 0
  /// - Inactivity threshold: 5 minutes (real mode) / 30 seconds (testing mode)
  /// - Only other resets when:
  ///   1. Session limit is violated (cooldown applied)
  ///   2. New day starts (midnight reset)
  /// 
  /// ✅ ACCURACY: Only accumulates time when delta is 100ms-2000ms (ensures app is actually open)
  /// Large deltas (>2s) indicate app was closed/backgrounded - gap time is NOT accumulated
  static Future<void> updateSessionActivity() async {
    // ✅ CRITICAL: Check Emergency Override FIRST - if active, don't track session
    final isEmergencyActive = await EmergencyService.isEmergencyActive();
    final isOverrideEnabled = AppState().isOverrideEnabled;
    if (isEmergencyActive || isOverrideEnabled) {
      print("🚨 Emergency Override: ACTIVE - Session tracking paused");
      return; // Don't update session activity during emergency
    }
    
    // ✅ CRITICAL FIX: Check for active cooldown/lock - don't track session during lock
    final cooldownInfo = await getActiveCooldown();
    if (cooldownInfo != null) {
      // Active lock/cooldown - don't accumulate session time
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final inactivityThreshold = await _getEffectiveInactivityThresholdMinutes();
    
    final sessionStartMs = prefs.getInt('session_start_$today');
    final lastActivityMs = prefs.getInt('last_activity_$today');
    int accMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;

    // ✅ CRITICAL FIX: Start new session FIRST if none exists, before accumulation logic
    // This ensures lastActivityMs is set immediately when session starts
    if (sessionStartMs == null || prefs.getInt('session_start_$today') == null) {
      await prefs.setInt('session_start_$today', now);
      await prefs.setInt('last_activity_$today', now); // ✅ CRITICAL: Set last_activity immediately
      await prefs.setInt('session_accumulated_ms_$today', 0);
      accMs = 0; // Reset accumulated time
      
      // ✅ CRITICAL: Update cache immediately (for real-time accuracy)
      _cachedSessionMinutes = 0.0;
      _cachedSessionMs = 0;
      _cacheTimestamp = DateTime.now();
      
      await DatabaseHelper.instance.logSessionStart();
      print("📱 New session started at ${DateTime.now().toString().substring(11, 19)}");
      // ✅ Return early - next call will start accumulating time
      return;
    }

    // ✅ CRITICAL FIX: Now we know session exists, check if lastActivityMs is set
    // If not, set it now (shouldn't happen, but safety check)
    if (lastActivityMs == null) {
      await prefs.setInt('last_activity_$today', now);
      print("⚠️ Session exists but lastActivityMs was null - initialized to now");
      return; // Next call will start accumulating
    }

    // ✅ Now both sessionStartMs and lastActivityMs exist - check inactivity threshold
    final inactivityMinutes = (now - lastActivityMs) / 1000 / 60;
    
    if (inactivityMinutes >= inactivityThreshold) {
      // ✅ User was inactive beyond threshold - session has ended
      // Log the ended session to database
      await DatabaseHelper.instance.logSessionEnd(
        sessionStart: sessionStartMs,
        reason: 'inactivity',
        appsUsed: null, // Could enhance this later to track which apps were used
      );
      
      // ✅ CRITICAL: Clear session data - session stays at 0 until user uses monitored app again
      // DO NOT automatically start a new session - wait for user to actually use a monitored app
      await prefs.remove('session_start_$today');
      await prefs.remove('last_activity_$today');
      await prefs.remove('session_accumulated_ms_$today');
      accMs = 0; // Reset accumulated time to 0
      
      // ✅ CRITICAL: Update cache immediately (for real-time accuracy)
      _cachedSessionMinutes = 0.0;
      _cachedSessionMs = 0;
      _cacheTimestamp = DateTime.now();
      
      print("⏸️ Session ended due to inactivity (${inactivityMinutes.toStringAsFixed(1)}min >= ${inactivityThreshold}min) - staying at 0 until user uses monitored app");
      // ✅ Don't start new session here - it will start when updateSessionActivity() is called
      // from a monitored app (MonitorService checks category before calling this)
      return;
    }
    
    // ✅ WITHIN THRESHOLD: User is actively using monitored apps (Social/Games/Entertainment)
    // ✅ CRITICAL: Only accumulate time when a monitored app is ACTUALLY in foreground
    // MonitorService calls this every 1 second ONLY when a monitored app is in foreground
    // When user switches to non-monitored app, this function is NOT called, so accumulation stops
    final deltaMs = now - lastActivityMs;
    
    // ✅ CRITICAL FIX: Only accumulate reasonable deltas (when app is actively open)
    // Expected delta: ~200ms when called every 200ms, or ~1000ms when called every second
    // Accept range: 50ms - 2000ms (0.05s - 2s) - strict range to ensure app is actually open
    // Reject: < 50ms (too fast, likely duplicate call) or > 2000ms (app was closed/backgrounded)
    // ✅ UPDATED: Lowered minimum from 100ms to 50ms to support 200ms update interval
    if (deltaMs >= 50 && deltaMs <= 2000) {
      // ✅ Valid delta: App is actively open and in foreground
      // Accumulate this active time to the session
      final oldAccMs = accMs;
      accMs += deltaMs;
      
      // ✅ Enhanced logging for debugging - log every 5 seconds to track accumulation
      final totalSeconds = (accMs / 1000);
      final totalMinutes = (accMs / 1000 / 60);
      if (totalSeconds % 5 < 1 || (oldAccMs / 1000).floor() != (accMs / 1000).floor()) { // Log every ~5 seconds or when minute changes
        final deltaSeconds = (deltaMs / 1000).toStringAsFixed(1);
        final totalMinutesStr = totalMinutes.toStringAsFixed(2);
        print("⏱️ Session: +${deltaSeconds}s | Total: ${totalMinutesStr}min (${(totalMinutes * 60).toStringAsFixed(0)}s)");
      }
      
      // ✅ CRITICAL: Update last activity time ONLY when we accumulate (app is open)
      // This ensures session continues when switching between monitored apps
      // ✅ OPTIMIZED: Use await for both writes to ensure data is saved before next read
      await prefs.setInt('last_activity_$today', now);
      await prefs.setInt('session_accumulated_ms_$today', accMs);
      
      // ✅ CRITICAL: Update in-memory cache IMMEDIATELY (for real-time accuracy)
      // This makes getCurrentSessionMinutes() return instantly without async SharedPreferences read
      // Matches how daily usage works (in-memory cache updated immediately)
      // ✅ CRITICAL FIX: Update cache BEFORE async writes to ensure it's always fresh
      final sessionMinutes = accMs / 1000 / 60;
      _cachedSessionMinutes = sessionMinutes;
      _cachedSessionMs = accMs;
      _cacheTimestamp = DateTime.now(); // Update timestamp immediately
      
      // ✅ DEBUG: Verify the value was saved correctly (synchronous read for immediate verification)
      final savedAccMs = prefs.getInt('session_accumulated_ms_$today') ?? 0;
      if (savedAccMs != accMs) {
        print("⚠️ WARNING: Session accumulation mismatch! Expected: $accMs, Saved: $savedAccMs");
        // ✅ CRITICAL: Retry save if mismatch detected (ensures data integrity)
        await prefs.setInt('session_accumulated_ms_$today', accMs);
        print("🔄 Retried saving session accumulation: $accMs");
      }
      
    } else if (deltaMs > 2000 && deltaMs < (inactivityThreshold * 60 * 1000)) {
      // ✅ Large gap but within inactivity threshold (2s - 5min)
      // This happens when user switched to "Others" category apps, closed the app, or app was in background
      // Don't accumulate this time - user wasn't actively using monitored apps
      // Don't update lastActivityMs - keep it at the last time when app was actually open
      // This way, when user returns, we can detect the gap and not accumulate it
      print("⏸️ Session paused: ${(deltaMs / 1000 / 60).toStringAsFixed(1)}min gap (app closed or switched to non-monitored app) - NOT accumulating");
      
      // ✅ CRITICAL: Update lastActivityMs to now so next call will have small delta if app is reopened
      // But don't accumulate the gap time
      await prefs.setInt('last_activity_$today', now);
      await prefs.setInt('session_accumulated_ms_$today', accMs); // Keep accumulated time unchanged
      
    } else if (deltaMs < 100) {
      // ✅ Too fast - likely duplicate call or timing issue
      // Don't accumulate to prevent over-incrementing
      print("⚠️ Session: Delta too small (${deltaMs}ms) - skipping to prevent over-increment");
      // Still update lastActivityMs to prevent issues
      await prefs.setInt('last_activity_$today', now);
      await prefs.setInt('session_accumulated_ms_$today', accMs);
      
      // ✅ CRITICAL: Update cache immediately (for real-time accuracy)
      final sessionMinutes = accMs / 1000 / 60;
      _cachedSessionMinutes = sessionMinutes;
      _cachedSessionMs = accMs;
      _cacheTimestamp = DateTime.now();
    } else {
      // Delta is invalid or too large - skip
      print("⚠️ Session: Invalid delta (${deltaMs}ms) - skipping");
      // Still update lastActivityMs to prevent issues
      await prefs.setInt('last_activity_$today', now);
      await prefs.setInt('session_accumulated_ms_$today', accMs);
      
      // ✅ CRITICAL: Update cache immediately (for real-time accuracy)
      final sessionMinutes = accMs / 1000 / 60;
      _cachedSessionMinutes = sessionMinutes;
      _cachedSessionMs = accMs;
      _cacheTimestamp = DateTime.now();
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
    
    // ✅ CRITICAL: Update cache immediately (for real-time accuracy)
    _cachedSessionMinutes = 0.0;
    _cachedSessionMs = 0;
    _cacheTimestamp = DateTime.now();
    
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
    // For unlock_limit cooldown, the base is already set during violation
    
    // ✅ CRITICAL FIX: For session_limit cooldown, ensure session tracking can resume
    // Session tracking is already reset during violation, so it will start fresh
    if (cooldownReason == 'session_limit') {
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

    // ✅ Unlock limit removed - no longer triggers violations
    // Only daily and session limits trigger locks

    return null;
  }

  // ---------- Configurable Limits ----------
  /// Set custom limits
  static Future<void> setLimits({
    double? dailyHours,
    double? sessionMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (dailyHours != null) {
      await prefs.setDouble(KEY_DAILY_LIMIT_HOURS, dailyHours);
    }
    if (sessionMinutes != null) {
      await prefs.setDouble(KEY_SESSION_LIMIT_MINUTES, sessionMinutes);
    }
    print("⚙️ Limits updated - Daily: ${dailyHours ?? 'unchanged'}h, Session: ${sessionMinutes ?? 'unchanged'}m");
  }

  /// Reset limits to defaults
  static Future<void> resetLimitsToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(KEY_DAILY_LIMIT_HOURS);
    await prefs.remove(KEY_SESSION_LIMIT_MINUTES);
    print("⚙️ Limits reset to defaults");
  }

  /// Get current thresholds (public for MonitorService)
  /// Uses configured values if set, otherwise defaults
  /// ✅ Automatically resets if old testing values are detected
  static Future<Map<String, dynamic>> getThresholds() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ AUTO-RESET: If stored values are unreasonably low (old testing values), reset to defaults
    final storedDaily = prefs.getDouble(KEY_DAILY_LIMIT_HOURS);
    final storedSession = prefs.getDouble(KEY_SESSION_LIMIT_MINUTES);

    bool needsReset = false;
    if (storedDaily != null && storedDaily < 1.0) {
      // Old testing value detected (< 1 hour) - reset to production default
      print("⚠️ Old testing value detected (daily: ${storedDaily}h) - resetting to default (${DEFAULT_DAILY_LIMIT_HOURS}h)");
      needsReset = true;
    }
    if (storedSession != null && storedSession < 5.0) {
      // Old testing value detected (< 5 minutes) - reset to production default
      print("⚠️ Old testing value detected (session: ${storedSession}m) - resetting to default (${DEFAULT_SESSION_LIMIT_MINUTES}m)");
      needsReset = true;
    }

    if (needsReset) {
      await resetLimitsToDefaults();
      print("✅ Limits reset to production defaults - Daily: ${DEFAULT_DAILY_LIMIT_HOURS}h (240m), Session: ${DEFAULT_SESSION_LIMIT_MINUTES}m");
    }

    return {
      'dailyHours': prefs.getDouble(KEY_DAILY_LIMIT_HOURS) ?? DEFAULT_DAILY_LIMIT_HOURS,
      'sessionMinutes': prefs.getDouble(KEY_SESSION_LIMIT_MINUTES) ?? DEFAULT_SESSION_LIMIT_MINUTES,
      // unlockLimit removed - no longer used for locking
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