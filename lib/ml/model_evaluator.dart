import 'package:refocus_app/ml/decision_tree_model.dart';

/// Professional-grade model evaluation metrics
/// Calculates Precision, Recall, F1-Score, Confusion Matrix, and per-category metrics
class ModelEvaluator {
  /// Calculate comprehensive evaluation metrics
  static Map<String, dynamic> evaluateModel(
    DecisionTreeModel model,
    List<TrainingData> testData,
  ) {
    if (testData.isEmpty) {
      return _emptyMetrics();
    }

    // Calculate confusion matrix
    final confusionMatrix = _calculateConfusionMatrix(model, testData);
    
    final tp = confusionMatrix['true_positive'] as int;
    final tn = confusionMatrix['true_negative'] as int;
    final fp = confusionMatrix['false_positive'] as int;
    final fn = confusionMatrix['false_negative'] as int;

    // ✅ IMPROVED: Calculate metrics with better handling of edge cases
    final total = tp + tn + fp + fn;
    final accuracy = total > 0 ? (tp + tn) / total : 0.0;
    
    // ✅ IMPROVED: Handle edge cases where one class is missing
    // Precision: Of all predicted positives, how many were correct?
    double precision = 0.0;
    if (tp + fp > 0) {
      precision = tp / (tp + fp);
    } else if (tp == 0 && fp == 0) {
      // No positive predictions - precision is undefined, but we can't penalize
      // If there are no actual positives either, precision doesn't matter
      if (tp + fn == 0) {
        precision = 1.0; // No positives to predict - perfect precision
      } else {
        precision = 0.0; // Should have predicted positives but didn't
      }
    }
    
    // Recall: Of all actual positives, how many did we catch?
    double recall = 0.0;
    if (tp + fn > 0) {
      recall = tp / (tp + fn);
    } else if (tp == 0 && fn == 0) {
      // No actual positives - recall is undefined
      // If there are no predicted positives either, recall doesn't matter
      if (tp + fp == 0) {
        recall = 1.0; // No positives to catch - perfect recall
      } else {
        recall = 0.0; // Predicted positives when there were none
      }
    }
    
    // F1-Score: Harmonic mean of precision and recall
    // ✅ IMPROVED: Handle cases where both are 0 or undefined
    double f1Score = 0.0;
    if (precision > 0 || recall > 0) {
      if (precision + recall > 0) {
        f1Score = 2 * (precision * recall) / (precision + recall);
      }
    } else if (tp == 0 && fp == 0 && fn == 0) {
      // All predictions are true negatives - perfect F1 (no positives to predict)
      f1Score = 1.0;
    }
    
    // ✅ VALIDATION: Ensure metrics are valid numbers
    if (precision.isNaN || precision.isInfinite) precision = 0.0;
    if (recall.isNaN || recall.isInfinite) recall = 0.0;
    if (f1Score.isNaN || f1Score.isInfinite) f1Score = 0.0;
    
    // ✅ VALIDATION: Ensure metrics are valid
    if (accuracy.isNaN || accuracy.isInfinite) {
      print('⚠️ Invalid accuracy calculated, defaulting to 0.0');
      return _emptyMetrics();
    }

    // Calculate per-category metrics
    final perCategoryMetrics = _calculatePerCategoryMetrics(model, testData);

    return {
      'accuracy': accuracy,
      'precision': precision,
      'recall': recall,
      'f1_score': f1Score,
      'confusion_matrix': confusionMatrix,
      'per_category': perCategoryMetrics,
      'total_samples': testData.length,
      'true_positive': tp,
      'true_negative': tn,
      'false_positive': fp,
      'false_negative': fn,
    };
  }

