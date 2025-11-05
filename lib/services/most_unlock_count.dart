/// ✅ LSTM Input Module: Most Unlock Count Tracking
/// 
/// This module tracks the total unlocks and identifies the most frequently unlocked app.
/// It provides a clean interface for LSTM integration and automatically
/// stores data in time-series format for machine learning.
/// 
/// Features:
/// - Tracks unlock counts for all apps
/// - Identifies most unlocked app
/// - Stores data in time-series format (ready for LSTM)
/// - Provides real-time and historical access

import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/selected_apps.dart';

class MostUnlockCountTracker {
  /// Get current most unlocked app and its count (for selected apps only)
  static Future<Map<String, dynamic>> getCurrentMostUnlocked() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final appDetails = await DatabaseHelper.instance.getTodayAppDetails();
    
    // Get selected apps
    await SelectedAppsManager.loadFromPrefs();
    final selectedPackages = SelectedAppsManager.selectedApps
        .map((a) => a['package'])
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    
    String mostUnlockedApp = 'None';
    int maxUnlocks = 0;
    final Map<String, int> allUnlocks = {};
    
    for (var app in appDetails) {
      final pkg = app['package_name'] as String? ?? '';
      if (selectedPackages.contains(pkg)) {
        final unlocks = (app['unlock_count'] as int? ?? 0);
        allUnlocks[pkg] = unlocks;
        
        if (unlocks > maxUnlocks) {
          maxUnlocks = unlocks;
          mostUnlockedApp = pkg;
        }
      }
    }
    
    return {
      'most_unlocked_app': mostUnlockedApp,
      'most_unlock_count': maxUnlocks,
      'all_unlocks': allUnlocks,
      'date': today,
    };
  }

  /// Get unlock count for a specific date
  static Future<Map<String, dynamic>> getUnlockCountForDate(String date) async {
    final stats = await DatabaseHelper.instance.database.then((db) => db.query(
      'usage_stats',
      where: 'date = ?',
      whereArgs: [date],
    ));
    
    if (stats.isNotEmpty) {
      return {
        'most_unlocked_app': stats.first['most_unlock_app'] ?? 'None',
        'most_unlock_count': (stats.first['most_unlock_count'] as int? ?? 0),
        'date': date,
      };
    }
    
    return {
      'most_unlocked_app': 'None',
      'most_unlock_count': 0,
      'date': date,
    };
  }

  /// Get time-series data for LSTM (last N days)
  /// Returns List<Map> with: date, most_unlock_count, most_unlocked_app
  static Future<List<Map<String, dynamic>>> getTimeSeriesData(int days) async {
    final today = DateTime.now();
    
    final List<Map<String, dynamic>> timeSeries = [];
    
    for (int i = 0; i < days; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = date.toIso8601String().substring(0, 10);
      
      final data = await getUnlockCountForDate(dateStr);
      
      timeSeries.add({
        'date': dateStr,
        'timestamp': date.millisecondsSinceEpoch,
        'most_unlock_count': data['most_unlock_count'],
        'most_unlocked_app': data['most_unlocked_app'],
      });
    }
    
    // Reverse to get chronological order (oldest first)
    return timeSeries.reversed.toList();
  }

  /// Get total unlock count across all selected apps
  static Future<int> getTotalUnlockCount() async {
    final appDetails = await DatabaseHelper.instance.getTodayAppDetails();
    
    await SelectedAppsManager.loadFromPrefs();
    final selectedPackages = SelectedAppsManager.selectedApps
        .map((a) => a['package'])
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    
    int totalUnlocks = 0;
    
    for (var app in appDetails) {
      final pkg = app['package_name'] as String? ?? '';
      if (selectedPackages.contains(pkg)) {
        totalUnlocks += (app['unlock_count'] as int? ?? 0);
      }
    }
    
    return totalUnlocks;
  }

  /// Get unlock count breakdown by app
  /// Returns Map with: {package: unlock_count}
  static Future<Map<String, int>> getUnlockBreakdown() async {
    final appDetails = await DatabaseHelper.instance.getTodayAppDetails();
    
    await SelectedAppsManager.loadFromPrefs();
    final selectedPackages = SelectedAppsManager.selectedApps
        .map((a) => a['package'])
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toSet();
    
    final Map<String, int> breakdown = {};
    
    for (var app in appDetails) {
      final pkg = app['package_name'] as String? ?? '';
      if (selectedPackages.contains(pkg)) {
        breakdown[pkg] = (app['unlock_count'] as int? ?? 0);
      }
    }
    
    return breakdown;
  }

  /// Log unlock count snapshot for LSTM training
  static Future<void> logUnlockSnapshot() async {
    final data = await getCurrentMostUnlocked();
    
    // Data is already stored in usage_stats table
    // This method ensures we have a snapshot at this moment
    final stats = await DatabaseHelper.instance.getTodayStats();
    if (stats != null) {
      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': (stats['daily_usage_hours'] as num? ?? 0.0).toDouble(),
        'max_session': (stats['max_session'] as num? ?? 0.0).toDouble(),
        'longest_session_app': stats['longest_session_app'] ?? 'None',
        'most_unlock_app': data['most_unlocked_app'],
        'most_unlock_count': data['most_unlock_count'],
      });
    }
    
    print("📊 Unlock count snapshot logged: ${data['most_unlock_count']} unlocks (${data['most_unlocked_app']})");
  }

  /// Get unlock statistics for LSTM input preparation
  /// Returns formatted data ready for LSTM model consumption
  static Future<Map<String, dynamic>> getLSTMInputData() async {
    final current = await getCurrentMostUnlocked();
    final timeSeries = await getTimeSeriesData(30); // Last 30 days
    final total = await getTotalUnlockCount();
    
    return {
      'current_most_unlock_count': current['most_unlock_count'],
      'current_most_unlocked_app': current['most_unlocked_app'],
      'total_unlock_count': total,
      'time_series': timeSeries,
      'feature_type': 'most_unlock_count',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

