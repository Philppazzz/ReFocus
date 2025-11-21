import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/feedback_logger.dart';

/// Service to prevent abuse of feedback unlock system
/// Implements rate limiting, progressive penalties, and abuse detection
class FeedbackAbusePrevention {
  // Maximum unlocks allowed per day
  static const int MAX_UNLOCKS_PER_DAY = 5;
  
  // Minimum cooldown after unlock (in seconds)
  static const int MIN_UNLOCK_COOLDOWN_SECONDS = 30;
  
  // Abuse threshold: if override rate > 80%, disable unlock option
  static const double ABUSE_OVERRIDE_RATE_THRESHOLD = 0.8; // 80%
  
  // Minimum feedback samples needed to calculate override rate
  static const int MIN_FEEDBACK_FOR_ABUSE_CHECK = 10;

  /// Check if user can unlock (not abusing the system)
  /// Returns: {canUnlock: bool, reason: String?, remainingUnlocks: int}
  static Future<Map<String, dynamic>> canUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Get today's unlock count
    final unlockCountKey = 'feedback_unlocks_$today';
    final todayUnlocks = prefs.getInt(unlockCountKey) ?? 0;
    
    // Check rate limit
    if (todayUnlocks >= MAX_UNLOCKS_PER_DAY) {
      return {
        'canUnlock': false,
        'reason': 'Daily unlock limit reached ($MAX_UNLOCKS_PER_DAY unlocks/day). Please wait until tomorrow.',
        'remainingUnlocks': 0,
        'abuseDetected': false,
      };
    }
    
    // Check minimum cooldown
    final lastUnlockTimeKey = 'last_unlock_time_$today';
    final lastUnlockTime = prefs.getInt(lastUnlockTimeKey);
    if (lastUnlockTime != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceUnlock = (now - lastUnlockTime) / 1000; // seconds
      
      if (timeSinceUnlock < MIN_UNLOCK_COOLDOWN_SECONDS) {
        final remaining = (MIN_UNLOCK_COOLDOWN_SECONDS - timeSinceUnlock).ceil();
        return {
          'canUnlock': false,
          'reason': 'Please wait $remaining seconds before unlocking again.',
          'remainingUnlocks': MAX_UNLOCKS_PER_DAY - todayUnlocks,
          'abuseDetected': false,
        };
      }
    }
    
    // Check abuse pattern (override rate)
    final feedbackStats = await FeedbackLogger.getStats();
    final totalFeedback = feedbackStats['total_feedback'] as int;
    
    if (totalFeedback >= MIN_FEEDBACK_FOR_ABUSE_CHECK) {
      final overrideRate = feedbackStats['override_rate'] as double;
      
      if (overrideRate >= ABUSE_OVERRIDE_RATE_THRESHOLD * 100) {
        return {
          'canUnlock': false,
          'reason': 'Unlock option temporarily disabled due to high override rate (${overrideRate.toStringAsFixed(1)}%). Please use the app within limits.',
          'remainingUnlocks': MAX_UNLOCKS_PER_DAY - todayUnlocks,
          'abuseDetected': true,
        };
      }
    }
    
    // All checks passed
    return {
      'canUnlock': true,
      'reason': null,
      'remainingUnlocks': MAX_UNLOCKS_PER_DAY - todayUnlocks,
      'abuseDetected': false,
    };
  }

  /// Record an unlock event (call when user unlocks)
  static Future<void> recordUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final unlockCountKey = 'feedback_unlocks_$today';
    final todayUnlocks = (prefs.getInt(unlockCountKey) ?? 0) + 1;
    await prefs.setInt(unlockCountKey, todayUnlocks);
    
    final lastUnlockTimeKey = 'last_unlock_time_$today';
    await prefs.setInt(lastUnlockTimeKey, DateTime.now().millisecondsSinceEpoch);
    
    print('🔓 Unlock recorded: $todayUnlocks/$MAX_UNLOCKS_PER_DAY today');
  }

  /// Get today's unlock statistics
  static Future<Map<String, dynamic>> getTodayStats() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final unlockCountKey = 'feedback_unlocks_$today';
    final todayUnlocks = prefs.getInt(unlockCountKey) ?? 0;
    
    final lastUnlockTimeKey = 'last_unlock_time_$today';
    final lastUnlockTime = prefs.getInt(lastUnlockTimeKey);
    
    final feedbackStats = await FeedbackLogger.getStats();
    
    return {
      'today_unlocks': todayUnlocks,
      'max_unlocks': MAX_UNLOCKS_PER_DAY,
      'remaining_unlocks': MAX_UNLOCKS_PER_DAY - todayUnlocks,
      'last_unlock_time': lastUnlockTime,
      'override_rate': feedbackStats['override_rate'] as double,
      'total_feedback': feedbackStats['total_feedback'] as int,
    };
  }

  /// Reset daily unlock count (called at midnight or app start)
  static Future<void> resetDailyUnlocks() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Clean up old unlock counts (keep only today)
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('feedback_unlocks_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
      if (key.startsWith('last_unlock_time_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
    }
  }

  /// Get progressive penalty multiplier based on unlock count
  /// More unlocks = longer cooldown
  static int getProgressiveCooldownMultiplier(int unlockCount) {
    if (unlockCount <= 1) return 1; // 1x (30 seconds)
    if (unlockCount <= 2) return 2; // 2x (60 seconds)
    if (unlockCount <= 3) return 3; // 3x (90 seconds)
    if (unlockCount <= 4) return 4; // 4x (120 seconds)
    return 5; // 5x (150 seconds) for 5+ unlocks
  }

  /// Get effective cooldown after unlock (with progressive penalty)
  static Future<int> getEffectiveCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final unlockCountKey = 'feedback_unlocks_$today';
    final todayUnlocks = prefs.getInt(unlockCountKey) ?? 0;
    
    final multiplier = getProgressiveCooldownMultiplier(todayUnlocks);
    return MIN_UNLOCK_COOLDOWN_SECONDS * multiplier;
  }
}