  /// Calculate confusion matrix
  /// ✅ ROBUST: Handles all edge cases and validates predictions
/// ✅ CRITICAL: Made public for debugging identical metrics issue
  static Map<String, int> _calculateConfusionMatrix(
    DecisionTreeModel model,
    List<TrainingData> testData,
  ) {
    int tp = 0; // True Positive: Predicted Lock, Actual Lock
    int tn = 0; // True Negative: Predicted No Lock, Actual No Lock
    int fp = 0; // False Positive: Predicted Lock, Actual No Lock
    int fn = 0; // False Negative: Predicted No Lock, Actual Lock
    
    int totalPredictions = 0;
    int yesPredictions = 0;
    int noPredictions = 0;
    int actualYes = 0;
    int actualNo = 0;

    for (final data in testData) {
      try {
        // ✅ VALIDATION: Ensure data is valid before prediction
        if (data.categoryInt < 0 || data.categoryInt > 3) {
          print('⚠️ Invalid categoryInt: ${data.categoryInt}, skipping');
          continue;
        }
        
        if (data.dailyUsageMins < 0 || data.dailyUsageMins > 1440 ||
            data.sessionUsageMins < 0 || data.sessionUsageMins > 1440 ||
            data.timeOfDay < 0 || data.timeOfDay > 23) {
          print('⚠️ Invalid usage values, skipping');
          continue;
        }
        
        final prediction = model.predict(
          category: DecisionTreeModel.intToCategory(data.categoryInt),
          dailyUsageMins: data.dailyUsageMins,
          sessionUsageMins: data.sessionUsageMins,
          timeOfDay: data.timeOfDay,
        );

        final actual = data.overuse;

        // ✅ VALIDATION: Ensure prediction and actual are valid
        if (prediction != 'Yes' && prediction != 'No') {
          print('⚠️ Invalid prediction: $prediction, expected Yes or No');
          continue;
        }
        
        if (actual != 'Yes' && actual != 'No') {
          print('⚠️ Invalid actual label: $actual, expected Yes or No');
          continue;
        }

        // Track prediction distribution
        totalPredictions++;
        if (prediction == 'Yes') yesPredictions++;
        if (prediction == 'No') noPredictions++;
        if (actual == 'Yes') actualYes++;
        if (actual == 'No') actualNo++;

        if (prediction == 'Yes' && actual == 'Yes') {
          tp++;
        } else if (prediction == 'No' && actual == 'No') {
          tn++;
        } else if (prediction == 'Yes' && actual == 'No') {
          fp++;
        } else if (prediction == 'No' && actual == 'Yes') {
          fn++;
        }
      } catch (e) {
        print('⚠️ Error calculating confusion matrix for sample: $e');
        // Continue with next sample
      }
    }
    
    // ✅ DEBUGGING: Log prediction distribution to diagnose issues
    print('📊 Prediction Distribution:');
    print('   Total predictions: $totalPredictions');
    print('   Predicted "Yes": $yesPredictions (${totalPredictions > 0 ? (yesPredictions / totalPredictions * 100).toStringAsFixed(1) : 0}%)');
    print('   Predicted "No": $noPredictions (${totalPredictions > 0 ? (noPredictions / totalPredictions * 100).toStringAsFixed(1) : 0}%)');
    print('   Actual "Yes": $actualYes (${totalPredictions > 0 ? (actualYes / totalPredictions * 100).toStringAsFixed(1) : 0}%)');
    print('   Actual "No": $actualNo (${totalPredictions > 0 ? (actualNo / totalPredictions * 100).toStringAsFixed(1) : 0}%)');
    print('   Confusion Matrix: TP=$tp, TN=$tn, FP=$fp, FN=$fn');
    
    // ✅ VALIDATION: Warn if model is predicting only one class
    if (yesPredictions == 0 && actualYes > 0) {
      print('⚠️ CRITICAL: Model predicted NO "Yes" cases but test set has $actualYes "Yes" cases!');
      print('   This will result in 0 recall and F1-score. Model needs better training.');
    }
    if (noPredictions == 0 && actualNo > 0) {
      print('⚠️ CRITICAL: Model predicted NO "No" cases but test set has $actualNo "No" cases!');
      print('   This will result in poor precision. Model needs better training.');
    }

    return {
      'true_positive': tp,
      'true_negative': tn,
      'false_positive': fp,
      'false_negative': fn,
    };
  }

  /// Calculate per-category metrics
  static Map<String, Map<String, dynamic>> _calculatePerCategoryMetrics(
    DecisionTreeModel model,
    List<TrainingData> testData,
  ) {
    final categoryData = <String, List<TrainingData>>{};
    
    // Group data by category
    for (final data in testData) {
      final category = DecisionTreeModel.intToCategory(data.categoryInt);
      categoryData.putIfAbsent(category, () => []).add(data);
    }

    final perCategory = <String, Map<String, dynamic>>{};

    for (final entry in categoryData.entries) {
      final category = entry.key;
      final categoryTestData = entry.value;
      
      final cm = _calculateConfusionMatrix(model, categoryTestData);
      final tp = cm['true_positive'] as int;
      final tn = cm['true_negative'] as int;
      final fp = cm['false_positive'] as int;
      final fn = cm['false_negative'] as int;

      final total = categoryTestData.length;
      final accuracy = total > 0 ? (tp + tn) / total : 0.0;
      final precision = (tp + fp) > 0 ? tp / (tp + fp) : 0.0;
      final recall = (tp + fn) > 0 ? tp / (tp + fn) : 0.0;
      final f1Score = (precision + recall) > 0 
          ? 2 * (precision * recall) / (precision + recall) 
          : 0.0;

      perCategory[category] = {
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1_score': f1Score,
        'samples': total,
        'true_positive': tp,
        'true_negative': tn,
        'false_positive': fp,
        'false_negative': fn,
      };
    }

    return perCategory;
  }

  /// Return empty metrics structure
  static Map<String, dynamic> _emptyMetrics() {
    return {
      'accuracy': 0.0,
      'precision': 0.0,
      'recall': 0.0,
      'f1_score': 0.0,
      'confusion_matrix': {
        'true_positive': 0,
        'true_negative': 0,
        'false_positive': 0,
        'false_negative': 0,
      },
      'per_category': <String, Map<String, dynamic>>{},
      'total_samples': 0,
      'true_positive': 0,
      'true_negative': 0,
      'false_positive': 0,
      'false_negative': 0,
    };
  }
}

