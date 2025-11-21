import 'package:refocus_app/services/app_lock_manager.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/ensemble_model_service.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';
import 'package:refocus_app/services/emergency_service.dart';
import 'package:refocus_app/services/ml_effectiveness_tracker.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/pages/home_page.dart'; // For AppState

/// Hybrid lock manager with learning mode support
/// 
/// Strategy:
/// 1. Safety Limits (ALWAYS): Hard limits (6h daily / 2h session) - protects users from extreme overuse
/// 2. Learning Mode (default): No locks for normal usage, collects unbiased data + proactive feedback
/// 3. Rule-Based Mode (optional): Traditional locks from Day 1 (user choice)
/// 4. ML Mode: Ensemble model (rule-based + user-trained) when ready (300+ feedback, diversity checks)
/// 5. Quality-Adjusted Weights: Prevents bias from abusive feedback
/// 
/// Best Approach:
/// - Learning Mode as default: Collects unbiased data for best ML quality
/// - Safety limits always enforced: Protects users even in learning mode
/// - Result: Best ML quality (unbiased data) + User safety (hard limits)
class HybridLockManager {
  static bool _mlModelReady = false;
  static bool _hasCheckedMLReadiness = false;
  static const int MIN_FEEDBACK_FOR_ML = 300; // Optimized from 500 (faster activation)
  static const double MIN_ML_CONFIDENCE = 0.6; // Use ML only if confidence > 60%
  
  // Safety limits: ALWAYS enforced (even in learning mode)
  // These protect users from extreme overuse while allowing unbiased data collection
  static const int SAFETY_DAILY_MINUTES = 360;   // 6 hours/day maximum
  static const int SAFETY_SESSION_MINUTES = 120;  // 2 hours/session maximum

  /// Check if ML model is ready to use
  /// ML is ready when:
  /// - We have 300+ real user feedback samples (optimized from 500)
  /// - Data diversity checks pass (different days, times, categories)
  /// - Model has been trained on that feedback
  /// ✅ NO DAY REQUIREMENT: 300+ samples is sufficient for ML activation
  static Future<bool> _checkMLReadiness() async {
    if (_hasCheckedMLReadiness) {
      return _mlModelReady;
    }

    try {
      // Check if we have enough feedback
      final hasEnoughFeedback = await FeedbackLogger.hasEnoughFeedbackForTraining(
        minSamples: MIN_FEEDBACK_FOR_ML,
      );

      if (!hasEnoughFeedback) {
        _mlModelReady = false;
        _hasCheckedMLReadiness = true;
        return false;
      }

      // ✅ CRITICAL FIX: Check EnsembleModelService's user-trained model (not DecisionTreeService)
      // DecisionTreeService might load pretrained models, but we only want user-trained models
      await EnsembleModelService.initialize();
      final ensembleStats = await EnsembleModelService.getModelStats();
      final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
      final isTrained = userModelStats['trainingDataCount'] as int? ?? 0;
      
      // Model should be trained on real feedback (not just default/fallback)
      if (isTrained < MIN_FEEDBACK_FOR_ML) {
        _mlModelReady = false;
        _hasCheckedMLReadiness = true;
        return false;
      }

      _mlModelReady = true;
      _hasCheckedMLReadiness = true;
      print('✅ ML model is ready! Using ML predictions with rule-based fallback');
      
      // Start ML effectiveness tracking (for thesis validation)
      await MLEffectivenessTracker.onMLActivated();
      
      return true;
    } catch (e) {
      print('⚠️ Error checking ML readiness: $e');
      _mlModelReady = false;
      _hasCheckedMLReadiness = true;
      return false;
    }
  }

  /// Force refresh ML readiness check (call after training model)
  static void refreshMLReadiness() {
    _hasCheckedMLReadiness = false;
    _mlModelReady = false;
  }

  /// Check if usage exceeds safety limits (always enforced)
  /// These limits protect users from extreme overuse
  /// Even in learning mode, we enforce these hard limits
  static bool _exceedsSafetyLimits(int dailyMinutes, int sessionMinutes) {
    return dailyMinutes >= SAFETY_DAILY_MINUTES || 
           sessionMinutes >= SAFETY_SESSION_MINUTES;
  }

