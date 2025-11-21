import 'package:shared_preferences/shared_preferences.dart';

/// Rule-based app lock manager
/// Replaces ML decision tree with direct threshold logic
/// This is simpler, faster, and more transparent than the ML model
class AppLockManager {
  // ✅ SHARED LIMITS SYSTEM (Updated Design)
  // All monitored categories (Social, Games, Entertainment) share the same limit pool
  // User can spend ALL time in ONE category if they choose
  // 
  // ✅ RULE-BASED DEFAULTS (User Preference - Stricter than Safety)
  // Purpose: For users who want immediate locking or prefer stricter control
  // Safety limits (360/120) still enforced as maximum protection in HybridLockManager
  // 
  // SHARED DAILY LIMIT: 180 minutes (3 hours) across ALL three categories combined (default)
  // SHARED SESSION LIMIT: 60 minutes (1 hour) across ALL three categories combined (default)
  // 
  // Example scenarios:
  // - User spends 3h all on Social → Social locks at 180 min (rule-based)
  // - User spends 1.5h Social + 1.5h Games → Combined 180 min locks both (rule-based)
  // - User spends 1h continuous session on Entertainment → Session lock triggers (rule-based)
  // - User exceeds 6h daily or 2h session → Safety limit enforced (always)
  // 
  // NOTE: Session tracking continues across ALL monitored categories
  // Switching from Social to Games continues the same session (no reset)
  // Session only resets after 5 minutes of inactivity (not using any monitored app)
  static const Map<String, Map<String, int>> _defaultThresholds = {
    'Social': {'daily': 180, 'session': 60},        // SHARED: 3h daily, 1h session (stricter default)
    'Games': {'daily': 180, 'session': 60},         // SHARED: 3h daily, 1h session (stricter default)
    'Entertainment': {'daily': 180, 'session': 60}, // SHARED: 3h daily, 1h session (stricter default)
    'Others': {'daily': 9999, 'session': 9999},      // Not monitored (no limits)
  };
  
  // Safety limits: Universal maximum (cannot be exceeded by rule-based)
  // These are enforced in HybridLockManager as absolute maximum protection
  static const int SAFETY_DAILY_MINUTES = 360;   // 6 hours/day maximum (universal)
  static const int SAFETY_SESSION_MINUTES = 120; // 2 hours/session maximum (universal)

  // Peak hours: 6 PM - 11 PM (18:00 - 23:00)
  // During peak hours, limits are reduced by 15%
  static const int PEAK_HOUR_START = 18;
  static const int PEAK_HOUR_END = 23;
  static const double PEAK_HOUR_REDUCTION = 0.85;

  /// Validate thresholds against safety limits
  /// Rule-based cannot exceed safety limits (universal maximum protection)
  static Future<Map<String, int>> _validateThresholds(
    String category,
    int dailyLimit,
    int sessionLimit,
  ) async {
    // Clamp rule-based limits to safety limits
    final validatedDaily = dailyLimit.clamp(0, SAFETY_DAILY_MINUTES);
    final validatedSession = sessionLimit.clamp(0, SAFETY_SESSION_MINUTES);
    
    if (dailyLimit > SAFETY_DAILY_MINUTES || sessionLimit > SAFETY_SESSION_MINUTES) {
      print('⚠️ Rule-based limits exceed safety limits - clamped to safety maximum');
      print('   Daily: $dailyLimit → $validatedDaily (safety: $SAFETY_DAILY_MINUTES)');
      print('   Session: $sessionLimit → $validatedSession (safety: $SAFETY_SESSION_MINUTES)');
    }
    
    return {
      'daily': validatedDaily,
      'session': validatedSession,
    };
  }

