import 'dart:async';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/app_lock_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for proactive feedback prompts (not just when locked)
/// Asks for feedback at various usage levels to collect unbiased data
/// Now includes smart overuse detection for faster learning
class ProactiveFeedbackService {
  // Usage levels to prompt feedback (increased for more data collection)
  // More granular levels to collect feedback at various usage points
  static const List<int> PROMPT_LEVELS = [20, 40, 60, 90, 120, 150];  // minutes
  
  // Cooldown between prompts (reduced for more frequent feedback)
  static const int PROMPT_COOLDOWN_MINUTES = 8;  // 15 → 8 minutes
  
  // Daily limit: Max 6 prompts per category per day (increased for maximum feedback)
  static const int MAX_PROMPTS_PER_CATEGORY_PER_DAY = 6;  // 2 → 6
  
  // Minimum session activity before prompting (avoid prompting immediately)
  static const int MIN_SESSION_ACTIVITY_MINUTES = 5;
  
  // Overuse detection thresholds (percentage of limit)
  // ✅ CRITICAL: More thresholds for comprehensive coverage (faster ML learning)
  // Ask for feedback when approaching limits (smart detection)
  // Added 40%, 60%, 70% for earlier and more frequent feedback collection
  static const List<double> OVERUSE_THRESHOLDS = [0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95];  // 40%, 50%, 60%, 70%, 80%, 90%, 95%
  
  // Track last prompt time per category
  static final Map<String, int> _lastPromptTime = {};

  /// Check if we should show a proactive feedback prompt
  /// Returns: {shouldShow: bool, usageLevel: int?, reason: String?, isOveruse: bool?}
  /// Now includes smart overuse detection for faster learning
  static Future<Map<String, dynamic>> shouldShowPrompt({
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
  }) async {
    // Only in learning mode
    final shouldShow = await LearningModeManager.shouldShowProactiveFeedback();
    if (!shouldShow) {
      return {'shouldShow': false, 'reason': 'Not in learning mode'};
    }

    // Check minimum session activity (avoid prompting immediately)
    if (sessionUsageMinutes < MIN_SESSION_ACTIVITY_MINUTES) {
      return {'shouldShow': false, 'reason': 'Session too short'};
    }

    // Check cooldown
    final lastPrompt = _lastPromptTime[category] ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minutesSinceLastPrompt = (now - lastPrompt) / 1000 / 60;
    
    if (minutesSinceLastPrompt < PROMPT_COOLDOWN_MINUTES) {
      return {'shouldShow': false, 'reason': 'Cooldown active'};
    }

    // Check daily limit per category
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final dailyPromptCountKey = 'proactive_prompt_count_${category}_$today';
    final dailyPromptCount = prefs.getInt(dailyPromptCountKey) ?? 0;
    
    if (dailyPromptCount >= MAX_PROMPTS_PER_CATEGORY_PER_DAY) {
      return {'shouldShow': false, 'reason': 'Daily limit reached'};
    }

    // ✅ PRIORITY 1: Smart overuse detection (faster learning)
    // Ask for feedback when approaching limits (70%, 80%, 90%, 95%)
    final overuseResult = await _checkOveruseDetection(
      category: category,
      sessionUsageMinutes: sessionUsageMinutes,
      dailyUsageMinutes: dailyUsageMinutes,
      prefs: prefs,
      today: today,
      dailyPromptCount: dailyPromptCount,
      now: now,
    );
    
    if (overuseResult['shouldShow'] == true) {
      return overuseResult;
    }

    // ✅ PRIORITY 2: Fixed milestones (backup for consistent data collection)
    final promptKey = 'proactive_prompt_${category}_$today';
    final lastPromptedLevel = prefs.getInt(promptKey) ?? 0;

    // Find next prompt level
    for (final level in PROMPT_LEVELS) {
      if (sessionUsageMinutes >= level && lastPromptedLevel < level) {
        // Mark this level as prompted and increment daily count
        await prefs.setInt(promptKey, level);
        await prefs.setInt(dailyPromptCountKey, dailyPromptCount + 1);
        _lastPromptTime[category] = now;
        
        return {
          'shouldShow': true,
          'usageLevel': level,
          'reason': 'Usage reached ${level} minutes',
          'isOveruse': false,
        };
      }
    }

    return {'shouldShow': false, 'reason': 'No prompt level reached'};
  }

