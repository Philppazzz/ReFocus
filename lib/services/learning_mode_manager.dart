import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/feedback_logger.dart';

/// Manages learning mode vs rule-based mode preferences
/// Learning mode: No locks, just monitoring + feedback (unbiased data collection)
/// Rule-based mode: Traditional locks from Day 1 (user protection)
class LearningModeManager {
  static const String KEY_LEARNING_MODE_ENABLED = 'learning_mode_enabled';
  static const String KEY_RULE_BASED_ENABLED = 'rule_based_enabled';
  static const String KEY_LEARNING_START_DATE = 'learning_start_date';
  
  // Learning phase thresholds
  static const int LEARNING_PHASE_DAYS = 7;   // Pure learning (no locks) - 1 week
  static const int SOFT_PHASE_DAYS = 14;       // Soft warnings - 2 weeks
  static const int MIN_FEEDBACK_FOR_ML = 300;  // ML activation threshold (optimized from 500)
  static const int MIN_DAYS_FOR_ML = 5;        // Minimum days for ML (ensures time diversity)
  
  // Diversity requirements for ML readiness
  static const int MIN_DIFFERENT_DAYS = 3;           // Feedback from 3+ different days
  static const int MIN_DIFFERENT_TIME_PERIODS = 2;  // Morning/Afternoon/Evening (at least 2)
  static const int MIN_DIFFERENT_CATEGORIES = 2;     // At least 2 categories
  static const double MIN_HELPFULNESS_RATE = 0.10;  // At least 10% helpful (quality check)

