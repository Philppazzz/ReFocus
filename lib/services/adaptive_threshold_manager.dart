import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/app_lock_manager.dart';

/// Adaptive Threshold Manager
/// Automatically adjusts usage limits based on user's actual behavior
/// Helps user maintain progress and prevents app from becoming irrelevant
class AdaptiveThresholdManager {
  // Evaluation window: analyze last N days
  static const int EVALUATION_WINDOW_DAYS = 7;
  
  // Adjustment factors
  static const double IMPROVEMENT_REDUCTION = 0.85; // -15% when improving
  static const double STRUGGLE_INCREASE = 1.15;      // +15% when struggling
  
  // ✅ SHARED LIMITS: Min/Max thresholds (same for all monitored categories)
  // All categories share the same limit pool - user can spend all time in one category
  static const Map<String, Map<String, int>> MIN_THRESHOLDS = {
    'Social': {'daily': 240, 'session': 90},        // Min 4h daily, 1.5h session (SHARED)
    'Games': {'daily': 240, 'session': 90},         // Min 4h daily, 1.5h session (SHARED)
    'Entertainment': {'daily': 240, 'session': 90}, // Min 4h daily, 1.5h session (SHARED)
  };
  
  // ✅ SHARED LIMITS: Maximum thresholds (same for all monitored categories)
  // Set at 20% above default to allow adjustment while staying reasonable
  static const Map<String, Map<String, int>> MAX_THRESHOLDS = {
    'Social': {'daily': 480, 'session': 150},        // Max 8h daily, 2.5h session (SHARED)
    'Games': {'daily': 480, 'session': 150},         // Max 8h daily, 2.5h session (SHARED)
    'Entertainment': {'daily': 480, 'session': 150}, // Max 8h daily, 2.5h session (SHARED)
  };
  
