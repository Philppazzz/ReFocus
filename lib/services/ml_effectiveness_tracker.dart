import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';

/// Tracks ML model effectiveness for thesis validation
/// Compares user behavior before and after ML activation
class MLEffectivenessTracker {
  static const String KEY_ML_ACTIVATED_DATE = 'ml_activated_date';
  static const String KEY_BASELINE_WEEKLY_USAGE = 'baseline_weekly_usage';
  static const String KEY_BASELINE_LOCK_COUNT = 'baseline_lock_count';
  static const String KEY_POST_ML_WEEKLY_USAGE = 'post_ml_weekly_usage';
  static const String KEY_POST_ML_LOCK_COUNT = 'post_ml_lock_count';

  /// Call this when ML model becomes ready
  static Future<void> onMLActivated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if already activated (don't re-activate)
      if (prefs.containsKey(KEY_ML_ACTIVATED_DATE)) {
        print('⚠️ ML Effectiveness Tracking already started, skipping');
        return;
      }
      
      // Record activation date
      await prefs.setInt(KEY_ML_ACTIVATED_DATE, DateTime.now().millisecondsSinceEpoch);
      
      // Calculate baseline (usage before ML activation)
      final baselineUsage = await _calculateWeeklyUsage(daysBack: 7);
      await prefs.setDouble(KEY_BASELINE_WEEKLY_USAGE, baselineUsage);
      
      final baselineLocks = await _calculateLockCount(daysBack: 7);
      await prefs.setInt(KEY_BASELINE_LOCK_COUNT, baselineLocks);
      
      print('✅ ML Effectiveness Tracking Started:');
      print('   Baseline weekly usage: ${baselineUsage.toStringAsFixed(1)} hours');
      print('   Baseline weekly locks: $baselineLocks');
    } catch (e) {
      print('⚠️ Error starting ML effectiveness tracking: $e');
      // Don't throw - this is non-critical
    }
  }

  /// Get ML effectiveness report (for thesis data)
  static Future<Map<String, dynamic>> getEffectivenessReport() async {
    final prefs = await SharedPreferences.getInstance();
    
    final mlActivatedTimestamp = prefs.getInt(KEY_ML_ACTIVATED_DATE);
    if (mlActivatedTimestamp == null) {
      return {
        'ml_activated': false,
        'message': 'ML model not yet activated',
      };
    }
    
    final mlActivatedDate = DateTime.fromMillisecondsSinceEpoch(mlActivatedTimestamp);
    final daysSinceActivation = DateTime.now().difference(mlActivatedDate).inDays;
    
    if (daysSinceActivation < 7) {
      return {
        'ml_activated': true,
        'days_since_activation': daysSinceActivation,
        'message': 'Need at least 7 days of ML usage for comparison',
      };
    }
    
    // Get baseline (before ML)
    final baselineUsage = prefs.getDouble(KEY_BASELINE_WEEKLY_USAGE) ?? 0.0;
    final baselineLocks = prefs.getInt(KEY_BASELINE_LOCK_COUNT) ?? 0;
    
    // Calculate current (after ML)
    final currentUsage = await _calculateWeeklyUsage(daysBack: 7);
    final currentLocks = await _calculateLockCount(daysBack: 7);
    
    // Calculate improvements
    final usageReduction = baselineUsage - currentUsage;
    final usageReductionPercent = baselineUsage > 0 
        ? (usageReduction / baselineUsage * 100) 
        : 0.0;
    
    final lockReduction = baselineLocks - currentLocks;
    final lockReductionPercent = baselineLocks > 0
        ? (lockReduction / baselineLocks * 100)
        : 0.0;
    
    return {
      'ml_activated': true,
      'days_since_activation': daysSinceActivation,
      'baseline_weekly_usage_hours': baselineUsage,
      'current_weekly_usage_hours': currentUsage,
      'usage_reduction_hours': usageReduction,
      'usage_reduction_percent': usageReductionPercent,
      'baseline_weekly_locks': baselineLocks,
      'current_weekly_locks': currentLocks,
      'lock_reduction_count': lockReduction,
      'lock_reduction_percent': lockReductionPercent,
      'is_effective': usageReduction > 0 || lockReduction > 0,
      'effectiveness_rating': _calculateEffectivenessRating(
        usageReductionPercent, 
        lockReductionPercent,
      ),
    };
  }

  /// Calculate weekly usage in hours
  static Future<double> _calculateWeeklyUsage({required int daysBack}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: daysBack));
      
      final startKey = _dateKey(startDate);
      final endKey = _dateKey(endDate);
      
      final result = await db.rawQuery('''
        SELECT SUM(usage_seconds) as total_seconds
        FROM app_details
        WHERE date >= ? AND date <= ?
      ''', [startKey, endKey]);
      
      if (result.isEmpty || result[0]['total_seconds'] == null) {
        return 0.0;
      }
      
      final totalSeconds = (result[0]['total_seconds'] as num?)?.toDouble() ?? 0.0;
      return totalSeconds / 3600.0; // Convert to hours
    } catch (e) {
      print('⚠️ Error calculating weekly usage: $e');
      return 0.0;
    }
  }

  /// Calculate lock count
  static Future<int> _calculateLockCount({required int daysBack}) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final endTimestamp = DateTime.now().millisecondsSinceEpoch;
      final startTimestamp = endTimestamp - (daysBack * 24 * 60 * 60 * 1000);
      
      final result = await db.rawQuery('''
        SELECT COUNT(*) as lock_count
        FROM lock_history
        WHERE timestamp >= ? AND timestamp <= ?
      ''', [startTimestamp, endTimestamp]);
      
      if (result.isEmpty) return 0;
      
      return (result[0]['lock_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      print('⚠️ Error calculating lock count: $e');
      return 0;
    }
  }

  /// Calculate effectiveness rating (0-100)
  static int _calculateEffectivenessRating(
    double usageReductionPercent,
    double lockReductionPercent,
  ) {
    // Weighted average: 70% usage reduction, 30% lock reduction
    final rating = (usageReductionPercent * 0.7) + (lockReductionPercent * 0.3);
    return rating.clamp(0, 100).round();
  }

  /// Get formatted date key
  static String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// Export data for thesis (CSV format)
  static Future<String> exportForThesis() async {
    final report = await getEffectivenessReport();
    
    if (!(report['ml_activated'] as bool)) {
      return 'ML not activated yet';
    }
    
    // CSV format for easy analysis
    final csv = StringBuffer();
    csv.writeln('Metric,Value');
    csv.writeln('Days Since ML Activation,${report['days_since_activation']}');
    csv.writeln('Baseline Weekly Usage (hours),${(report['baseline_weekly_usage_hours'] as double).toStringAsFixed(2)}');
    csv.writeln('Current Weekly Usage (hours),${(report['current_weekly_usage_hours'] as double).toStringAsFixed(2)}');
    csv.writeln('Usage Reduction (hours),${(report['usage_reduction_hours'] as double).toStringAsFixed(2)}');
    csv.writeln('Usage Reduction (%),${(report['usage_reduction_percent'] as double).toStringAsFixed(1)}');
    csv.writeln('Baseline Weekly Locks,${report['baseline_weekly_locks']}');
    csv.writeln('Current Weekly Locks,${report['current_weekly_locks']}');
    csv.writeln('Lock Reduction,${report['lock_reduction_count']}');
    csv.writeln('Lock Reduction (%),${(report['lock_reduction_percent'] as double).toStringAsFixed(1)}');
    csv.writeln('Effectiveness Rating (0-100),${report['effectiveness_rating']}');
    csv.writeln('Is Effective,${report['is_effective']}');
    
    return csv.toString();
  }
}