  /// Smart overuse detection - ask for feedback when approaching limits
  /// This collects data faster by detecting when user is near thresholds
  static Future<Map<String, dynamic>> _checkOveruseDetection({
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required SharedPreferences prefs,
    required String today,
    required int dailyPromptCount,
    required int now,
  }) async {
    try {
      // Get thresholds for this category
      final thresholds = await AppLockManager.getThresholds(category);
      final dailyLimit = thresholds['daily']!;
      final sessionLimit = thresholds['session']!;
      
      // Apply peak hours adjustment if needed
      final currentHour = DateTime.now().hour;
      int effectiveDailyLimit = dailyLimit;
      int effectiveSessionLimit = sessionLimit;
      
      if (currentHour >= 18 && currentHour <= 23) {
        effectiveDailyLimit = (effectiveDailyLimit * 0.85).round();
        effectiveSessionLimit = (effectiveSessionLimit * 0.85).round();
      }

      // Calculate percentages
      final dailyPercentage = dailyUsageMinutes / effectiveDailyLimit;
      final sessionPercentage = sessionUsageMinutes / effectiveSessionLimit;
      
      // Check which threshold we've crossed (use the higher percentage)
      final maxPercentage = dailyPercentage > sessionPercentage ? dailyPercentage : sessionPercentage;
      final isDailyOveruse = dailyPercentage > sessionPercentage;
      final limitType = isDailyOveruse ? 'daily' : 'session';
      final limitValue = isDailyOveruse ? effectiveDailyLimit : effectiveSessionLimit;
      final usageValue = isDailyOveruse ? dailyUsageMinutes : sessionUsageMinutes;

      // Check if we've already prompted at this overuse level today
      final overusePromptKey = 'overuse_prompt_${category}_$today';
      final lastOveruseThreshold = prefs.getDouble(overusePromptKey) ?? 0.0;

      // Find next overuse threshold
      for (final threshold in OVERUSE_THRESHOLDS) {
        if (maxPercentage >= threshold && lastOveruseThreshold < threshold) {
          // Mark this threshold as prompted and increment daily count
          await prefs.setDouble(overusePromptKey, threshold);
          await prefs.setInt('proactive_prompt_count_${category}_$today', dailyPromptCount + 1);
          _lastPromptTime[category] = now;
          
          return {
            'shouldShow': true,
            'usageLevel': usageValue,
            'reason': 'Approaching ${limitType} limit (${(threshold * 100).toInt()}% - ${usageValue}/${limitValue} min)',
            'isOveruse': true,
            'percentage': threshold,
          };
        }
      }
    } catch (e) {
      print('⚠️ Error in overuse detection: $e');
      // Don't block other prompts if overuse detection fails
    }

    return {'shouldShow': false};
  }

  /// Show proactive feedback prompt (non-blocking notification/dialog)
  /// This asks "Would a break be helpful now?" without locking
  static Future<void> showProactivePrompt({
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required int usageLevel,
  }) async {
    // This will be called from UI layer
    // For now, just log that we should show a prompt
    print('📊 Proactive feedback prompt: $appName at $usageLevel min (Category: $category)');
    
    // The actual UI prompt will be handled by the calling code
    // This service just determines when to show it
  }

  /// Log feedback from proactive prompt (user wasn't locked, just asked)
  static Future<void> logProactiveFeedback({
    required String appName,
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
    required bool wouldBeHelpful,  // User's answer: "Yes, break helpful" or "No, continue"
    String? packageName,
  }) async {
    await FeedbackLogger.logLockFeedback(
      appName: appName,
      appCategory: category,
      dailyUsageMinutes: dailyUsageMinutes,
      sessionUsageMinutes: sessionUsageMinutes,
      wasHelpful: wouldBeHelpful,  // User's opinion
      packageName: packageName,
      lockReason: 'Proactive feedback: ${sessionUsageMinutes} min session, ${dailyUsageMinutes} min daily',
      predictionSource: 'learning_mode',
      modelConfidence: null,
    );

    print('✅ Proactive feedback logged: ${wouldBeHelpful ? "Break helpful" : "Continue OK"}');
  }

  /// Check if user naturally stopped (for feedback collection)
  static Future<void> checkNaturalStop({
    required String category,
    required int sessionUsageMinutes,
    required int dailyUsageMinutes,
  }) async {
    // This can be called when user switches apps or closes app
    // Ask: "Was that a good stopping point?"
    // This helps learn natural usage patterns
    
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastNaturalStopPrompt = prefs.getInt('natural_stop_prompt_${category}_$today') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Only prompt once per day per category, and only if session was significant (>20 min)
    if (sessionUsageMinutes >= 20 && 
        (now - lastNaturalStopPrompt) > (60 * 60 * 1000)) {  // 1 hour cooldown
      
      await prefs.setInt('natural_stop_prompt_${category}_$today', now);
      
      // This will trigger a prompt in UI
      print('📊 Natural stop detected: $category at $sessionUsageMinutes min');
    }
  }

  /// Reset daily prompt tracking
  static Future<void> resetDailyTracking() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final keys = prefs.getKeys();
    
    for (final key in keys) {
      if (key.startsWith('proactive_prompt_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
      if (key.startsWith('overuse_prompt_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
      if (key.startsWith('proactive_prompt_count_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
      if (key.startsWith('natural_stop_prompt_') && !key.endsWith(today)) {
        await prefs.remove(key);
      }
    }
    
    _lastPromptTime.clear();
  }
}

