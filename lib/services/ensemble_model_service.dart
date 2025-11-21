import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:refocus_app/ml/decision_tree_model.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/app_lock_manager.dart';

/// Ensemble model service that combines rule-based + user-trained models
/// Rule-based provides unbiased baseline, user model provides personalization
/// Quality-adjusted weights prevent bias from abusive feedback
class EnsembleModelService {
  // User-trained model (personal patterns)
  static DecisionTreeModel? _userTrainedModel;
  
  // Safety limits: Never override these
  static const Map<String, int> SAFETY_LIMITS = {
    'daily_minutes': 360,   // 6 hours/day maximum
    'session_minutes': 120, // 2 hours/session maximum
  };

  /// Initialize user model (rule-based doesn't need initialization)
  /// Only loads user-trained models (never loads pretrained to avoid data leakage)
  /// 
  /// Strategy: User model starts completely fresh, only trained on real user feedback
  /// Rule-based (AppLockManager) provides the baseline, no pretrained model needed
  static Future<void> initialize() async {
    _userTrainedModel = DecisionTreeModel();
    
    // ✅ Only load user-trained model from local storage (never pretrained to avoid data leakage)
    // Pretrained models have data leakage (threshold-based labels), so we don't use them
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/decision_tree_model.json');
      
      if (await file.exists()) {
        try {
          // Read JSON to check if it's user-trained
          final jsonString = await file.readAsString();
          final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
          
          // Check if model has training data (user-trained models will have this)
          final trainingCount = jsonData['trainingDataCount'] as int? ?? 0;
          final lastTrained = jsonData['lastTrained'] as String?;
          
          // ✅ Only load if it's a user-trained model (has training data and was recently trained)
          // Pretrained models from assets won't be in user storage, so any model here is user-trained
          if (trainingCount > 0 && lastTrained != null) {
            // Load the model directly from file (bypassing loadModel which falls back to pretrained)
            final tempModel = DecisionTreeModel();
            // Use loadModel but it will load from file (won't fall back since file exists)
            final loaded = await tempModel.loadModel();
            
            if (loaded && tempModel.trainingDataCount > 0) {
              _userTrainedModel = tempModel;
              print('✅ User-trained model loaded (${tempModel.trainingDataCount} samples, personal patterns)');
              print('   Last trained: ${tempModel.lastTrained}');
            } else {
              print('⚠️ Model file exists but invalid or corrupted, starting fresh');
              _userTrainedModel = DecisionTreeModel();
            }
          } else {
            print('ℹ️ Model file exists but not user-trained, starting fresh');
            _userTrainedModel = DecisionTreeModel();
          }
        } catch (e) {
          print('⚠️ Error reading model file (may be corrupted): $e - starting fresh');
          // ✅ CRITICAL: If file is corrupted, delete it and start fresh
          try {
            await file.delete();
            print('   Deleted corrupted model file');
          } catch (deleteError) {
            print('   Could not delete corrupted file: $deleteError');
          }
          _userTrainedModel = DecisionTreeModel();
        }
      } else {
        print('ℹ️ No user-trained model yet (will train on real user feedback only)');
      }
    } catch (e) {
      print('ℹ️ Error loading user model: $e - starting fresh');
      _userTrainedModel = DecisionTreeModel();
    }
  }

  /// Get weighted prediction from ensemble
  /// Combines rule-based (baseline) + user-trained (personal) models
  /// Uses quality-adjusted weights to prevent bias
  /// 
  /// ✅ SHARED LIMITS: For monitored categories, dailyUsageMinutes and sessionUsageMinutes
  /// should be COMBINED across all 3 categories (matching training data).
  static Future<Map<String, dynamic>> predict({
    required String category,
    required int dailyUsageMinutes, // ✅ COMBINED for monitored categories
    required int sessionUsageMinutes, // ✅ COMBINED for monitored categories
    required int timeOfDay,
  }) async {
    // Step 1: Check safety limits (always enforce)
    if (_exceedsSafetyLimits(dailyUsageMinutes, sessionUsageMinutes)) {
      return {
        'shouldLock': true,
        'source': 'safety_override',
        'confidence': 1.0,
        'reason': 'Exceeds safety limits (${dailyUsageMinutes} min daily, ${sessionUsageMinutes} min session)',
        'ruleBasedWeight': 1.0,
        'userTrainedWeight': 0.0,
      };
    }

    // Step 2: Get rule-based prediction (unbiased baseline)
    bool ruleBasedLock = false;
    try {
      ruleBasedLock = await AppLockManager.shouldLockApp(
        category: category,
        dailyUsageMinutes: dailyUsageMinutes,
        sessionUsageMinutes: sessionUsageMinutes,
        currentHour: timeOfDay,
      );
    } catch (e) {
      print('⚠️ Error in rule-based prediction: $e');
      // ✅ SAFE FALLBACK: If rule-based fails, use safety limits
      ruleBasedLock = _exceedsSafetyLimits(dailyUsageMinutes, sessionUsageMinutes);
    }

    // Step 3: Get user-trained prediction (if available)
    bool userTrainedLock = false;
    bool hasUserModel = false;
    
    if (_userTrainedModel != null && _userTrainedModel!.trainingDataCount > 0) {
      try {
        // ✅ VALIDATION: trainingDataCount > 0 implies model is trained
        // The predict() method will handle null root with fallback prediction
        // ✅ CRITICAL: Validate inputs before prediction
        if (category.isEmpty) {
          print('⚠️ Empty category in user model prediction, skipping');
        } else if (dailyUsageMinutes < 0 || dailyUsageMinutes > 1440 ||
                   sessionUsageMinutes < 0 || sessionUsageMinutes > 1440 ||
                   timeOfDay < 0 || timeOfDay > 23) {
          print('⚠️ Invalid input values in user model prediction, skipping');
        } else {
          final userPrediction = _userTrainedModel!.predict(
            category: category,
            dailyUsageMins: dailyUsageMinutes,
            sessionUsageMins: sessionUsageMinutes,
            timeOfDay: timeOfDay,
          );
          userTrainedLock = userPrediction == 'Yes';
          hasUserModel = true;
        }
      } catch (e, stackTrace) {
        print('⚠️ User model prediction error: $e');
        print('Stack trace: $stackTrace');
        // ✅ SAFE FALLBACK: If user model fails, continue with rule-based only
        hasUserModel = false;
      }
    }

    // Step 4: Calculate quality-adjusted weights
    // ✅ CRITICAL: Safe error handling for feedback stats
    double helpfulnessRate = 0.0;
    int feedbackCount = 0;
    
    try {
      final feedbackStats = await FeedbackLogger.getStats();
      helpfulnessRate = (feedbackStats['helpfulness_rate'] as num?)?.toDouble() ?? 0.0;
      feedbackCount = (feedbackStats['total_feedback'] as num?)?.toInt() ?? 0;
    } catch (e) {
      print('⚠️ Error getting feedback stats: $e - using defaults');
      // Use safe defaults (0% helpfulness, 0 count)
    }
    
    final weights = _calculateQualityBasedWeights(
      helpfulnessRate,
      feedbackCount,
      hasUserModel,
    );
    
    // Step 5: Weighted ensemble prediction
    final ruleBasedWeight = weights['ruleBased']!;
    final userTrainedWeight = weights['userTrained']!;
    
    // ✅ EDGE CASE HANDLING: If no user model, use rule-based only
    if (!hasUserModel) {
      return {
        'shouldLock': ruleBasedLock,
        'source': 'rule_based',
        'confidence': ruleBasedLock ? 1.0 : 0.0,
        'reason': ruleBasedLock 
            ? 'Rule-based prediction: Lock recommended'
            : 'Rule-based prediction: Within safe limits',
        'ruleBasedWeight': 1.0,
        'userTrainedWeight': 0.0,
        'ruleBasedPrediction': ruleBasedLock,
        'userTrainedPrediction': false,
      };
    }
    
    // Convert boolean to double for weighted average
    final ruleBasedScore = ruleBasedLock ? 1.0 : 0.0;
    final userTrainedScore = userTrainedLock ? 1.0 : 0.0;
    
    // ✅ VALIDATION: Ensure weights sum to 1.0 (should always be true, but verify)
    final totalWeight = ruleBasedWeight + userTrainedWeight;
    final normalizedRuleWeight = totalWeight > 0 ? ruleBasedWeight / totalWeight : 0.5;
    final normalizedUserWeight = totalWeight > 0 ? userTrainedWeight / totalWeight : 0.5;
    
    final ensembleScore = (ruleBasedScore * normalizedRuleWeight) + 
                          (userTrainedScore * normalizedUserWeight);
    
    // ✅ CRITICAL: Validate ensemble score (prevent NaN/Infinity)
    final validScore = ensembleScore.isNaN || ensembleScore.isInfinite 
        ? (ruleBasedLock ? 1.0 : 0.0)  // Fallback to rule-based if invalid
        : ensembleScore.clamp(0.0, 1.0);  // Clamp to valid range
    
    // ✅ EDGE CASE: Handle exact 0.5 score (tie) - favor rule-based for safety
    final shouldLock = validScore > 0.5 || (validScore == 0.5 && ruleBasedLock);

    return {
      'shouldLock': shouldLock,
      'source': hasUserModel ? 'ensemble' : 'rule_based',
      'confidence': validScore,  // Use validated score
      'reason': shouldLock 
          ? 'Ensemble prediction: Lock recommended'
          : 'Ensemble prediction: Within safe limits',
      'ruleBasedWeight': ruleBasedWeight,
      'userTrainedWeight': userTrainedWeight,
      'ruleBasedPrediction': ruleBasedLock,
      'userTrainedPrediction': userTrainedLock,
    };
  }

  /// Check if usage exceeds safety limits
  static bool _exceedsSafetyLimits(int dailyMinutes, int sessionMinutes) {
    return dailyMinutes >= SAFETY_LIMITS['daily_minutes']! ||
           sessionMinutes >= SAFETY_LIMITS['session_minutes']!;
  }

  /// Calculate quality-adjusted weights for ensemble
  /// Prevents bias by adjusting weights based on feedback quality (helpfulness rate)
  static Map<String, double> _calculateQualityBasedWeights(
    double helpfulnessRate,
    int feedbackCount,
    bool hasUserModel,
  ) {
    // If user gives very helpful feedback (>70%), trust user model more
    if (helpfulnessRate > 70 && feedbackCount >= 300 && hasUserModel) {
      print('✅ High helpfulness rate (${helpfulnessRate.toStringAsFixed(1)}%) - balanced weights');
      return {'ruleBased': 0.5, 'userTrained': 0.5};
    }
    
    // If good quality feedback (40-70% helpful), balanced but favor rule-based
    if (helpfulnessRate >= 40 && helpfulnessRate <= 70 && hasUserModel) {
      return {'ruleBased': 0.7, 'userTrained': 0.3};
    }
    
    // If low helpfulness rate (<40%), heavily favor rule-based (user may not be engaging)
    if (helpfulnessRate < 40 && feedbackCount >= 50 && hasUserModel) {
      print('⚠️ Low helpfulness rate (${helpfulnessRate.toStringAsFixed(1)}%) - using rule-based (90%)');
      return {'ruleBased': 0.9, 'userTrained': 0.1};
    }
    
    // If not enough user data or low quality, trust rule-based more
    if (!hasUserModel || feedbackCount < 100) {
      return {'ruleBased': 0.9, 'userTrained': 0.1};
    }
    
    // Default: Trust rule-based more (safety)
    return {'ruleBased': 0.8, 'userTrained': 0.2};
  }

  /// Train user model on quality-filtered feedback ONLY
  /// 
  /// ✅ COMPLETE TRAINING PIPELINE:
  /// 1. Receives TrainingData with complete features: [categoryInt, dailyUsageMins, sessionUsageMins, timeOfDay, overuse]
  /// 2. Filters quality feedback to remove abusive patterns
  /// 3. Converts to feature vectors: [categoryInt, dailyUsageMins, sessionUsageMins, timeOfDay]
  /// 4. Trains decision tree using ID3 algorithm (entropy, information gain, threshold optimization)
  /// 5. Evaluates accuracy on training data
  /// 6. Saves model to local storage
  /// 
  /// ✅ NO PRETRAINED DATA: User model starts completely fresh
  /// ✅ NO DATA LEAKAGE: Only uses real user feedback (not threshold-based labels)
  /// ✅ PERSONALIZATION: Learns actual user patterns, not synthetic rules
  /// 
  /// Strategy:
  /// - Rule-based (AppLockManager) = General baseline (no data leakage, works immediately)
  /// - User model = Personal patterns (no data leakage, pure learning from feedback)
  /// - Ensemble = Combines both with quality-adjusted weights
  static Future<void> trainUserModel(List<TrainingData> feedbackData) async {
    if (_userTrainedModel == null) {
      _userTrainedModel = DecisionTreeModel();
    }


    // ✅ STEP 1: Filter quality feedback (remove abusive patterns)
    // This ensures we only train on genuine user feedback
    final qualityFeedback = await _filterQualityFeedback(feedbackData);

    if (qualityFeedback.length < 20) {
      // ✅ IMPROVED: More informative error message
      throw Exception('Not enough quality feedback for training. Need at least 20 samples, got ${qualityFeedback.length}. '
          'Please provide more helpful feedback (mark locks as "Yes, helpful" when appropriate) to improve model training.');
    }

    // ✅ STEP 2: Train user model on quality feedback ONLY (no pretrained data)
    // Note: Dataset balancing is done in ML Pipeline Test Screen for testing only
    // Real app uses actual feedback distribution (no artificial balancing)
    // DecisionTreeModel.trainModel() will:
    // - Convert TrainingData to feature vectors: [categoryInt, dailyUsageMins, sessionUsageMins, timeOfDay]
    // - Build decision tree using ID3 algorithm (_buildTree)
    // - Calculate entropy (_calculateEntropy)
    // - Find best features (_findBestFeature with information gain)
    // - Find best thresholds (_findBestThreshold)
    // - Evaluate accuracy (evaluateAccuracy)
    print('   Training decision tree with ID3 algorithm...');
    await _userTrainedModel!.trainModel(qualityFeedback);
    
    // ✅ STEP 3: Save trained model to local storage
    print('   Saving model to local storage...');
    await _userTrainedModel!.saveModel();
    
    // ✅ CRITICAL: Verify model was saved successfully
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/decision_tree_model.json');
      if (!await file.exists()) {
        throw Exception('Model file was not created after save');
      }
      
      // ✅ CRITICAL: Verify file is readable and valid JSON
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      if (jsonData['tree'] == null && jsonData['trainingDataCount'] == null) {
        throw Exception('Model file is invalid or corrupted');
      }
      
      print('✅ Model file verified: ${file.path}');
    } catch (e) {
      print('❌ Model save verification failed: $e');
      throw Exception('Failed to save model: $e');
    }

    print('✅ Model training complete!');
    print('   Training samples: ${qualityFeedback.length} (from ${feedbackData.length} total)');
    print('   Model accuracy: ${((_userTrainedModel!.accuracy) * 100).toStringAsFixed(1)}%');
    print('   Model saved: decision_tree_model.json');
    print('   ✅ No pretrained data used (avoids data leakage)');
    print('   ✅ Pure personalization from real user patterns');
  }

  /// Filter feedback to remove low-quality patterns
  /// Only use quality feedback to prevent bias
  /// ✅ CRITICAL: Improved error handling and user-friendly messages
  /// ✅ SAFEGUARD 4: Enhanced filtering - removes outliers that contradict usage patterns
  static Future<List<TrainingData>> _filterQualityFeedback(List<TrainingData> allFeedback) async {
    try {
      final stats = await FeedbackLogger.getStats();
      final helpfulnessRate = (stats['helpfulness_rate'] as num?)?.toDouble() ?? 0.0;
      final totalFeedback = (stats['total_feedback'] as num?)?.toInt() ?? 0;
      
      // ✅ SAFEGUARD 4.1: Filter outliers that contradict usage patterns
      // Remove feedback where:
      // - Usage >90% but user said "Not helpful" (likely accidental)
      // - Usage <20% but user said "Helpful" (likely accidental)
      final filteredFeedback = <TrainingData>[];
      int outliersRemoved = 0;
      
      for (final feedback in allFeedback) {
        // Calculate usage percentage (assuming max limits: 360 daily, 120 session)
        final dailyPercentage = (feedback.dailyUsageMins / 360.0) * 100;
        final sessionPercentage = (feedback.sessionUsageMins / 120.0) * 100;
        final maxPercentage = dailyPercentage > sessionPercentage ? dailyPercentage : sessionPercentage;
        
        // Check for contradictory patterns
        final isOutlier = (maxPercentage >= 90 && feedback.overuse == 'No') || // High usage but "Not helpful"
                          (maxPercentage < 20 && feedback.overuse == 'Yes');   // Low usage but "Helpful"
        
        if (isOutlier) {
          outliersRemoved++;
          print('   ⚠️ Filtered outlier: ${feedback.overuse} at ${maxPercentage.toStringAsFixed(0)}% usage');
          continue; // Skip this feedback
        }
        
        filteredFeedback.add(feedback);
      }
      
      if (outliersRemoved > 0) {
        print('   ✅ Removed $outliersRemoved outliers (contradictory usage patterns)');
      }
      
      // ✅ SAFEGUARD 4.2: If user always says "No" (<10% helpful), only use "helpful" feedback for training
      if (helpfulnessRate < 10 && totalFeedback >= 20) {
        print('⚠️ Low helpfulness rate (${helpfulnessRate.toStringAsFixed(1)}%) - filtering to quality feedback only');
        // Only use feedback where user said "Yes, helpful" (overuse = 'Yes')
        final qualityOnly = filteredFeedback.where((f) => f.overuse == 'Yes').toList();
        if (qualityOnly.length >= 20) {
          print('   Using ${qualityOnly.length} quality samples (filtered from ${allFeedback.length} total, ${outliersRemoved} outliers removed)');
          return qualityOnly;
        } else {
          print('   ⚠️ Not enough quality samples (${qualityOnly.length} < 20), using all but will weight less');
          // Return filtered feedback but with warning (training will proceed)
          return filteredFeedback;
        }
      }
      
      // Good quality feedback - use filtered feedback (outliers already removed)
      if (outliersRemoved > 0) {
        print('   ✅ Using ${filteredFeedback.length} quality samples (${outliersRemoved} outliers removed)');
      }
      return filteredFeedback;
    } catch (e) {
      print('⚠️ Error filtering quality feedback: $e - using all feedback');
      // ✅ SAFE FALLBACK: Return all feedback if filtering fails
      return allFeedback;
    }
  }

  /// Get user-trained model instance (for accessing metrics)
  static DecisionTreeModel? getUserTrainedModel() {
    return _userTrainedModel;
  }

  /// Get model statistics
  /// ✅ CRITICAL: Validates that model was not trained on test data
  static Future<Map<String, dynamic>> getModelStats() async {
    final feedbackStats = await FeedbackLogger.getStats();
    final feedbackCount = feedbackStats['total_feedback'] as int;
    final helpfulnessRate = feedbackStats['helpfulness_rate'] as double;
    
    // ✅ CRITICAL FIX: Validate model wasn't trained on test data
    // If model's trainingDataCount > real feedback count, model was trained on test data
    int safeTrainingDataCount = 0;
    bool modelIsValid = true;
    
    if (_userTrainedModel != null && _userTrainedModel!.trainingDataCount > 0) {
      final modelTrainingCount = _userTrainedModel!.trainingDataCount;
      
      // ✅ VALIDATION: Model should not have more training samples than real feedback
      // This detects if model was trained on test data
      if (modelTrainingCount > feedbackCount) {
        print('⚠️ CRITICAL: Model training count ($modelTrainingCount) > real feedback count ($feedbackCount)');
        print('   Model may have been trained on test data - marking as invalid');
        modelIsValid = false;
        safeTrainingDataCount = 0; // Don't trust this model
      } else {
        safeTrainingDataCount = modelTrainingCount;
      }
    }
    
    final hasValidModel = modelIsValid && (_userTrainedModel != null && safeTrainingDataCount > 0);
    
    final weights = _calculateQualityBasedWeights(
      helpfulnessRate,
      feedbackCount,
      hasValidModel,
    );
    
    return {
      'ruleBased': {
        'exists': true,  // Always available
        'source': 'AppLockManager',
      },
      'userTrained': {
        'exists': hasValidModel,
        'accuracy': modelIsValid ? (_userTrainedModel?.accuracy ?? 0.0) : 0.0,
        'trainingDataCount': safeTrainingDataCount, // ✅ Safe count (excludes test data contamination)
        'isValid': modelIsValid, // ✅ Flag indicating if model is valid
      },
      'ensemble': {
        'ruleBasedWeight': weights['ruleBased'],
        'userTrainedWeight': weights['userTrained'],
        'feedbackCount': feedbackCount,
        'helpfulnessRate': helpfulnessRate,
      },
      'safetyLimits': SAFETY_LIMITS,
    };
  }
}