  /// Get thresholds for a category (with user customization support)
  /// ✅ VALIDATION: Rule-based limits cannot exceed safety limits
  static Future<Map<String, int>> _getThresholds(String category) async {
    // Normalize category name
    final normalizedCategory = _normalizeCategory(category);
    
    // Try to get user-customized thresholds from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final customDailyKey = 'threshold_${normalizedCategory}_daily';
    final customSessionKey = 'threshold_${normalizedCategory}_session';
    
    final customDaily = prefs.getInt(customDailyKey);
    final customSession = prefs.getInt(customSessionKey);
    
    // Use custom thresholds if available, otherwise use defaults
    // ✅ NULL SAFETY: Ensure defaults exist
    final defaults = _defaultThresholds[normalizedCategory] ?? _defaultThresholds['Others'];
    if (defaults == null) {
      // Fallback to safe defaults if category mapping fails
      print('⚠️ Category "$normalizedCategory" not found, using Others defaults');
      final othersDefaults = _defaultThresholds['Others']!;
      final dailyLimit = customDaily ?? othersDefaults['daily']!;
      final sessionLimit = customSession ?? othersDefaults['session']!;
      
      // ✅ VALIDATION: Ensure rule-based doesn't exceed safety (skip for Others category)
      if (normalizedCategory == 'Others') {
        return {
          'daily': dailyLimit,
          'session': sessionLimit,
        };
      }
      return await _validateThresholds(category, dailyLimit, sessionLimit);
    }
    
    final dailyLimit = customDaily ?? defaults['daily']!;
    final sessionLimit = customSession ?? defaults['session']!;
    
    // ✅ VALIDATION: Ensure rule-based doesn't exceed safety (skip for Others category)
    if (normalizedCategory == 'Others') {
      return {
        'daily': dailyLimit,
        'session': sessionLimit,
      };
    }
    return await _validateThresholds(category, dailyLimit, sessionLimit);
  }

  /// Normalize category name to match threshold keys
  static String _normalizeCategory(String category) {
    final normalized = category.trim();
    if (_defaultThresholds.containsKey(normalized)) {
      return normalized;
    }
    // Fallback to Others if category not found
    return 'Others';
  }

  /// Determines if an app should be locked based on usage
  /// ✅ SHARED LIMITS: For monitored categories (Social, Games, Entertainment),
  /// dailyUsageMinutes and sessionUsageMinutes should be COMBINED across all 3 categories.
  /// For "Others" category, these values are per-category (not monitored).
  /// Returns true if daily OR session limit is exceeded
  static Future<bool> shouldLockApp({
    required String category,
    required int dailyUsageMinutes, // ✅ COMBINED for monitored categories, per-category for Others
    required int sessionUsageMinutes, // ✅ COMBINED for monitored categories, per-category for Others
    required int currentHour,
  }) async {
    try {
      // ✅ CRITICAL: Check Emergency Override FIRST - if active, NEVER lock
      final prefs = await SharedPreferences.getInstance();
      final isEmergencyActive = prefs.getBool('emergency_override_enabled') ?? false;
      if (isEmergencyActive) {
        print("🚨 Emergency Override: ACTIVE - Skipping lock check");
        return false; // Never lock during emergency override
      }
      
    final thresholds = await _getThresholds(category);
    
      // ✅ NULL SAFETY: Validate thresholds exist
      final dailyLimit = thresholds['daily'];
      final sessionLimit = thresholds['session'];
      
      if (dailyLimit == null || sessionLimit == null) {
        print('⚠️ Invalid thresholds for category "$category", using Others defaults');
        final othersDefaults = _defaultThresholds['Others']!;
        final fallbackDaily = othersDefaults['daily']!;
        final fallbackSession = othersDefaults['session']!;
        
        // Apply peak hours if needed
        int effectiveDaily = fallbackDaily;
        int effectiveSession = fallbackSession;
        if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
          effectiveDaily = (effectiveDaily * PEAK_HOUR_REDUCTION).round();
          effectiveSession = (effectiveSession * PEAK_HOUR_REDUCTION).round();
        }
        
        return dailyUsageMinutes >= effectiveDaily || sessionUsageMinutes >= effectiveSession;
      }
      
      int effectiveDailyLimit = dailyLimit;
      int effectiveSessionLimit = sessionLimit;

    // Apply peak hours penalty (6 PM - 11 PM)
    if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
        effectiveDailyLimit = (effectiveDailyLimit * PEAK_HOUR_REDUCTION).round();
        effectiveSessionLimit = (effectiveSessionLimit * PEAK_HOUR_REDUCTION).round();
    }

    // Check if usage exceeds limits
      final exceedsDailyLimit = dailyUsageMinutes >= effectiveDailyLimit;
      final exceedsSessionLimit = sessionUsageMinutes >= effectiveSessionLimit;