  /// Determine if app should be locked using hybrid approach
  /// 
  /// ✅ SHARED LIMITS: For monitored categories, calculates COMBINED usage across all 3 categories.
  /// 
  /// Returns:
  /// - Map with 'shouldLock' (bool), 'source' ('learning', 'ml', 'rule_based', 'safety'), 
  ///   'confidence' (0.0-1.0), 'reason' (String), and 'shouldAskFeedback' (bool)
  static Future<Map<String, dynamic>> shouldLockApp({
    required String category,
    required int dailyUsageMinutes, // Per-category usage (will be converted to combined if monitored)
    required int sessionUsageMinutes, // Per-category usage (will be converted to combined if monitored)
    required int currentHour,
    String? appName,
    String? packageName,
  }) async {
    // ✅ SHARED LIMITS: Calculate COMBINED usage for monitored categories
    // ✅ CRITICAL: Use getEffectiveSessionUsage() to account for 5-minute inactivity threshold
    // This ensures lock decisions and ML predictions use actual active session (0 if inactive for 5+ minutes)
    int combinedDailyMinutes = dailyUsageMinutes;
    int combinedSessionMinutes = sessionUsageMinutes;
    
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    if (monitoredCategories.contains(category)) {
      try {
        // ✅ CRITICAL FIX: Read daily usage directly from database (source of truth)
        // This ensures accuracy and consistency with frontend (home_page.dart, dashboard_screen.dart)
        // Database is updated by UsageService.getUsageStatsWithEvents() which processes Android UsageStats
        final db = DatabaseHelper.instance;
        final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
        final dbCombinedDaily = ((categoryUsage['Social'] ?? 0.0) +
                                 (categoryUsage['Games'] ?? 0.0) +
                                 (categoryUsage['Entertainment'] ?? 0.0)).round();
        
        // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
        // ✅ SINGLE SOURCE OF TRUTH: Same function used by home_page.dart for UI display
        // This ensures ML predictions use EXACTLY the same session time as frontend display
        // LockStateManager tracks time in milliseconds and handles combined session across all monitored categories
        // ✅ ACCURACY: Session only increments when monitored apps are open, stops when closed/switched away
        // This ensures ML model predictions are based on the same accurate data shown to users
        final dbCombinedSession = (await LockStateManager.getCurrentSessionMinutes()).round();
        
        // ✅ TEST MODE DETECTION: If passed values are significantly different from DB values,
        // this might be a test scenario. Use passed values if they're provided explicitly.
        // However, in real app usage, always use DB values for accuracy.
        // For test predictions, we want to use the test values, so we check if DB values are 0 or very small
        // and the passed values are non-zero (indicating test mode)
        if (dbCombinedDaily == 0 && dbCombinedSession == 0 && 
            dailyUsageMinutes > 0 && sessionUsageMinutes > 0) {
          // Likely test mode - use passed values
          combinedDailyMinutes = dailyUsageMinutes;
          combinedSessionMinutes = sessionUsageMinutes;
          print('📊 Test mode detected: Using passed values for $category: ${combinedDailyMinutes}min daily, ${combinedSessionMinutes}min session');
        } else {
          // Real app usage - use DB values (source of truth)
          combinedDailyMinutes = dbCombinedDaily;
          combinedSessionMinutes = dbCombinedSession;
          print('📊 Combined usage for $category: ${combinedDailyMinutes}min daily, ${combinedSessionMinutes}min session (SAME AS FRONTEND - accounting for inactivity)');
        }
      } catch (e) {
        print('⚠️ Error calculating combined usage: $e - using per-category values');
        // Use per-category values as fallback
        combinedDailyMinutes = dailyUsageMinutes;
        combinedSessionMinutes = sessionUsageMinutes;
      }
    }
    // ✅ CRITICAL: Check Emergency Override FIRST - if active, NEVER lock
    final isEmergencyActive = await EmergencyService.isEmergencyActive();
    final isOverrideEnabled = AppState().isOverrideEnabled;
    if (isEmergencyActive || isOverrideEnabled) {
      print("🚨 Emergency Override: ACTIVE - Skipping all lock checks");
      return {
        'shouldLock': false,
        'source': 'emergency_override',
        'confidence': 1.0,
        'reason': 'Emergency override is active - all restrictions lifted',
        'shouldAskFeedback': false,
      };
    }
    
    // Step 1: ALWAYS enforce safety limits (protect users from extreme overuse)
    // This applies even in learning mode - we collect unbiased data for normal usage,
    // but still protect users from dangerous overuse (6h daily / 2h session)
    // ✅ Use COMBINED usage for monitored categories
    if (_exceedsSafetyLimits(combinedDailyMinutes, combinedSessionMinutes)) {
      String safetyReason;
      if (combinedDailyMinutes >= SAFETY_DAILY_MINUTES && 
          combinedSessionMinutes >= SAFETY_SESSION_MINUTES) {
        safetyReason = 'Combined safety limit exceeded: ${combinedDailyMinutes} min daily and ${combinedSessionMinutes} min session (max: ${SAFETY_DAILY_MINUTES} min daily, ${SAFETY_SESSION_MINUTES} min session)';
      } else if (combinedDailyMinutes >= SAFETY_DAILY_MINUTES) {
        safetyReason = 'Combined safety limit exceeded: ${combinedDailyMinutes} min daily (max: ${SAFETY_DAILY_MINUTES} min/day)';
      } else {
        safetyReason = 'Combined safety limit exceeded: ${combinedSessionMinutes} min session (max: ${SAFETY_SESSION_MINUTES} min/session)';
      }
      
      return {
        'shouldLock': true,
        'source': 'safety_override',
        'confidence': 1.0,
        'reason': safetyReason,
        'shouldAskFeedback': true, // Still collect feedback even for safety locks
      };
    }

    // Step 2: Check user preference (rule-based mode)
    final ruleBasedEnabled = await LearningModeManager.isRuleBasedEnabled();
    if (ruleBasedEnabled) {
      // User chose rule-based mode - use traditional locks
      // ✅ Use COMBINED usage for monitored categories
      final ruleBasedLock = await AppLockManager.shouldLockApp(
        category: category,
        dailyUsageMinutes: combinedDailyMinutes,
        sessionUsageMinutes: combinedSessionMinutes,
        currentHour: currentHour,
      );

      final lockReason = await AppLockManager.getLockReason(
        category: category,
        dailyUsageMinutes: combinedDailyMinutes,
        sessionUsageMinutes: combinedSessionMinutes,
        currentHour: currentHour,
      );

      return {
        'shouldLock': ruleBasedLock,
        'source': 'rule_based',
        'confidence': 1.0,
        'reason': ruleBasedLock ? lockReason : 'Within limits',
        'shouldAskFeedback': ruleBasedLock, // Ask feedback when locked
      };
    }

    // Step 3: Check learning mode (below safety limits, collect unbiased data)
    final learningEnabled = await LearningModeManager.isLearningModeEnabled();
    final phase = await LearningModeManager.getLearningPhase();

    if (learningEnabled && (phase == 'pure_learning' || phase == 'soft_learning')) {
      // Learning mode: No locks, but check for proactive feedback
      final feedbackPrompt = await ProactiveFeedbackService.shouldShowPrompt(
        category: category,
        sessionUsageMinutes: sessionUsageMinutes,
        dailyUsageMinutes: dailyUsageMinutes,
      );

      return {
        'shouldLock': false,  // ❌ NO LOCKS in learning mode
        'source': phase == 'pure_learning' ? 'pure_learning' : 'soft_learning',
        'confidence': 0.0,
        'reason': 'Learning mode: Collecting unbiased data (no locks)',
        'shouldAskFeedback': feedbackPrompt['shouldShow'] as bool,
        'feedbackUsageLevel': feedbackPrompt['usageLevel'] as int?,
      };
    }

    // Step 4: ML is ready - use ensemble model
    final mlReady = await _checkMLReadiness();
    if (mlReady) {
      try {
        // Initialize ensemble if needed
        await EnsembleModelService.initialize();
        
        // ✅ CRITICAL: Verify model is actually trained before using it
        final ensembleStats = await EnsembleModelService.getModelStats();
        final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
        final trainingDataCount = userModelStats['trainingDataCount'] as int? ?? 0;
        
        if (trainingDataCount < MIN_FEEDBACK_FOR_ML) {
          print('⚠️ Model not fully trained (${trainingDataCount} < ${MIN_FEEDBACK_FOR_ML} samples), using rule-based');
          // Fall through to rule-based
        } else {
          // Get ensemble prediction
          // ✅ Use COMBINED usage for monitored categories (ML model will learn combined patterns)
          final ensembleResult = await EnsembleModelService.predict(
            category: category,
            dailyUsageMinutes: combinedDailyMinutes,
            sessionUsageMinutes: combinedSessionMinutes,
            timeOfDay: currentHour,
          );

          // ✅ NULL SAFETY: Validate ensemble result
          if (ensembleResult.isEmpty) {
            print('⚠️ Empty ensemble result, falling back to rule-based');
            // Explicitly fall through to rule-based
          } else {
            // ✅ CRITICAL: Safe type casting with validation
            final ensembleConfidence = (ensembleResult['confidence'] as num?)?.toDouble() ?? 0.0;
            final shouldLock = ensembleResult['shouldLock'] as bool? ?? false;
            final source = ensembleResult['source'] as String? ?? 'ensemble';
            final reason = ensembleResult['reason'] as String? ?? 'Ensemble prediction';
            final ruleBasedWeight = (ensembleResult['ruleBasedWeight'] as num?)?.toDouble() ?? 0.5;
            final userTrainedWeight = (ensembleResult['userTrainedWeight'] as num?)?.toDouble() ?? 0.5;
            
            // ✅ CRITICAL: Validate confidence is valid (not NaN/Infinity)
            if (ensembleConfidence.isNaN || ensembleConfidence.isInfinite) {
              print('⚠️ Invalid ensemble confidence (NaN/Infinity), using rule-based');
              // Fall through to rule-based
            } else if (ensembleConfidence >= MIN_ML_CONFIDENCE) {
              // ✅ ENHANCED LOGGING: Detailed ML decision for verification
              print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
              print('✅ ML LOCK DECISION (ENSEMBLE MODEL)');
              print('   Category: $category');
              print('   Decision: ${shouldLock ? "🔒 LOCK" : "✅ NO LOCK"}');
              print('   Confidence: ${(ensembleConfidence * 100).toStringAsFixed(1)}%');
              print('   Weights: Rule-based=${(ruleBasedWeight * 100).toStringAsFixed(0)}%, ML=${(userTrainedWeight * 100).toStringAsFixed(0)}%');
              print('   Usage: ${combinedDailyMinutes}min daily, ${combinedSessionMinutes}min session');
              print('   Source: $source');
              print('   Reason: $reason');
              print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
              return {
                'shouldLock': shouldLock,
                'source': source,
                'confidence': ensembleConfidence,
                'reason': reason,
                'shouldAskFeedback': shouldLock,
                'ruleBasedWeight': ruleBasedWeight,
                'userTrainedWeight': userTrainedWeight,
              };
            } else {
              print('⚠️ Ensemble confidence too low (${(ensembleConfidence * 100).toStringAsFixed(1)}% < ${(MIN_ML_CONFIDENCE * 100).toStringAsFixed(0)}%), using rule-based');
              // Fall through to rule-based
            }
          }
        }
      } catch (e, stackTrace) {
        print('⚠️ Ensemble prediction error: $e');
        print('Stack trace: $stackTrace');
        // ✅ SAFE FALLBACK: Continue to rule-based
      }
    }

    // Step 5: Fallback to rule-based (safety net)
    // ✅ RELIABLE: Rule-based locking always works, even if ML fails
    // ✅ Use COMBINED usage for monitored categories
    try {
      final ruleBasedLock = await AppLockManager.shouldLockApp(
        category: category,
        dailyUsageMinutes: combinedDailyMinutes,
        sessionUsageMinutes: combinedSessionMinutes,
        currentHour: currentHour,
      );

      final lockReason = await AppLockManager.getLockReason(
        category: category,
        dailyUsageMinutes: combinedDailyMinutes,
        sessionUsageMinutes: combinedSessionMinutes,
        currentHour: currentHour,
      );

      // ✅ ENHANCED LOGGING: Rule-based fallback decision
      if (ruleBasedLock) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('✅ RULE-BASED LOCK DECISION (FALLBACK)');
        print('   Category: $category');
        print('   Decision: 🔒 LOCK');
        print('   Usage: ${combinedDailyMinutes}min daily, ${combinedSessionMinutes}min session');
        print('   Reason: $lockReason');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
      
      return {
        'shouldLock': ruleBasedLock,
        'source': 'rule_based',
        'confidence': 1.0,
        'reason': ruleBasedLock ? lockReason : 'Within limits',
        'shouldAskFeedback': ruleBasedLock, // ✅ Always ask feedback when locked
      };
    } catch (e, stackTrace) {
      print('⚠️ Error in rule-based fallback: $e');
      print('Stack trace: $stackTrace');
      // ✅ CRITICAL FALLBACK: If rule-based fails, use safety limits as last resort
      // ✅ Use COMBINED usage for monitored categories
      try {
        final safetyLock = _exceedsSafetyLimits(combinedDailyMinutes, combinedSessionMinutes);
        return {
          'shouldLock': safetyLock,
          'source': 'safety_override',
          'confidence': 1.0,
          'reason': safetyLock 
              ? 'Combined safety limit exceeded (${combinedDailyMinutes} min daily, ${combinedSessionMinutes} min session)'
              : 'Within limits',
          'shouldAskFeedback': safetyLock,
        };
      } catch (safetyError) {
        // ✅ FINAL FALLBACK: If even safety check fails, default to no lock (safest option)
        print('❌ CRITICAL: Even safety limit check failed: $safetyError');
        print('   Defaulting to NO LOCK (safest fallback)');
        return {
          'shouldLock': false,
          'source': 'error_fallback',
          'confidence': 0.0,
          'reason': 'System error - defaulting to no lock',
          'shouldAskFeedback': false,
        };
      }
    }
  }