  /// Check if learning mode is enabled (default: true)
  /// ✅ CRITICAL: Handles SharedPreferences corruption gracefully
  static Future<bool> isLearningModeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to learning mode (true) if not set
      return prefs.getBool(KEY_LEARNING_MODE_ENABLED) ?? true;
    } catch (e) {
      // ✅ CRITICAL: If SharedPreferences is corrupted, default to learning mode
      print('⚠️ Error reading learning mode preference: $e - defaulting to learning mode');
      return true;
    }
  }

  /// Check if rule-based mode is enabled (default: false)
  /// ✅ CRITICAL: Handles SharedPreferences corruption gracefully
  static Future<bool> isRuleBasedEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(KEY_RULE_BASED_ENABLED) ?? false;
    } catch (e) {
      // ✅ CRITICAL: If SharedPreferences is corrupted, default to false (learning mode)
      print('⚠️ Error reading rule-based mode preference: $e - defaulting to learning mode');
      return false;
    }
  }

  /// Enable or disable learning mode
  static Future<void> setLearningModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KEY_LEARNING_MODE_ENABLED, enabled);
    
    if (enabled) {
      // Record learning start date
      await prefs.setInt(KEY_LEARNING_START_DATE, DateTime.now().millisecondsSinceEpoch);
      print('✅ Learning mode enabled - collecting unbiased data');
    } else {
      print('✅ Learning mode disabled - using rule-based locks');
    }
  }

  /// Enable or disable rule-based mode
  static Future<void> setRuleBasedEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KEY_RULE_BASED_ENABLED, enabled);
    
    if (enabled) {
      print('✅ Rule-based mode enabled - locks active from Day 1');
    } else {
      print('✅ Rule-based mode disabled - using learning mode');
    }
  }

  /// Get learning phase (pure learning, soft learning, or ML ready)
  /// ✅ OPTIMIZED: ML ready when 300+ samples reached (no day requirement)
  static Future<String> getLearningPhase() async {
    final learningEnabled = await isLearningModeEnabled();
    if (!learningEnabled) {
      return 'rule_based';  // User chose rule-based mode
    }

    final startDate = await getLearningStartDate();
    if (startDate == null) {
      return 'learning';  // Just started
    }

    final daysSinceStart = DateTime.now().difference(startDate).inDays;
    final feedbackCount = await _getFeedbackCount();
    
    // ✅ ML READY CHECK: 300+ samples is sufficient (no day requirement)
    // Data diversity is still checked to ensure quality
    if (feedbackCount >= MIN_FEEDBACK_FOR_ML) {
      // Check data diversity (ensures quality, not just quantity)
      final hasDiversity = await _checkDataDiversity();
      if (hasDiversity) {
        return 'ml_ready';  // ML activated when 300+ samples + diversity met!
      }
    }
    
    // Phase based on days (for UI display)
    if (daysSinceStart < LEARNING_PHASE_DAYS) {
      return 'pure_learning';  // Day 1-7: No locks
    } else if (daysSinceStart < SOFT_PHASE_DAYS) {
      return 'soft_learning';  // Day 7-14: Soft warnings
    } else {
      return 'soft_learning';  // Day 14+: Still collecting data (until ML ready)
    }
  }

  /// Get learning start date
  static Future<DateTime?> getLearningStartDate() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(KEY_LEARNING_START_DATE);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Get days since learning started
  static Future<int> getDaysSinceLearningStart() async {
    final startDate = await getLearningStartDate();
    if (startDate == null) return 0;
    return DateTime.now().difference(startDate).inDays;
  }

  /// Check if we should show proactive feedback prompts
  static Future<bool> shouldShowProactiveFeedback() async {
    final learningEnabled = await isLearningModeEnabled();
    if (!learningEnabled) return false;  // Only in learning mode
    
    final phase = await getLearningPhase();
    return phase == 'pure_learning' || phase == 'soft_learning';
  }

  /// Get current mode description
  static Future<Map<String, dynamic>> getModeInfo() async {
    final learningEnabled = await isLearningModeEnabled();
    final ruleBasedEnabled = await isRuleBasedEnabled();
    final phase = await getLearningPhase();
    final daysSinceStart = await getDaysSinceLearningStart();
    final feedbackCount = await _getFeedbackCount();

    return {
      'learning_mode_enabled': learningEnabled,
      'rule_based_enabled': ruleBasedEnabled,
      'phase': phase,
      'days_since_start': daysSinceStart,
      'feedback_count': feedbackCount,
      'min_feedback_needed': MIN_FEEDBACK_FOR_ML,
      'progress_percentage': (feedbackCount / MIN_FEEDBACK_FOR_ML * 100).clamp(0.0, 100.0),
    };
  }

  static Future<int> _getFeedbackCount() async {
    try {
      final stats = await FeedbackLogger.getStats();
      return stats['total_feedback'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Check if feedback data has sufficient diversity for ML training
  /// Ensures data quality by checking:
  /// - Different days (time diversity)
  /// - Different time periods (morning/afternoon/evening)
  /// - Different categories (Social, Games, Entertainment)
  /// - Quality feedback (helpfulness rate)
  static Future<bool> _checkDataDiversity() async {
    try {
      // Get all feedback data
      final feedbackData = await FeedbackLogger.exportFeedbackForTraining();
      
      // Need at least minimum feedback count
      if (feedbackData.length < MIN_FEEDBACK_FOR_ML) {
        return false;
      }
      
      // Check different days (time diversity)
      final uniqueDays = feedbackData
          .map((f) {
            try {
              final timestamp = f['timestamp'] as int?;
              if (timestamp == null) return null;
              return DateTime.fromMillisecondsSinceEpoch(timestamp)
                  .toIso8601String().substring(0, 10); // YYYY-MM-DD
            } catch (e) {
              return null;
            }
          })
          .where((day) => day != null)
          .toSet();
      
      if (uniqueDays.length < MIN_DIFFERENT_DAYS) {
        return false; // Not enough different days
      }
      
      // Check different time periods (morning 6-12, afternoon 12-18, evening 18-24, night 0-6)
      final timePeriods = feedbackData
          .map((f) {
            try {
              final hour = f['time_of_day'] as int? ?? 12;
              if (hour >= 6 && hour < 12) return 'morning';
              if (hour >= 12 && hour < 18) return 'afternoon';
              if (hour >= 18 && hour < 24) return 'evening';
              return 'night';
            } catch (e) {
              return 'unknown';
            }
          })
          .where((period) => period != 'unknown')
          .toSet();
      
      if (timePeriods.length < MIN_DIFFERENT_TIME_PERIODS) {
        return false; // Not enough different time periods
      }
      
      // Check different categories
      final categories = feedbackData
          .map((f) {
            try {
              final category = f['category'] as String? ?? 'Others';
              // Only count monitored categories
              if (category == 'Social' || category == 'Games' || category == 'Entertainment') {
                return category;
              }
              return null;
            } catch (e) {
              return null;
            }
          })
          .where((cat) => cat != null)
          .toSet();
      
      if (categories.length < MIN_DIFFERENT_CATEGORIES) {
        return false; // Not enough different categories
      }
      
      // Check helpfulness rate (quality check)
      final stats = await FeedbackLogger.getStats();
      final helpfulnessRate = (stats['helpfulness_rate'] as num?)?.toDouble() ?? 0.0;
      
      if (helpfulnessRate < MIN_HELPFULNESS_RATE * 100) {
        return false; // Helpfulness rate too low (might be all negative feedback)
      }
      
      // All diversity checks passed!
      return true;
    } catch (e) {
      // If diversity check fails, return false (safer to wait)
      return false;
    }
  }
}