    return exceedsDailyLimit || exceedsSessionLimit;
    } catch (e) {
      print('⚠️ Error in shouldLockApp for category "$category": $e');
      // ✅ SAFE FALLBACK: If error occurs, use conservative defaults
      final othersDefaults = _defaultThresholds['Others']!;
      final fallbackDaily = othersDefaults['daily']!;
      final fallbackSession = othersDefaults['session']!;
      
      // Apply peak hours if needed
      int effectiveDaily = fallbackDaily;
      int effectiveSession = fallbackSession;
      if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
        effectiveDaily = (effectiveDaily * PEAK_HOUR_REDUCTION).round();
        effectiveSession = (effectiveSession * PEAK_HOUR_REDUCTION).round();
      }
      
      return dailyUsageMinutes >= effectiveDaily || sessionUsageMinutes >= effectiveSession;
    }
  }

  /// Get remaining time before lock (in minutes)
  /// ✅ RELIABLE: Always returns valid remaining time with proper error handling
  static Future<Map<String, int>> getRemainingTime({
    required String category,
    required int dailyUsageMinutes,
    required int sessionUsageMinutes,
    required int currentHour,
  }) async {
    try {
      final thresholds = await _getThresholds(category);
      
      // ✅ NULL SAFETY: Validate thresholds exist
      final dailyLimit = thresholds['daily'];
      final sessionLimit = thresholds['session'];
      
      if (dailyLimit == null || sessionLimit == null) {
        print('⚠️ Invalid thresholds for getRemainingTime, using defaults');
        final othersDefaults = _defaultThresholds['Others']!;
        final fallbackDaily = othersDefaults['daily']!;
        final fallbackSession = othersDefaults['session']!;
        
        // Apply peak hours if needed
        int effectiveDaily = fallbackDaily;
        int effectiveSession = fallbackSession;
        if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
          effectiveDaily = (effectiveDaily * PEAK_HOUR_REDUCTION).round();
          effectiveSession = (effectiveSession * PEAK_HOUR_REDUCTION).round();
        }
        
        return {
          'dailyRemaining': (effectiveDaily - dailyUsageMinutes).clamp(0, effectiveDaily),
          'sessionRemaining': (effectiveSession - sessionUsageMinutes).clamp(0, effectiveSession),
        };
      }
      
      int effectiveDailyLimit = dailyLimit;
      int effectiveSessionLimit = sessionLimit;

      // Apply peak hours penalty (6 PM - 11 PM)
      if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
        effectiveDailyLimit = (effectiveDailyLimit * PEAK_HOUR_REDUCTION).round();
        effectiveSessionLimit = (effectiveSessionLimit * PEAK_HOUR_REDUCTION).round();
      }

      return {
        'dailyRemaining': (effectiveDailyLimit - dailyUsageMinutes).clamp(0, effectiveDailyLimit),
        'sessionRemaining': (effectiveSessionLimit - sessionUsageMinutes).clamp(0, effectiveSessionLimit),
      };
    } catch (e) {
      print('⚠️ Error getting remaining time: $e');
      // ✅ SAFE FALLBACK: Return zeros if error occurs
      return {
        'dailyRemaining': 0,
        'sessionRemaining': 0,
      };
    }
  }

  /// Get lock reason for user feedback
  /// ✅ RELIABLE: Always returns accurate lock reason with proper error handling
  static Future<String> getLockReason({
    required String category,
    required int dailyUsageMinutes,
    required int sessionUsageMinutes,
    required int currentHour,
  }) async {
    try {
      final thresholds = await _getThresholds(category);
      
      // ✅ NULL SAFETY: Validate thresholds exist
      final dailyLimit = thresholds['daily'];
      final sessionLimit = thresholds['session'];
      
      if (dailyLimit == null || sessionLimit == null) {
        print('⚠️ Invalid thresholds for lock reason, using defaults');
        final othersDefaults = _defaultThresholds['Others']!;
        final fallbackDaily = othersDefaults['daily']!;
        final fallbackSession = othersDefaults['session']!;
        
        // Apply peak hours if needed
        int effectiveDaily = fallbackDaily;
        int effectiveSession = fallbackSession;
        if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
          effectiveDaily = (effectiveDaily * PEAK_HOUR_REDUCTION).round();
          effectiveSession = (effectiveSession * PEAK_HOUR_REDUCTION).round();
        }
        
        final exceedsDailyLimit = dailyUsageMinutes >= effectiveDaily;
        final exceedsSessionLimit = sessionUsageMinutes >= effectiveSession;
        
        if (exceedsDailyLimit && exceedsSessionLimit) {
          return 'Both daily (${dailyUsageMinutes}/${effectiveDaily} min) and session (${sessionUsageMinutes}/${effectiveSession} min) limits exceeded';
        } else if (exceedsDailyLimit) {
          return 'Daily limit exceeded: ${dailyUsageMinutes}/${effectiveDaily} minutes';
        } else if (exceedsSessionLimit) {
          return 'Session limit exceeded: ${sessionUsageMinutes}/${effectiveSession} minutes';
        }
        
        return 'Within limits';
      }
      
      int effectiveDailyLimit = dailyLimit;
      int effectiveSessionLimit = sessionLimit;

      // Apply peak hours penalty (6 PM - 11 PM)
      if (currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END) {
        effectiveDailyLimit = (effectiveDailyLimit * PEAK_HOUR_REDUCTION).round();
        effectiveSessionLimit = (effectiveSessionLimit * PEAK_HOUR_REDUCTION).round();
      }

      final exceedsDailyLimit = dailyUsageMinutes >= effectiveDailyLimit;
      final exceedsSessionLimit = sessionUsageMinutes >= effectiveSessionLimit;

      if (exceedsDailyLimit && exceedsSessionLimit) {
        return 'Both daily (${dailyUsageMinutes}/${effectiveDailyLimit} min) and session (${sessionUsageMinutes}/${effectiveSessionLimit} min) limits exceeded';
      } else if (exceedsDailyLimit) {
        return 'Daily limit exceeded: ${dailyUsageMinutes}/${effectiveDailyLimit} minutes';
      } else if (exceedsSessionLimit) {
        return 'Session limit exceeded: ${sessionUsageMinutes}/${effectiveSessionLimit} minutes';
      }
      
      return 'Within limits';
    } catch (e) {
      print('⚠️ Error getting lock reason: $e');
      // ✅ SAFE FALLBACK: Return generic reason if error occurs
      return 'Usage limit exceeded';
    }
  }

  /// Update threshold for a category (user customization)
  /// ✅ VALIDATION: Rule-based limits cannot exceed safety limits
  static Future<void> updateThreshold({
    required String category,
    int? dailyLimit,
    int? sessionLimit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedCategory = _normalizeCategory(category);
    
    // ✅ VALIDATION: Get current values to validate
    final currentThresholds = await _getThresholds(category);
    final currentDaily = currentThresholds['daily']!;
    final currentSession = currentThresholds['session']!;
    
    // Apply new values (if provided)
    int? newDaily = dailyLimit ?? currentDaily;
    int? newSession = sessionLimit ?? currentSession;
    
    // ✅ VALIDATION: Ensure rule-based doesn't exceed safety (skip for Others category)
    if (normalizedCategory != 'Others') {
      final validated = await _validateThresholds(category, newDaily, newSession);
      newDaily = validated['daily']!;
      newSession = validated['session']!;
    }
    
    // Save validated thresholds
    if (dailyLimit != null) {
      await prefs.setInt('threshold_${normalizedCategory}_daily', newDaily);
    }
    if (sessionLimit != null) {
      await prefs.setInt('threshold_${normalizedCategory}_session', newSession);
    }
    
    print('✅ Thresholds updated for $category: ${newDaily}min daily, ${newSession}min session');
  }

  /// Get current thresholds for a category (including customizations)
  static Future<Map<String, int>> getThresholds(String category) async {
    return await _getThresholds(category);
  }

  /// Reset thresholds to defaults
  static Future<void> resetThresholds(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedCategory = _normalizeCategory(category);
    
    await prefs.remove('threshold_${normalizedCategory}_daily');
    await prefs.remove('threshold_${normalizedCategory}_session');
  }

  /// Get all default thresholds (for settings UI)
  static Map<String, Map<String, int>> getDefaultThresholds() {
    return Map.from(_defaultThresholds);
  }

  /// Check if current time is peak hours
  static bool isPeakHours(int currentHour) {
    return currentHour >= PEAK_HOUR_START && currentHour <= PEAK_HOUR_END;
  }
}