  /// Get lock reason for display
  /// ✅ SHARED LIMITS: Calculates combined usage for monitored categories
  static Future<String> getLockReason({
    required String category,
    required int dailyUsageMinutes,
    required int sessionUsageMinutes,
    required int currentHour,
  }) async {
    // ✅ Calculate combined usage for monitored categories
    int combinedDailyMinutes = dailyUsageMinutes;
    int combinedSessionMinutes = sessionUsageMinutes;
    
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    if (monitoredCategories.contains(category)) {
      // ✅ CRITICAL FIX: Read daily usage directly from database (source of truth)
      // This ensures accuracy and consistency with frontend (home_page.dart, dashboard_screen.dart)
      final db = DatabaseHelper.instance;
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      combinedDailyMinutes = ((categoryUsage['Social'] ?? 0.0) +
                               (categoryUsage['Games'] ?? 0.0) +
                               (categoryUsage['Entertainment'] ?? 0.0)).round();
      
      // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
      // This ensures lock reason reflects actual accumulated session time with 5-minute inactivity threshold
      combinedSessionMinutes = (await LockStateManager.getCurrentSessionMinutes()).round();
    }
    
    return await AppLockManager.getLockReason(
      category: category,
      dailyUsageMinutes: combinedDailyMinutes,
      sessionUsageMinutes: combinedSessionMinutes,
      currentHour: currentHour,
    );
  }

