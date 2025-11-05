/// ✅ LSTM Bridge Module
/// 
/// This module provides a ready-to-connect interface for LSTM model integration.
/// It collects, structures, and prepares all tracking data for the LSTM model,
/// and provides placeholders for AI-driven prediction and lock decisions.
/// 
/// The system is designed to work in parallel with rule-based locking:
/// - Rule-based system remains active as default
/// - LSTM can run in parallel when added
/// - Rule-based system serves as fallback safety
/// - Smooth transition from rules to AI-driven control

import 'package:refocus_app/services/daily_usage.dart';
import 'package:refocus_app/services/most_unlock_count.dart';
import 'package:refocus_app/services/max_session.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/database_helper.dart';

class LSTMBridge {
  // LSTM model integration flag
  static bool _lstmEnabled = false;
  
  /// Enable/disable LSTM model integration
  static void setLSTMEnabled(bool enabled) {
    _lstmEnabled = enabled;
    print(_lstmEnabled 
        ? "🤖 LSTM model ENABLED - AI-driven predictions active"
        : "📋 LSTM model DISABLED - Rule-based system active");
  }
  
  /// Check if LSTM is enabled
  static bool isLSTMEnabled() => _lstmEnabled;

  /// ============================================================
  /// DATA COLLECTION FOR LSTM TRAINING & PREDICTION
  /// ============================================================

  /// Collect all three core features for LSTM input
  /// Returns structured data ready for LSTM model consumption
  static Future<Map<String, dynamic>> collectAllFeatures() async {
    final dailyUsage = await DailyUsageTracker.getLSTMInputData();
    final unlockCount = await MostUnlockCountTracker.getLSTMInputData();
    final maxSession = await MaxSessionTracker.getLSTMInputData();
    
    return {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'features': {
        'daily_usage': dailyUsage,
        'most_unlock_count': unlockCount,
        'max_session': maxSession,
      },
      'metadata': {
        'lstm_enabled': _lstmEnabled,
        'data_format': 'time_series',
        'version': '1.0.0',
      },
    };
  }

  /// Get time-series data for LSTM training (all features)
  /// Returns data in chronological order ready for sequence modeling
  static Future<List<Map<String, dynamic>>> getTimeSeriesForTraining({
    int days = 30,
  }) async {
    final dailyUsage = await DailyUsageTracker.getTimeSeriesData(days);
    final unlockCount = await MostUnlockCountTracker.getTimeSeriesData(days);
    final maxSession = await MaxSessionTracker.getTimeSeriesData(days);
    
    // Merge data by date
    final Map<String, Map<String, dynamic>> merged = {};
    
    for (int i = 0; i < days; i++) {
      final date = dailyUsage.length > i ? dailyUsage[i]['date'] : null;
      if (date == null) continue;
      
      merged[date] = {
        'date': date,
        'timestamp': dailyUsage[i]['timestamp'],
        'daily_usage_hours': dailyUsage[i]['daily_usage_hours'],
        'most_unlock_count': i < unlockCount.length ? unlockCount[i]['most_unlock_count'] : 0,
        'most_unlocked_app': i < unlockCount.length ? unlockCount[i]['most_unlocked_app'] : 'None',
        'max_session_minutes': i < maxSession.length ? maxSession[i]['max_session_minutes'] : 0.0,
        'longest_session_app': i < maxSession.length ? maxSession[i]['longest_session_app'] : 'None',
      };
    }
    
    return merged.values.toList()..sort((a, b) => 
      (a['timestamp'] as int).compareTo(b['timestamp'] as int)
    );
  }

  /// Get current state snapshot for real-time LSTM prediction
  /// Returns current values of all three features
  static Future<Map<String, dynamic>> getCurrentState() async {
    final dailyUsage = await DailyUsageTracker.getCurrentDailyUsage();
    final mostUnlocked = await MostUnlockCountTracker.getCurrentMostUnlocked();
    final currentSession = await MaxSessionTracker.getCurrentSessionMinutes();
    final longestSession = await MaxSessionTracker.getLongestSessionToday();
    
    return {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'daily_usage_hours': dailyUsage,
      'most_unlock_count': mostUnlocked['most_unlock_count'],
      'most_unlocked_app': mostUnlocked['most_unlocked_app'],
      'current_session_minutes': currentSession,
      'max_session_minutes': longestSession['max_session_minutes'],
      'longest_session_app': longestSession['longest_session_app'],
    };
  }

  /// ============================================================
  /// LSTM MODEL PLACEHOLDERS (TO BE IMPLEMENTED WITH LSTM)
  /// ============================================================

