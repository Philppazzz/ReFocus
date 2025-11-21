import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/ml/decision_tree_model.dart';
import 'package:refocus_app/services/hybrid_lock_manager.dart';
import 'package:refocus_app/services/ensemble_model_service.dart';
import 'package:refocus_app/database_helper.dart' as db;
import 'package:refocus_app/database_helper.dart';

/// Service for training ML model on REAL user feedback
/// Uses ensemble approach: Rule-based (AppLockManager) + user-trained model
/// Quality-based filtering prevents bias from abusive feedback
/// 
/// ✅ SHARED LIMITS: Training data uses COMBINED usage for monitored categories.
/// This ensures ML model learns patterns matching actual lock decisions (shared limits system).
class MLTrainingService {
  // ✅ CRITICAL: Prevent concurrent training attempts
  static bool _isTraining = false;
  
  // ✅ CRITICAL: Reset training flag on app initialization (handles app kill scenario)
  static void resetTrainingFlag() {
    _isTraining = false;
  }
  
  /// Train model on real user feedback
  /// ✅ SHARED LIMITS: Feedback data contains COMBINED usage for monitored categories.
  /// This replaces threshold-based labels with REAL user feedback
  /// ✅ CRITICAL: Only trains on real feedback (excludes test data via exportFeedbackForTraining)
  static Future<Map<String, dynamic>> trainOnRealFeedback() async {
    // ✅ CRITICAL: Prevent concurrent training
    if (_isTraining) {
      print('⚠️ Training already in progress, skipping duplicate request');
      return {
        'success': false,
        'error': 'Training already in progress',
        'feedback_count': 0,
      };
    }
    
    _isTraining = true;
    try {
      // ✅ CRITICAL: Get real feedback data (exportFeedbackForTraining excludes test data)
      final feedbackData = await FeedbackLogger.exportFeedbackForTraining();
      
      // ✅ VERIFICATION: Log that we're training on real data only
      print('📊 Training on real feedback only (test data excluded):');
      print('   Real feedback samples: ${feedbackData.length}');
      
      if (feedbackData.length < 100) {
        return {
          'success': false,
          'error': 'Not enough feedback data. Need at least 100 samples, got ${feedbackData.length}',
          'feedback_count': feedbackData.length,
        };
      }


      // ✅ VALIDATE: Ensure all required fields are present
      if (feedbackData.isEmpty) {
        return {
          'success': false,
          'error': 'No feedback data available for training',
          'feedback_count': 0,
        };
      }

      // ✅ VALIDATE: Check data integrity - ensure all rows have required columns
      final validFeedback = <Map<String, dynamic>>[];
      for (final feedback in feedbackData) {
        if (feedback.containsKey('category') &&
            feedback.containsKey('daily_usage_minutes') &&
            feedback.containsKey('session_usage_minutes') &&
            feedback.containsKey('time_of_day') &&
            feedback.containsKey('should_lock')) {
          validFeedback.add(feedback);
        } else {
          print('⚠️ Skipping invalid feedback row: missing required fields');
        }
      }

      if (validFeedback.length < 100) {
        return {
          'success': false,
          'error': 'Not enough valid feedback data. Need at least 100 samples, got ${validFeedback.length}',
          'feedback_count': validFeedback.length,
        };
      }


      // ✅ CONVERT: Transform validated feedback to training data format with type safety
      // ✅ SHARED LIMITS: daily_usage_minutes and session_usage_minutes are COMBINED for monitored categories
      // Dataset columns: category, daily_usage_minutes (COMBINED), session_usage_minutes (COMBINED), time_of_day, should_lock
      final trainingData = <TrainingData>[];
      for (final feedback in validFeedback) {
        try {
          // ✅ TYPE SAFETY: Ensure all values are valid before conversion
          final category = feedback['category'] as String? ?? 'Others';
          final dailyMins = (feedback['daily_usage_minutes'] as num?)?.toInt() ?? 0;
          final sessionMins = (feedback['session_usage_minutes'] as num?)?.toInt() ?? 0;
          final timeOfDay = (feedback['time_of_day'] as num?)?.toInt() ?? 12;
          final shouldLock = (feedback['should_lock'] as num?)?.toInt() ?? 0;
          
          // ✅ VALIDATION: Ensure values are within reasonable ranges
          if (dailyMins < 0 || dailyMins > 1440 || // Max 24 hours
              sessionMins < 0 || sessionMins > 1440 ||
              timeOfDay < 0 || timeOfDay > 23) {
            print('⚠️ Skipping invalid feedback row: out of range values');
            continue;
          }
          
          trainingData.add(TrainingData(
            categoryInt: DecisionTreeModel.categoryToInt(category),
            dailyUsageMins: dailyMins,
            sessionUsageMins: sessionMins,
            timeOfDay: timeOfDay,
            // ✅ REAL LABEL: Use user feedback, not threshold-based!
            // was_helpful=1 means user agreed lock was needed → should_lock=Yes
            // was_helpful=0 means user disagreed → should_lock=No
            overuse: shouldLock == 1 ? 'Yes' : 'No',
          ));
        } catch (e) {
          print('⚠️ Error converting feedback row to TrainingData: $e');
          // Skip invalid row and continue
        }
      }
      
      if (trainingData.length < 100) {
        return {
          'success': false,
          'error': 'Not enough valid training data after conversion. Need at least 100 samples, got ${trainingData.length}',
          'feedback_count': trainingData.length,
        };
      }

      print('✅ Dataset prepared: ${trainingData.length} rows with columns [categoryInt, dailyUsageMins, sessionUsageMins, timeOfDay, overuse]');

      // Initialize ensemble service (loads user model, rule-based always available)
      await EnsembleModelService.initialize();

      // ✅ ENSEMBLE APPROACH: Train user model on quality-filtered feedback
      // Save feedback to database for tracking
      // ✅ CRITICAL: Use transaction to ensure atomicity (all or nothing)
      final database = await db.DatabaseHelper.instance.database;
      try {
        // ✅ CRITICAL: Use transaction with proper rollback on error
        await database.transaction((txn) async {
          for (final feedback in feedbackData) {
            try {
              // ✅ SAFE TYPE CASTING: Handle potential null values
              final timestamp = (feedback['timestamp'] as num?)?.toInt();
              final category = feedback['category'] as String?;
              final dailyMins = (feedback['daily_usage_minutes'] as num?)?.toInt();
              final sessionMins = (feedback['session_usage_minutes'] as num?)?.toInt();
              final timeOfDay = (feedback['time_of_day'] as num?)?.toInt();
              final dayOfWeek = (feedback['day_of_week'] as num?)?.toInt();
              final shouldLock = (feedback['should_lock'] as num?)?.toInt();
              
              // ✅ VALIDATION: Skip invalid rows
              if (timestamp == null || category == null || category.isEmpty ||
                  dailyMins == null || sessionMins == null ||
                  timeOfDay == null || dayOfWeek == null || shouldLock == null) {
                print('⚠️ Skipping invalid feedback for database insert');
                continue;
              }
              
              await txn.insert('decision_tree_data', {
                'timestamp': timestamp,
                'category': category,
                'daily_usage_seconds': dailyMins * 60,
                'current_session_seconds': sessionMins * 60,
                'session_count': 1,
                'time_of_day': timeOfDay.toString(),
                'day_of_week': dayOfWeek.toString(),
                'should_lock': shouldLock, // REAL label from user!
              });
            } catch (e) {
              print('⚠️ Error inserting feedback row: $e - continuing');
              // Continue with next row (transaction will rollback if critical)
            }
          }
        }, exclusive: true); // ✅ CRITICAL: Use exclusive transaction to prevent concurrent writes
        print('✅ Feedback data saved to database (transaction complete)');
      } catch (e) {
        print('⚠️ Database transaction failed: $e');
        // ✅ CRITICAL: Transaction automatically rolls back on exception
        // Re-throw to prevent training on incomplete data
        throw Exception('Failed to save feedback data: $e');
      }

      // Train USER model on quality-filtered feedback (rule-based always available as baseline)
      try {
        await EnsembleModelService.trainUserModel(trainingData);
        print('✅ Model training completed successfully');
      } catch (e) {
        print('❌ Model training failed: $e');
        // Re-throw to indicate training failure
        throw Exception('Model training failed: $e');
      }

      // ✅ CRITICAL: Save training timestamp AFTER successful training
      await _saveLastTrainingTime();

      // Refresh ML readiness
      HybridLockManager.refreshMLReadiness();

      // Get ensemble model stats
      final ensembleStats = await EnsembleModelService.getModelStats();
      final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
      final ensembleInfo = ensembleStats['ensemble'] as Map<String, dynamic>;

      // ✅ PROFESSIONAL METRICS: Get model metrics from DecisionTreeModel
      await EnsembleModelService.initialize();
      final userModel = EnsembleModelService.getUserTrainedModel();
      if (userModel != null) {
        // Calculate train/test split info
        final totalSamples = trainingData.length;
        final trainSamples = (totalSamples * 0.8).toInt();
        final testSamples = totalSamples - trainSamples;
        
        // Save training history for analytics
        try {
          await DatabaseHelper.instance.saveTrainingHistory(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            trainingSamples: trainSamples,
            testSamples: testSamples,
            accuracy: userModel.accuracy,
            precision: userModel.precision,
            recall: userModel.recall,
            f1Score: userModel.f1Score,
            trainAccuracy: null, // Can be calculated if needed
            overfittingDetected: false, // Can be detected from train/test accuracy gap
          );
          print('✅ Training history saved for analytics');
        } catch (e) {
          print('⚠️ Failed to save training history: $e');
          // Non-critical, continue
        }
      }

      print('✅ User model trained successfully!');
      print('   Training samples: ${trainingData.length}');
      print('   User model accuracy: ${((userModelStats['accuracy'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%');
      print('   Precision: ${((userModel?.precision ?? 0.0) * 100).toStringAsFixed(1)}%');
      print('   Recall: ${((userModel?.recall ?? 0.0) * 100).toStringAsFixed(1)}%');
      print('   F1-Score: ${((userModel?.f1Score ?? 0.0) * 100).toStringAsFixed(1)}%');
      print('   Rule-based weight: ${((ensembleInfo['ruleBasedWeight'] as double) * 100).toStringAsFixed(0)}%');
      print('   User model weight: ${((ensembleInfo['userTrainedWeight'] as double) * 100).toStringAsFixed(0)}%');

      return {
        'success': true,
        'training_samples': trainingData.length,
        'accuracy': userModelStats['accuracy'] as double? ?? 0.0,
        'precision': userModel?.precision ?? 0.0,
        'recall': userModel?.recall ?? 0.0,
        'f1_score': userModel?.f1Score ?? 0.0,
        'last_trained': DateTime.now().toIso8601String(),
        'model_ready': true,
        'ensemble_stats': ensembleStats,
      };
    } catch (e, stackTrace) {
      print('❌ Error training model on real feedback: $e');
      print('Stack trace: $stackTrace');
      
      // ✅ USER-FRIENDLY ERROR MESSAGE
      String errorMessage = 'Training failed';
      if (e.toString().contains('Not enough')) {
        errorMessage = 'Not enough feedback data. Need at least 100 samples.';
      } else if (e.toString().contains('quality feedback')) {
        errorMessage = 'Not enough quality feedback. Please provide more helpful feedback.';
      } else if (e.toString().contains('database')) {
        errorMessage = 'Database error. Please restart the app.';
      } else {
        errorMessage = 'Training error: ${e.toString()}';
      }
      
      return {
        'success': false,
        'error': errorMessage,
        'technical_error': e.toString(),
      };
    } finally {
      // ✅ CRITICAL: Always reset training flag
      _isTraining = false;
    }
  }

