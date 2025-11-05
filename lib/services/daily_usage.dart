/// ✅ LSTM Input Module: Daily Usage Tracking
/// 
/// This module tracks the total daily usage duration of all selected apps.
/// It provides a clean interface for LSTM integration and automatically
/// stores data in time-series format for machine learning.
/// 
/// Features:
/// - Tracks total daily usage across all selected apps
/// - Stores data in time-series format (ready for LSTM)
/// - Provides real-time and historical access
/// - Automatically resets at midnight

import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/selected_apps.dart';

class DailyUsageTracker {
  /// Get current daily usage in hours (for selected apps only)
  static Future<double> getCurrentDailyUsage() async {
    // Get from database (most accurate)
    final stats = await DatabaseHelper.instance.getTodayStats();
    if (stats != null) {
      return (stats['daily_usage_hours'] as num? ?? 0.0).toDouble();
    }
    
    return 0.0;
  }

  /// Get daily usage for a specific date
  static Future<double> getDailyUsageForDate(String date) async {
    final stats = await DatabaseHelper.instance.database.then((db) => db.query(
      'usage_stats',
      where: 'date = ?',
      whereArgs: [date],
    ));
    
    if (stats.isNotEmpty) {
      return (stats.first['daily_usage_hours'] as num? ?? 0.0).toDouble();
    }
    return 0.0;
  }

  /// Get time-series data for LSTM (last N days)
  /// Returns List<Map> with: date, daily_usage_hours
  static Future<List<Map<String, dynamic>>> getTimeSeriesData(int days) async {
    final today = DateTime.now();
    
    final List<Map<String, dynamic>> timeSeries = [];
    
    for (int i = 0; i < days; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      
      final usage = await getDailyUsageForDate(dateStr);
      
      timeSeries.add({
        'date': dateStr,
        'timestamp': date.millisecondsSinceEpoch,
        'daily_usage_hours': usage,
      });
    }
    
    // Reverse to get chronological order (oldest first)
    return timeSeries.reversed.toList();
  }

  /// Get current usage with breakdown by app
  /// Returns Map with: total_hours, apps: {package: hours}
  static Future<Map<String, dynamic>> getDetailedUsage() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final appDetails = await DatabaseHelper.instance.getTodayAppDetails();
    
    // Get selected apps
    await SelectedAppsManager.loadFromPrefs();
    final selectedPackages = SelectedAppsManager.selectedApps
        .map((a) => a['package'])
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    
    double totalHours = 0.0;
    final Map<String, double> appUsage = {};
    
    for (var app in appDetails) {
      final pkg = app['package_name'] as String? ?? '';
      if (selectedPackages.contains(pkg)) {
        final seconds = (app['usage_seconds'] as num? ?? 0.0).toDouble();
        final hours = seconds / 3600.0;
        totalHours += hours;
        appUsage[pkg] = hours;
      }
    }
    
    return {
      'total_hours': totalHours,
      'apps': appUsage,
      'date': today,
    };
  }

  /// Log daily usage snapshot for LSTM training
  /// This creates a time-series entry that can be used for model training
  static Future<void> logUsageSnapshot() async {
    final usage = await getCurrentDailyUsage();
    
    // Data is already stored in usage_stats table
    // This method ensures we have a snapshot at this moment
    final stats = await DatabaseHelper.instance.getTodayStats();
    await DatabaseHelper.instance.saveUsageStats({
      'daily_usage_hours': usage,
      'max_session': (stats?['max_session'] as num? ?? 0.0).toDouble(),
      'longest_session_app': stats?['longest_session_app'] ?? 'None',
      'most_unlock_app': stats?['most_unlock_app'] ?? 'None',
      'most_unlock_count': (stats?['most_unlock_count'] as int? ?? 0),
    });
    
    print("📊 Daily usage snapshot logged: ${usage.toStringAsFixed(2)}h");
  }

  /// Get usage statistics for LSTM input preparation
  /// Returns formatted data ready for LSTM model consumption
  static Future<Map<String, dynamic>> getLSTMInputData() async {
    final current = await getCurrentDailyUsage();
    final timeSeries = await getTimeSeriesData(30); // Last 30 days
    
    return {
      'current_usage_hours': current,
      'time_series': timeSeries,
      'feature_type': 'daily_usage',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