  /// Predict usage pattern using LSTM model
  /// 
  /// PLACEHOLDER: This function will be implemented when LSTM model is added.
  /// Expected behavior:
  /// - Takes time-series data as input
  /// - Returns prediction: {will_exceed_daily: bool, will_exceed_session: bool, will_exceed_unlock: bool, confidence: double}
  /// - Can predict future violations based on current patterns
  /// 
  /// @param historyData: Time-series data for last N days
  /// @param currentState: Current feature values
  /// @returns Prediction map with violation probabilities
  static Future<Map<String, dynamic>> predictUsagePattern({
    required List<Map<String, dynamic>> historyData,
    required Map<String, dynamic> currentState,
  }) async {
    // PLACEHOLDER: Replace with actual LSTM model call
    if (!_lstmEnabled) {
      // Fallback to rule-based prediction
      return {
        'will_exceed_daily': await LockStateManager.isDailyLimitExceeded(
          currentState['daily_usage_hours'] as double
        ),
        'will_exceed_session': await LockStateManager.isSessionLimitExceeded(),
        'will_exceed_unlock': await LockStateManager.isUnlockLimitExceeded(
          currentState['most_unlock_count'] as int
        ),
        'confidence': 0.0,
        'method': 'rule_based',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
    
    // TODO: Implement actual LSTM model prediction
    // Example structure:
    // final prediction = await LSTMModel.predict(
    //   history: historyData,
    //   current: currentState,
    // );
    // return prediction;
    
    print("⚠️ LSTM prediction called but model not implemented yet");
    return {
      'will_exceed_daily': false,
      'will_exceed_session': false,
      'will_exceed_unlock': false,
      'confidence': 0.0,
      'method': 'lstm_placeholder',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Apply LSTM-driven lock decision
  /// 
  /// PLACEHOLDER: This function will be implemented when LSTM model is added.
  /// Expected behavior:
  /// - Receives prediction from LSTM model
  /// - Determines if lock should be applied based on AI prediction
  /// - Applies lock with appropriate cooldown/reason
  /// - Logs AI decision for analysis
  /// 
  /// @param prediction: Prediction result from predictUsagePattern()
  /// @returns Map with lock decision: {should_lock: bool, reason: String, cooldown_seconds: int}
  static Future<Map<String, dynamic>> applyLSTMLockDecision({
    required Map<String, dynamic> prediction,
  }) async {
    // PLACEHOLDER: Replace with actual LSTM-driven logic
    if (!_lstmEnabled) {
      // Fallback: Use rule-based system
      return {
        'should_lock': false,
        'reason': 'rule_based_fallback',
        'cooldown_seconds': 0,
        'method': 'rule_based',
      };
    }
    
    // TODO: Implement LSTM-driven lock decision
    // Example structure:
    // if (prediction['will_exceed_daily'] == true && prediction['confidence'] > 0.8) {
    //   await LockStateManager.setDailyLock();
    //   return {
    //     'should_lock': true,
    //     'reason': 'lstm_daily_prediction',
    //     'cooldown_seconds': 0, // Daily lock until midnight
    //     'method': 'lstm',
    //   };
    // }
    
    print("⚠️ LSTM lock decision called but model not implemented yet");
    return {
      'should_lock': false,
      'reason': 'lstm_placeholder',
      'cooldown_seconds': 0,
      'method': 'lstm_placeholder',
    };
  }

  /// ============================================================
  /// HYBRID SYSTEM: LSTM + RULE-BASED FALLBACK
  /// ============================================================

  /// Check limits using hybrid approach (LSTM if enabled, fallback to rules)
  /// This allows gradual transition from rule-based to AI-driven control
  static Future<Map<String, dynamic>?> checkLimitsHybrid({
    required double dailyHours,
    required int totalUnlocks,
  }) async {
    if (_lstmEnabled) {
      // Try LSTM prediction first
      try {
        final historyData = await getTimeSeriesForTraining(days: 7);
        final currentState = await getCurrentState();
        
        final prediction = await predictUsagePattern(
          historyData: historyData,
          currentState: currentState,
        );
        
        final lockDecision = await applyLSTMLockDecision(prediction: prediction);
        
        if (lockDecision['should_lock'] == true) {
          // Log AI decision
          await DatabaseHelper.instance.logViolation(
            violationType: 'lstm_prediction',
            appName: 'AI Prediction',
            dailyHours: dailyHours,
            sessionMinutes: currentState['current_session_minutes'] as double,
            unlockCount: totalUnlocks,
            cooldownSeconds: lockDecision['cooldown_seconds'] as int,
          );
          
          return {
            'type': lockDecision['reason'],
            'message': 'AI prediction: ${lockDecision['reason']}',
            'method': 'lstm',
            'confidence': prediction['confidence'] as double? ?? 0.0,
          };
        }
      } catch (e) {
        print("⚠️ LSTM prediction failed, falling back to rules: $e");
        // Fall through to rule-based check
      }
    }
    
    // Fallback to rule-based system (always available as safety net)
    return await LockStateManager.checkLimits(
      dailyHours: dailyHours,
      totalUnlocks: totalUnlocks,
    );
  }

  /// ============================================================
  /// DATA LOGGING FOR LSTM TRAINING
  /// ============================================================

  /// Log complete snapshot for LSTM training
  /// This should be called periodically to build training dataset
  static Future<void> logTrainingSnapshot() async {
    final currentState = await getCurrentState();
    
    // Log to database for training data collection
    await DatabaseHelper.instance.saveLSTMTrainingSnapshot(
      dailyUsageHours: currentState['daily_usage_hours'] as double,
      mostUnlockCount: currentState['most_unlock_count'] as int,
      maxSessionMinutes: currentState['max_session_minutes'] as double,
      currentSessionMinutes: currentState['current_session_minutes'] as double,
      snapshotType: 'periodic',
    );
    
    print("📊 LSTM training snapshot logged at ${DateTime.now()}");
  }

  /// Export data for LSTM model training
  /// Returns formatted data ready for model training scripts
  static Future<Map<String, dynamic>> exportTrainingData({
    int days = 30,
  }) async {
    final timeSeries = await getTimeSeriesForTraining(days: days);
    final startDate = DateTime.now().subtract(Duration(days: days)).toIso8601String().substring(0, 10);
    final endDate = DateTime.now().toIso8601String().substring(0, 10);
    final violations = await DatabaseHelper.instance.getViolations(
      startDate: startDate,
      endDate: endDate,
    );
    
    return {
      'time_series': timeSeries,
      'violations': violations,
      'export_date': DateTime.now().toIso8601String(),
      'data_format': 'lstm_training',
      'version': '1.0.0',
    };
  }
}