  /// Get last training timestamp from SharedPreferences
  static Future<DateTime?> _getLastTrainingTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('ml_last_training_timestamp');
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print('⚠️ Error getting last training time: $e');
    }
    return null;
  }

  /// Save last training timestamp to SharedPreferences
  static Future<void> _saveLastTrainingTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ml_last_training_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('⚠️ Error saving last training time: $e');
    }
  }

  /// Check if model should be retrained
  /// Retrain when:
  /// - New feedback collected (100+ new samples since last training)
  /// - Feedback reaches milestones (100, 200, 500, 1000, etc.)
  /// - Model accuracy drops below threshold
  /// - Last training was more than 24 hours ago and we have new feedback
  static Future<bool> shouldRetrain() async {
    try {
      final feedbackStats = await FeedbackLogger.getStats();
      
      // ✅ CRITICAL FIX: Check EnsembleModelService's user model (not DecisionTreeService)
      await EnsembleModelService.initialize();
      final ensembleStats = await EnsembleModelService.getModelStats();
      final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
      
      final totalFeedback = feedbackStats['total_feedback'] as int;
      final lastTrainedCount = userModelStats['trainingDataCount'] as int? ?? 0;
      final lastTrainingTime = await _getLastTrainingTime();
      
      // ✅ MILESTONE-BASED TRAINING: Retrain when feedback reaches milestones
      // This ensures training happens at key points (100, 200, 500, 1000, etc.)
      final milestones = [100, 200, 500, 1000, 2000, 5000];
      for (final milestone in milestones) {
        if (totalFeedback >= milestone && lastTrainedCount < milestone) {
          return true;
        }
      }
      
      // ✅ NEW FEEDBACK TRAINING: Retrain if we have 100+ new feedback samples
      if (totalFeedback >= lastTrainedCount + 100) {
        return true;
      }

      // ✅ TIME-BASED TRAINING: Retrain if last training was >24h ago and we have new feedback
      if (lastTrainingTime != null) {
        final hoursSinceTraining = DateTime.now().difference(lastTrainingTime).inHours;
        if (hoursSinceTraining >= 24 && totalFeedback > lastTrainedCount) {
          return true;
        }
      }

      // ✅ ACCURACY-BASED TRAINING: Retrain if accuracy is too low
      // ✅ CRITICAL FIX: Use already-fetched user model stats (reuse variables from above)
      final accuracy = (userModelStats['accuracy'] as num?)?.toDouble() ?? 0.0;
      if (accuracy > 0 && accuracy < 0.7) {
        return true;
      }

      return false;
    } catch (e) {
      print('⚠️ Error checking retrain status: $e');
      return false;
    }
  }

  /// Auto-retrain if needed (call periodically or on app events)
  /// This is the main entry point for automatic training
  /// Returns true if training was triggered, false otherwise
  static Future<bool> autoRetrainIfNeeded() async {
    try {
      // Check if training is needed
      if (!await shouldRetrain()) {
        return false; // No training needed
      }

      final result = await trainOnRealFeedback();
      
      if (result['success'] == true) {
        // ✅ Save training timestamp to avoid redundant training
        await _saveLastTrainingTime();
        print('✅ Auto-retraining completed successfully');
        print('   Training samples: ${result['training_samples']}');
        print('   Model accuracy: ${((result['accuracy'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%');
        return true;
      } else {
        print('⚠️ Auto-retraining failed: ${result['error']}');
        // Don't throw - this is background operation
        return false;
      }
    } catch (e) {
      print('⚠️ Error in autoRetrainIfNeeded: $e');
      // Don't throw - this is background operation, shouldn't crash app
      return false;
    }
  }

  /// Manual training trigger (for user-initiated training)
  /// Returns training result with success status
  static Future<Map<String, dynamic>> manualTrain() async {
    try {
      final feedbackStats = await FeedbackLogger.getStats();
      final totalFeedback = feedbackStats['total_feedback'] as int;
      
      if (totalFeedback < 100) {
        return {
          'success': false,
          'error': 'Not enough feedback. Need at least 100 samples, got $totalFeedback',
          'feedback_count': totalFeedback,
        };
      }

      final result = await trainOnRealFeedback();
      
      if (result['success'] == true) {
        await _saveLastTrainingTime();
        print('✅ Manual training completed successfully');
      }
      
      return result;
    } catch (e) {
      print('❌ Error in manual training: $e');
      return {
        'success': false,
        'error': 'Training error: ${e.toString()}',
      };
    }
  }

  /// Get training status (last training time, feedback count, etc.)
  static Future<Map<String, dynamic>> getTrainingStatus() async {
    try {
      final feedbackStats = await FeedbackLogger.getStats();
      final lastTrainingTime = await _getLastTrainingTime();
      
      // ✅ CRITICAL FIX: Get user model stats from EnsembleModelService (not DecisionTreeService)
      await EnsembleModelService.initialize();
      final ensembleStats = await EnsembleModelService.getModelStats();
      final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
      
      String lastTrainingText = 'Never';
      if (lastTrainingTime != null) {
        final hoursAgo = DateTime.now().difference(lastTrainingTime).inHours;
        if (hoursAgo < 1) {
          final minsAgo = DateTime.now().difference(lastTrainingTime).inMinutes;
          lastTrainingText = '$minsAgo minutes ago';
        } else if (hoursAgo < 24) {
          lastTrainingText = '$hoursAgo hours ago';
        } else {
          final daysAgo = DateTime.now().difference(lastTrainingTime).inDays;
          lastTrainingText = '$daysAgo days ago';
        }
      }

      return {
        'total_feedback': feedbackStats['total_feedback'] as int,
        'last_training_time': lastTrainingTime?.toIso8601String(),
        'last_training_text': lastTrainingText,
        'model_trained_count': userModelStats['isValid'] == true 
            ? (userModelStats['trainingDataCount'] as int? ?? 0)
            : 0, // ✅ Safe count (excludes test data contamination)
        'model_accuracy': userModelStats['isValid'] == true 
            ? ((userModelStats['accuracy'] as num?)?.toDouble() ?? 0.0)
            : 0.0, // ✅ Only return accuracy if model is valid
        'should_retrain': await shouldRetrain(),
        'model_is_valid': userModelStats['isValid'] as bool? ?? true, // ✅ Flag for UI
      };
    } catch (e) {
      print('⚠️ Error getting training status: $e');
      return {
        'total_feedback': 0,
        'last_training_time': null,
        'last_training_text': 'Error',
        'model_trained_count': 0,
        'model_accuracy': 0.0,
        'should_retrain': false,
      };
    }
  }

  /// Get training statistics
  static Future<Map<String, dynamic>> getTrainingStats() async {
    final feedbackStats = await FeedbackLogger.getStats();
    final mlStatus = await HybridLockManager.getMLStatus();
    final ensembleStats = await EnsembleModelService.getModelStats();
    
    final userTrainedStats = ensembleStats['userTrained'] as Map<String, dynamic>;
    final ensembleInfo = ensembleStats['ensemble'] as Map<String, dynamic>;

    return {
      'feedback_count': feedbackStats['total_feedback'] as int,
      'helpful_locks': feedbackStats['helpful_locks'] as int,
      'user_overrides': feedbackStats['user_overrides'] as int,
      'helpfulness_rate': feedbackStats['helpfulness_rate'] as double,
      'override_rate': feedbackStats['override_rate'] as double,
      'model_trained': userTrainedStats['trainingDataCount'] as int? ?? 0,
      'model_accuracy': (userTrainedStats['accuracy'] as num?)?.toDouble() ?? 0.0,
      'ml_ready': mlStatus['ml_ready'] as bool,
      'current_source': mlStatus['current_source'] as String,
      'rule_based_weight': ensembleInfo['ruleBasedWeight'] as double,
      'user_trained_weight': ensembleInfo['userTrainedWeight'] as double,
    };
  }
}

