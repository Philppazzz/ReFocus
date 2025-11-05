/// ✅ LSTM Input Module: Max Session Tracking
/// 
/// This module tracks the continuous session time for each selected app
/// and resets only after 5 minutes of inactivity.
/// It provides a clean interface for LSTM integration and automatically
/// stores data in time-series format for machine learning.
/// 
/// Features:
/// - Tracks continuous session duration (5-minute inactivity rule)
/// - Tracks longest session per app
/// - Stores data in time-series format (ready for LSTM)
/// - Provides real-time and historical access
/// - Integrates with session_logs table

import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/lock_state_manager.dart';

class MaxSessionTracker {
  /// Get current session duration in minutes
  /// Accounts for 5-minute inactivity rule
  static Future<double> getCurrentSessionMinutes() async {
    return await LockStateManager.getCurrentSessionMinutes();
  }

  /// Get longest session duration for today
  static Future<Map<String, dynamic>> getLongestSessionToday() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Get from database
    final stats = await DatabaseHelper.instance.getTodayStats();
    if (stats != null) {
      return {
        'max_session_minutes': (stats['max_session'] as num? ?? 0.0).toDouble(),
        'longest_session_app': stats['longest_session_app'] ?? 'None',
        'date': today,
      };
    }
    
    return {
      'max_session_minutes': 0.0,
      'longest_session_app': 'None',
      'date': today,
    };
  }

  /// Get max session for a specific date
  static Future<double> getMaxSessionForDate(String date) async {
    final stats = await DatabaseHelper.instance.database.then((db) => db.query(
      'usage_stats',
      where: 'date = ?',
      whereArgs: [date],
    ));
    
    if (stats.isNotEmpty) {
      return (stats.first['max_session'] as num? ?? 0.0).toDouble();
    }
    return 0.0;
  }

  /// Get time-series data for LSTM (last N days)
  /// Returns List<Map> with: date, max_session_minutes, longest_session_app
  static Future<List<Map<String, dynamic>>> getTimeSeriesData(int days) async {
    final today = DateTime.now();
    
    final List<Map<String, dynamic>> timeSeries = [];
    
    for (int i = 0; i < days; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      
      final maxSession = await getMaxSessionForDate(dateStr);
      
      // Get longest session app for this date
      final db = DatabaseHelper.instance;
      final stats = await db.database.then((db) => db.query(
        'usage_stats',
        where: 'date = ?',
        whereArgs: [dateStr],
      ));
      
      final longestApp = stats.isNotEmpty 
          ? (stats.first['longest_session_app'] ?? 'None')
          : 'None';
      
      timeSeries.add({
        'date': dateStr,
        'timestamp': date.millisecondsSinceEpoch,
        'max_session_minutes': maxSession,
        'longest_session_app': longestApp,
      });
    }
    
    // Reverse to get chronological order (oldest first)
    return timeSeries.reversed.toList();
  }

  /// Get session logs for LSTM training
  /// Returns all completed sessions with duration and reasons
  static Future<List<Map<String, dynamic>>> getSessionLogs({
    int? limit,
    String? startDate,
    String? endDate,
  }) async {
    var query = DatabaseHelper.instance.database.then((db) => db.query(
      'session_logs',
      where: 'session_end IS NOT NULL',
      orderBy: 'session_start DESC',
      limit: limit,
    ));
    
    if (startDate != null || endDate != null) {
      // Filter by date range if provided
      final logs = await query;
      final filtered = logs.where((log) {
        final start = log['session_start'] as int?;
        if (start == null) return false;
        
        final sessionDate = DateTime.fromMillisecondsSinceEpoch(start);
        final sessionDateStr = sessionDate.toIso8601String().substring(0, 10);
        
        if (startDate != null && sessionDateStr.compareTo(startDate) < 0) return false;
        if (endDate != null && sessionDateStr.compareTo(endDate) > 0) return false;
        
        return true;
      }).toList();
      
      return filtered;
    }
    
    return await query;
  }

  /// Get average session duration for a date range
  static Future<double> getAverageSessionDuration({
    required String startDate,
    required String endDate,
  }) async {
    final logs = await getSessionLogs(startDate: startDate, endDate: endDate);
    
    if (logs.isEmpty) return 0.0;
    
    double totalDuration = 0.0;
    for (var log in logs) {
      totalDuration += (log['duration_minutes'] as num? ?? 0.0).toDouble();
    }
    
    return totalDuration / logs.length;
  }

  /// Log session snapshot for LSTM training
  static Future<void> logSessionSnapshot() async {
    final current = await getCurrentSessionMinutes();
    final longest = await getLongestSessionToday();
    
    // Data is already stored in session_logs and usage_stats tables
    // This method ensures we have a snapshot at this moment
    final stats = await DatabaseHelper.instance.getTodayStats();
    if (stats != null) {
      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': (stats['daily_usage_hours'] as num? ?? 0.0).toDouble(),
        'max_session': longest['max_session_minutes'],
        'longest_session_app': longest['longest_session_app'],
        'most_unlock_app': stats['most_unlock_app'] ?? 'None',
        'most_unlock_count': (stats['most_unlock_count'] as int? ?? 0),
      });
    }
    
    print("📊 Session snapshot logged: Current=${current.toStringAsFixed(1)}m, Max=${longest['max_session_minutes'].toStringAsFixed(1)}m");
  }

  /// Get session statistics for LSTM input preparation
  /// Returns formatted data ready for LSTM model consumption
  static Future<Map<String, dynamic>> getLSTMInputData() async {
    final current = await getCurrentSessionMinutes();
    final longest = await getLongestSessionToday();
    final timeSeries = await getTimeSeriesData(30); // Last 30 days
    final recentLogs = await getSessionLogs(limit: 100);
    
    return {
      'current_session_minutes': current,
      'max_session_minutes': longest['max_session_minutes'],
      'longest_session_app': longest['longest_session_app'],
      'time_series': timeSeries,
      'recent_sessions': recentLogs.take(50).toList(), // Last 50 sessions
      'feature_type': 'max_session',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

