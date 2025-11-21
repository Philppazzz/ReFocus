import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/app_lock_manager.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';

/// Passive Learning Service
/// Learns from user behavior WITHOUT asking for feedback
/// Uses conservative inference to avoid bias and errors
class PassiveLearningService {
  // Minimum session length to infer "satisfied" (avoid noise from very short sessions)
  static const int MIN_SESSION_MINUTES_FOR_INFERENCE = 10;
  
  // Maximum session length to consider "natural" (beyond this might be forced/interrupted)
  static const int MAX_NATURAL_SESSION_MINUTES = 180; // 3 hours
  
  // Minimum time between app close and reopen to consider it a "natural stop"
  // If user reopens app within this time, it's likely not a natural stop
  static const int MIN_STOP_DURATION_MINUTES = 5;
  
  // Track recent app closes to avoid duplicate inference
  static final Map<String, int> _recentCloses = {}; // packageName -> timestamp
  
  // Track app reopen times to detect forced closes
  static final Map<String, int> _appReopenTimes = {}; // packageName -> timestamp
  
  /// Called when user closes an app or switches away
  /// Infers "satisfied" label conservatively
  static Future<void> onAppClosed({
    required String packageName,
    required String category,
    required int sessionMinutes,
    required int dailyUsageMinutes,
    String? appName,
  }) async {
    try {
      // ✅ SAFEGUARD 1: Only in learning mode
      final isLearningMode = await LearningModeManager.shouldShowProactiveFeedback();
      if (!isLearningMode) {
        return; // Don't learn when rule-based mode is active
      }
      
      // ✅ SAFEGUARD 2: Only for monitored categories
      if (category == 'Others') {
        return; // Don't learn from "Others" category
      }
      
      // ✅ SAFEGUARD 3: Minimum session length (avoid noise)
      if (sessionMinutes < MIN_SESSION_MINUTES_FOR_INFERENCE) {
        print('📊 Passive learning: Session too short ($sessionMinutes min < $MIN_SESSION_MINUTES_FOR_INFERENCE min) - skipping');
        return;
      }
      
      // ✅ SAFEGUARD 4: Maximum natural session (beyond this might be forced)
      if (sessionMinutes > MAX_NATURAL_SESSION_MINUTES) {
        print('📊 Passive learning: Session too long ($sessionMinutes min > $MAX_NATURAL_SESSION_MINUTES min) - might be forced, skipping');
        return;
      }
      
      // ✅ SAFEGUARD 5: Check if user reopened app quickly (forced close, not natural)
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastReopen = _appReopenTimes[packageName];
      if (lastReopen != null) {
        final minutesSinceReopen = (now - lastReopen) / 1000 / 60;
        if (minutesSinceReopen < MIN_STOP_DURATION_MINUTES) {
          print('📊 Passive learning: User reopened app too quickly ($minutesSinceReopen min < $MIN_STOP_DURATION_MINUTES min) - likely forced close, skipping');
          return;
        }
      }
      
      // ✅ SAFEGUARD 6: Avoid duplicate inference (same app close within 30 min)
      final lastClose = _recentCloses[packageName];
      if (lastClose != null) {
        final minutesSinceLastClose = (now - lastClose) / 1000 / 60;
        if (minutesSinceLastClose < 30) {
          print('📊 Passive learning: Duplicate close detected (${minutesSinceLastClose.toStringAsFixed(1)} min ago) - skipping');
          return;
        }
      }
      
      // ✅ SAFEGUARD 7: Check if usage was near limits (might be forced by limit, not natural)
      final thresholds = await AppLockManager.getThresholds(category);
      final dailyLimit = thresholds['daily']!;
      final sessionLimit = thresholds['session']!;
      
      final dailyPercentage = dailyUsageMinutes / dailyLimit;
      final sessionPercentage = sessionMinutes / sessionLimit;
      
      // If user was very close to limit (95%+), might have been forced, not natural
      if (dailyPercentage >= 0.95 || sessionPercentage >= 0.95) {
        print('📊 Passive learning: Usage near limit (daily: ${(dailyPercentage * 100).toStringAsFixed(0)}%, session: ${(sessionPercentage * 100).toStringAsFixed(0)}%) - might be forced, skipping');
        return;
      }
      
      // ✅ CONSERVATIVE INFERENCE: User closed app naturally
      // This means they were satisfied with this usage level
      // Label: wasHelpful = true (they stopped naturally, so no lock was needed)
      
      final finalAppName = appName ?? packageName;
      
      await FeedbackLogger.logLockFeedback(
        appName: finalAppName,
        appCategory: category,
        dailyUsageMinutes: dailyUsageMinutes,
        sessionUsageMinutes: sessionMinutes,
        wasHelpful: true, // ✅ Natural stop = satisfied = no lock needed
        packageName: packageName,
        lockReason: 'Natural stop (passive learning)',
        predictionSource: 'passive_learning',
        modelConfidence: null,
      );
      
      // Track this close to avoid duplicates
      _recentCloses[packageName] = now;
      
      print('✅ Passive learning: Inferred "satisfied" from natural stop - $finalAppName ($sessionMinutes min session, $dailyUsageMinutes min daily)');
      
    } catch (e) {
      print('⚠️ Error in passive learning: $e');
      // Don't throw - passive learning should never break the app
    }
  }
  