  /// Get remaining time before lock
  /// ✅ SHARED LIMITS: Calculates combined usage for monitored categories
  static Future<Map<String, int>> getRemainingTime({
    required String category,
    required int dailyUsageMinutes,
    required int sessionUsageMinutes,
    required int currentHour,
  }) async {
    // ✅ Calculate combined usage for monitored categories
    int combinedDailyMinutes = dailyUsageMinutes;
    int combinedSessionMinutes = sessionUsageMinutes;
    
    final monitoredCategories = ['Social', 'Games', 'Entertainment'];
    if (monitoredCategories.contains(category)) {
      // ✅ CRITICAL FIX: Read daily usage directly from database (source of truth)
      // This ensures accuracy and consistency with frontend (home_page.dart, dashboard_screen.dart)
      final db = DatabaseHelper.instance;
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      combinedDailyMinutes = ((categoryUsage['Social'] ?? 0.0) +
                               (categoryUsage['Games'] ?? 0.0) +
                               (categoryUsage['Entertainment'] ?? 0.0)).round();
      
      // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
      // This ensures remaining time reflects actual accumulated session time with 5-minute inactivity threshold
      combinedSessionMinutes = (await LockStateManager.getCurrentSessionMinutes()).round();
    }
    
    return await AppLockManager.getRemainingTime(
      category: category,
      dailyUsageMinutes: combinedDailyMinutes,
      sessionUsageMinutes: combinedSessionMinutes,
      currentHour: currentHour,
    );
  }

  /// Get ML readiness status
  static Future<Map<String, dynamic>> getMLStatus() async {
    final hasEnoughFeedback = await FeedbackLogger.hasEnoughFeedbackForTraining(
      minSamples: MIN_FEEDBACK_FOR_ML,
    );
    
    final feedbackStats = await FeedbackLogger.getStats();
    
    // ✅ CRITICAL FIX: Check EnsembleModelService's user model (not DecisionTreeService)
    await EnsembleModelService.initialize();
    final ensembleStats = await EnsembleModelService.getModelStats();
    final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
    
    return {
      'ml_ready': _mlModelReady,
      'has_enough_feedback': hasEnoughFeedback,
      'feedback_count': feedbackStats['total_feedback'] as int,
      'min_feedback_needed': MIN_FEEDBACK_FOR_ML,
      'model_trained': (userModelStats['trainingDataCount'] as int? ?? 0) >= MIN_FEEDBACK_FOR_ML,
      'model_accuracy': (userModelStats['accuracy'] as num?)?.toDouble() ?? 0.0,
      'current_source': _mlModelReady ? 'ml' : 'rule_based',
    };
  }
}