  /// Main evaluation: Call this daily or when user opens app
  static Future<Map<String, dynamic>> evaluateAndAdjust() async {
    try {
      print('🔄 Adaptive Threshold: Starting evaluation...');
      
      final adjustments = <String, Map<String, dynamic>>{};
      final now = DateTime.now();
      final evaluationStart = now.subtract(Duration(days: EVALUATION_WINDOW_DAYS));
      
      // Check if enough time has passed since last adjustment (prevent daily changes)
      final prefs = await SharedPreferences.getInstance();
      final lastAdjustment = prefs.getInt('last_threshold_adjustment');
      if (lastAdjustment != null) {
        final daysSinceAdjustment = now.difference(
          DateTime.fromMillisecondsSinceEpoch(lastAdjustment)
        ).inDays;
        
        if (daysSinceAdjustment < 7) {
          print('⏳ Adaptive Threshold: Too soon (${daysSinceAdjustment}d < 7d)');
          return {'adjusted': false, 'reason': 'Too soon since last adjustment'};
        }
      }
      
      // Evaluate each monitored category
      for (final category in ['Social', 'Entertainment', 'Games']) {
        final result = await _evaluateCategory(category, evaluationStart);
        if (result['adjusted'] == true) {
          adjustments[category] = result;
        }
      }
      
      // Save adjustment timestamp
      if (adjustments.isNotEmpty) {
        await prefs.setInt('last_threshold_adjustment', now.millisecondsSinceEpoch);
      }
      
      print('✅ Adaptive Threshold: Evaluation complete (${adjustments.length} adjustments)');
      
      return {
        'success': true,
        'adjusted': adjustments.isNotEmpty,
        'adjustments': adjustments,
        'evaluation_date': now.toIso8601String(),
      };
      
    } catch (e) {
      print('⚠️ Error in adaptive threshold evaluation: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// Evaluate single category
  static Future<Map<String, dynamic>> _evaluateCategory(
    String category,
    DateTime evaluationStart,
  ) async {
    try {
      // Get current thresholds
      final currentThresholds = await AppLockManager.getThresholds(category);
      final currentDaily = currentThresholds['daily']!;
      final currentSession = currentThresholds['session']!;
      
      // Calculate average daily usage in evaluation window
      final usageData = await _getAverageDailyUsage(category, evaluationStart);
      final avgDailyUsage = usageData['average'] as double;
      final daysWithData = usageData['days'] as int;
      
      // Need at least 5 days of data
      if (daysWithData < 5) {
        print('📊 $category: Not enough data ($daysWithData days)');
        return {'adjusted': false, 'reason': 'Insufficient data'};
      }
      
      // Get feedback satisfaction rate
      final satisfactionRate = await _getSatisfactionRate(category, evaluationStart);
      
      // Calculate usage percentage
      final usagePercentage = avgDailyUsage / currentDaily;
      
      print('📊 $category: avg=${avgDailyUsage.toInt()}min, limit=${currentDaily}min, usage=${(usagePercentage*100).toInt()}%, satisfaction=${(satisfactionRate*100).toInt()}%');
      
      // Decision logic
      if (_shouldReduceThreshold(usagePercentage, satisfactionRate)) {
        return await _reduceThreshold(category, currentDaily, currentSession, avgDailyUsage);
      } else if (_shouldIncreaseThreshold(usagePercentage, satisfactionRate)) {
        return await _increaseThreshold(category, currentDaily, currentSession);
      }
      
      return {'adjusted': false, 'reason': 'No adjustment needed'};
      
    } catch (e) {
      print('⚠️ Error evaluating $category: $e');
      return {'adjusted': false, 'error': e.toString()};
    }
  }
  
  /// Check if threshold should be reduced (user improving)
  static bool _shouldReduceThreshold(double usagePercentage, double satisfactionRate) {
    // Reduce if:
    // - Using < 70% of limit consistently
    // - AND satisfaction rate > 75%
    return usagePercentage < 0.70 && satisfactionRate > 0.75;
  }
  
  /// Check if threshold should be increased (user struggling)
  static bool _shouldIncreaseThreshold(double usagePercentage, double satisfactionRate) {
    // Increase if:
    // - Using > 95% of limit consistently
    // - AND low satisfaction rate (< 50% - many "not helpful" feedbacks)
    return usagePercentage > 0.95 && satisfactionRate < 0.50;
  }
  
  /// Reduce threshold (user is improving!)
  static Future<Map<String, dynamic>> _reduceThreshold(
    String category,
    int currentDaily,
    int currentSession,
    double avgUsage,
  ) async {
    // Target: Set limit slightly above average usage (10% buffer)
    final targetDaily = (avgUsage * 1.10).round();
    
    // Apply reduction factor and clamp to min/max
    final newDaily = targetDaily.clamp(
      MIN_THRESHOLDS[category]!['daily']!,
      currentDaily, // Don't increase when reducing
    );
    
    final newSession = (currentSession * IMPROVEMENT_REDUCTION).round().clamp(
      MIN_THRESHOLDS[category]!['session']!,
      currentSession,
    );
    
    // Only apply if change is significant (at least 10 minutes difference)
    if (currentDaily - newDaily < 10) {
      print('📊 $category: Change too small (<10 min)');
      return {'adjusted': false, 'reason': 'Change too small'};
    }
    
    // Apply new thresholds
    await AppLockManager.updateThreshold(
      category: category,
      dailyLimit: newDaily,
      sessionLimit: newSession,
    );
    
    print('✅ $category: REDUCED daily ${currentDaily}→${newDaily}min, session ${currentSession}→${newSession}min');
    
    return {
      'adjusted': true,
      'direction': 'reduced',
      'old_daily': currentDaily,
      'new_daily': newDaily,
      'old_session': currentSession,
      'new_session': newSession,
      'reason': 'User showing consistent improvement',
    };
  }
  
  /// Increase threshold (user is struggling)
  static Future<Map<String, dynamic>> _increaseThreshold(
    String category,
    int currentDaily,
    int currentSession,
  ) async {
    // Increase by 15%
    final newDaily = (currentDaily * STRUGGLE_INCREASE).round().clamp(
      currentDaily, // Don't decrease when increasing
      MAX_THRESHOLDS[category]!['daily']!,
    );
    
    final newSession = (currentSession * STRUGGLE_INCREASE).round().clamp(
      currentSession,
      MAX_THRESHOLDS[category]!['session']!,
    );
    
    // Apply new thresholds
    await AppLockManager.updateThreshold(
      category: category,
      dailyLimit: newDaily,
      sessionLimit: newSession,
    );
    
    print('⚠️ $category: INCREASED daily ${currentDaily}→${newDaily}min, session ${currentSession}→${newSession}min');
    
    return {
      'adjusted': true,
      'direction': 'increased',
      'old_daily': currentDaily,
      'new_daily': newDaily,
      'old_session': currentSession,
      'new_session': newSession,
      'reason': 'User struggling with current limits',
    };
  }
  
  /// Get average daily usage for category
  static Future<Map<String, dynamic>> _getAverageDailyUsage(
    String category,
    DateTime since,
  ) async {
    try {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      
      double totalUsage = 0;
      int daysWithData = 0;
      
      for (int i = 0; i < EVALUATION_WINDOW_DAYS; i++) {
        final date = now.subtract(Duration(days: i));
        final usageMap = await db.getCategoryUsageForDate(date);
        final usage = usageMap[category] ?? 0.0;
        
        if (usage > 0) {
          totalUsage += usage;
          daysWithData++;
        }
      }
      
      final average = daysWithData > 0 ? totalUsage / daysWithData : 0.0;
      
      return {
        'average': average,
        'total': totalUsage,
        'days': daysWithData,
      };
    } catch (e) {
      print('⚠️ Error getting average usage: $e');
      return {'average': 0.0, 'total': 0.0, 'days': 0};
    }
  }
  
  /// Get satisfaction rate from feedback
  static Future<double> _getSatisfactionRate(
    String category,
    DateTime since,
  ) async {
    try {
      final feedback = await FeedbackLogger.getFeedbackSince(since, category);
      
      if (feedback.isEmpty) {
        return 0.80; // Default neutral satisfaction if no feedback
      }
      
      final helpfulCount = feedback.where((f) => f['was_helpful'] == 1).length;
      return helpfulCount / feedback.length;
      
    } catch (e) {
      print('⚠️ Error getting satisfaction rate: $e');
      return 0.80; // Default neutral
    }
  }
  
  /// Get readable report for UI
  static Future<String> getAdaptiveReport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAdjustmentTime = prefs.getInt('last_threshold_adjustment');
      
      if (lastAdjustmentTime == null) {
        return 'No adaptive adjustments yet. Continue using the app!';
      }
      
      final lastAdjustment = DateTime.fromMillisecondsSinceEpoch(lastAdjustmentTime);
      final daysAgo = DateTime.now().difference(lastAdjustment).inDays;
      
      String report = 'Last adjustment: $daysAgo days ago\n';
      report += 'Next evaluation: ${7 - daysAgo} days\n\n';
      report += 'The app adapts your limits based on your actual behavior!';
      
      return report;
    } catch (e) {
      return 'Error getting adaptive report';
    }
  }
  
  /// Get detailed statistics for each category
  static Future<Map<String, dynamic>> getAdaptiveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAdjustmentTime = prefs.getInt('last_threshold_adjustment');
      final now = DateTime.now();
      final evaluationStart = now.subtract(Duration(days: EVALUATION_WINDOW_DAYS));
      
      final stats = <String, dynamic>{};
      
      for (final category in ['Social', 'Entertainment', 'Games']) {
        final thresholds = await AppLockManager.getThresholds(category);
        final usageData = await _getAverageDailyUsage(category, evaluationStart);
        final satisfactionRate = await _getSatisfactionRate(category, evaluationStart);
        
        stats[category] = {
          'current_daily_limit': thresholds['daily'],
          'current_session_limit': thresholds['session'],
          'avg_daily_usage': (usageData['average'] as double).round(),
          'days_with_data': usageData['days'],
          'satisfaction_rate': (satisfactionRate * 100).round(),
          'usage_percentage': thresholds['daily']! > 0 
              ? ((usageData['average'] as double) / thresholds['daily']! * 100).round() 
              : 0,
        };
      }
      
      return {
        'success': true,
        'last_adjustment': lastAdjustmentTime != null 
            ? DateTime.fromMillisecondsSinceEpoch(lastAdjustmentTime).toIso8601String()
            : null,
        'days_since_adjustment': lastAdjustmentTime != null
            ? now.difference(DateTime.fromMillisecondsSinceEpoch(lastAdjustmentTime)).inDays
            : null,
        'next_evaluation_days': lastAdjustmentTime != null
            ? (7 - now.difference(DateTime.fromMillisecondsSinceEpoch(lastAdjustmentTime)).inDays).clamp(0, 7)
            : 7,
        'categories': stats,
      };
    } catch (e) {
      print('⚠️ Error getting adaptive stats: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}