  /// Called when user reopens an app
  /// Tracks reopen time to detect forced closes
  static Future<void> onAppReopened(String packageName) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      _appReopenTimes[packageName] = now;
      
      // Clean up old reopen times (older than 1 hour)
      final cutoff = now - (60 * 60 * 1000);
      _appReopenTimes.removeWhere((_, timestamp) => timestamp < cutoff);
      
    } catch (e) {
      print('⚠️ Error tracking app reopen: $e');
    }
  }
  
  /// Called when user switches between apps
  /// Can infer satisfaction if switch is natural (not forced)
  static Future<void> onAppSwitch({
    required String fromPackageName,
    required String toPackageName,
    required String fromCategory,
    required String toCategory,
    required int fromSessionMinutes,
    required int fromDailyUsageMinutes,
    String? fromAppName,
  }) async {
    try {
      // Only infer if switching from monitored category to different category
      // (switching within same category might be multitasking, not satisfaction)
      if (fromCategory == toCategory) {
        return; // Same category switch - likely multitasking, not satisfaction
      }
      
      // Only infer if switching away from monitored category
      if (fromCategory == 'Others') {
        return; // Don't learn from "Others" category
      }
      
      // Use same safeguards as app close
      await onAppClosed(
        packageName: fromPackageName,
        category: fromCategory,
        sessionMinutes: fromSessionMinutes,
        dailyUsageMinutes: fromDailyUsageMinutes,
        appName: fromAppName,
      );
      
    } catch (e) {
      print('⚠️ Error in passive learning (app switch): $e');
    }
  }
  
  /// Clean up old tracking data (call daily)
  static Future<void> cleanup() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - (60 * 60 * 1000); // 1 hour ago
      
      _recentCloses.removeWhere((_, timestamp) => timestamp < cutoff);
      _appReopenTimes.removeWhere((_, timestamp) => timestamp < cutoff);
      
      print('✅ Passive learning: Cleaned up old tracking data');
    } catch (e) {
      print('⚠️ Error cleaning up passive learning data: $e');
    }
  }
  
  /// Get statistics about passive learning
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final db = await FeedbackLogger.exportFeedbackForTraining();
      
      final passiveLearningData = db.where((entry) => 
        entry['prediction_source'] == 'passive_learning'
      ).toList();
      
      return {
        'total_passive_samples': passiveLearningData.length,
        'total_feedback_samples': db.length,
        'passive_percentage': db.isNotEmpty ? (passiveLearningData.length / db.length * 100) : 0.0,
      };
    } catch (e) {
      print('⚠️ Error getting passive learning stats: $e');
      return {
        'total_passive_samples': 0,
        'total_feedback_samples': 0,
        'passive_percentage': 0.0,
      };
    }
  }
}

