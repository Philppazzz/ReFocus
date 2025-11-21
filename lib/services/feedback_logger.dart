import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'ml_training_service.dart';
import 'lock_state_manager.dart';

/// Service for collecting real user feedback on lock decisions
/// This provides REAL labels for ML training (not threshold-based)
class FeedbackLogger {
  static const String _tableName = 'user_feedback';

  /// Initialize feedback table in database
  static Future<void> initialize() async {
    final db = await DatabaseHelper.instance.database;
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        app_name TEXT NOT NULL,
        app_category TEXT NOT NULL,
        package_name TEXT,
        daily_usage_minutes INTEGER NOT NULL,
        session_usage_minutes INTEGER NOT NULL,
        time_of_day INTEGER NOT NULL,
        day_of_week INTEGER NOT NULL,
        was_helpful INTEGER NOT NULL,
        user_override INTEGER NOT NULL,
        lock_reason TEXT,
        prediction_source TEXT,
        model_confidence REAL,
        is_test_data INTEGER DEFAULT 0
      )
    ''');
    
    // ✅ SAFE TESTING: Add is_test_data column if it doesn't exist (for existing databases)
    try {
      await db.execute('ALTER TABLE $_tableName ADD COLUMN is_test_data INTEGER DEFAULT 0');
    } catch (e) {
      // Column already exists, ignore error
    }

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_feedback_timestamp 
      ON $_tableName(timestamp)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_feedback_category 
      ON $_tableName(app_category)
    ''');
  }

  /// Log user feedback when app gets locked
  /// 
  /// ✅ SHARED LIMITS: For monitored categories, calculates COMBINED usage across all 3 categories.
  /// This ensures ML model trains on combined usage patterns (matching actual lock decisions).
  /// 
  /// [wasHelpful]: true if user agrees the lock was helpful, false otherwise
  /// Note: userOverride is deprecated - feedback is for ML training only
  /// [predictionSource]: 'ml' or 'rule_based' - which system made the prediction
  /// [modelConfidence]: ML model confidence (0.0-1.0) if using ML
  static Future<void> logLockFeedback({
    required String appName,
    required String appCategory,
    required int dailyUsageMinutes, // Per-category usage (will be converted to combined if monitored)
    required int sessionUsageMinutes, // Per-category usage (will be converted to combined if monitored)
    required bool wasHelpful,
    String? packageName,
    String? lockReason,
    String predictionSource = 'rule_based',
    double? modelConfidence,
    // Deprecated: userOverride - kept for backward compatibility but always false
    @Deprecated('Feedback is for ML training only, not for unlocking')
    bool userOverride = false,
  }) async {
    try {
      // ✅ VALIDATION: Ensure all required fields are valid
      if (appName.isEmpty || appCategory.isEmpty) {
        print('⚠️ Invalid feedback data: appName=$appName, appCategory=$appCategory');
        throw ArgumentError('App name and category cannot be empty');
      }
      
      // ✅ SHARED LIMITS: Calculate COMBINED usage for monitored categories
      // This ensures ML model learns patterns based on combined usage (matching lock decisions)
      // ✅ CRITICAL: Use getEffectiveSessionUsage() to account for 5-minute inactivity threshold
      // This ensures feedback reflects actual active session (0 if inactive for 5+ minutes)
      int combinedDailyMinutes = dailyUsageMinutes;
      int combinedSessionMinutes = sessionUsageMinutes;
      
      final monitoredCategories = ['Social', 'Games', 'Entertainment'];
      if (monitoredCategories.contains(appCategory)) {
        try {
          // ✅ CRITICAL FIX: Read daily usage directly from database (source of truth)
          // This ensures accuracy and consistency with frontend (home_page.dart, dashboard_screen.dart)
          // Database is updated by UsageService.getUsageStatsWithEvents() which processes Android UsageStats
          final db = DatabaseHelper.instance;
          final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
          combinedDailyMinutes = ((categoryUsage['Social'] ?? 0.0) +
                                   (categoryUsage['Games'] ?? 0.0) +
                                   (categoryUsage['Entertainment'] ?? 0.0)).round();
          
          // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
          // This ensures feedback reflects actual accumulated session time with 5-minute inactivity threshold
          // LockStateManager tracks time in milliseconds and handles combined session across all monitored categories
          combinedSessionMinutes = (await LockStateManager.getCurrentSessionMinutes()).round();
          
          print('📊 Feedback: Combined usage for $appCategory: ${combinedDailyMinutes}min daily, ${combinedSessionMinutes}min session (accounting for inactivity)');
        } catch (e) {
          print('⚠️ Error calculating combined usage: $e - using per-category values');
          // Use per-category values as fallback
        }
      }
      
      // ✅ VALIDATION: Ensure usage values are within reasonable ranges
      if (combinedDailyMinutes < 0 || combinedDailyMinutes > 1440 ||
          combinedSessionMinutes < 0 || combinedSessionMinutes > 1440) {
        print('⚠️ Invalid usage values: daily=$combinedDailyMinutes, session=$combinedSessionMinutes');
        // Clamp values to valid range
        final clampedDaily = combinedDailyMinutes.clamp(0, 1440);
        final clampedSession = combinedSessionMinutes.clamp(0, 1440);
        
        print('   Clamping to valid range: daily=$clampedDaily, session=$clampedSession');
        
        // Use clamped values for logging (COMBINED usage for monitored categories)
        final db = await DatabaseHelper.instance.database;
        final now = DateTime.now();

        await db.insert(_tableName, {
          'timestamp': now.millisecondsSinceEpoch,
          'app_name': appName,
          'app_category': appCategory,
          'package_name': packageName ?? appName, // Use appName as fallback for package
          'daily_usage_minutes': clampedDaily, // ✅ COMBINED for monitored categories
          'session_usage_minutes': clampedSession, // ✅ COMBINED for monitored categories
          'time_of_day': now.hour,
          'day_of_week': now.weekday,
          'was_helpful': wasHelpful ? 1 : 0,
          'user_override': 0, // Always false - feedback is for ML training only
          'lock_reason': lockReason ?? '',
          'prediction_source': predictionSource,
          'model_confidence': modelConfidence,
        });
      } else {
        // ✅ All data is valid - log normally
        final db = await DatabaseHelper.instance.database;
        final now = DateTime.now();

        await db.insert(_tableName, {
          'timestamp': now.millisecondsSinceEpoch,
          'app_name': appName,
          'app_category': appCategory,
          'package_name': packageName ?? appName, // Use appName as fallback for package
          'daily_usage_minutes': combinedDailyMinutes, // ✅ COMBINED for monitored categories
          'session_usage_minutes': combinedSessionMinutes, // ✅ COMBINED for monitored categories
          'time_of_day': now.hour,
          'day_of_week': now.weekday,
          'was_helpful': wasHelpful ? 1 : 0,
          'user_override': 0, // Always false - feedback is for ML training only
          'lock_reason': lockReason ?? '',
          'prediction_source': predictionSource,
          'model_confidence': modelConfidence,
        });
      }

      // ✅ SAFEGUARD: Store last feedback ID for undo mechanism
      final db = await DatabaseHelper.instance.database;
      final prefs = await SharedPreferences.getInstance();
      final lastFeedbackId = await db.rawQuery(
        'SELECT id FROM $_tableName ORDER BY timestamp DESC LIMIT 1'
      );
      if (lastFeedbackId.isNotEmpty) {
        final feedbackId = lastFeedbackId.first['id'] as int?;
        if (feedbackId != null) {
          await prefs.setInt('last_feedback_id', feedbackId);
          await prefs.setInt('last_feedback_timestamp', DateTime.now().millisecondsSinceEpoch);
        }
      }
      
      print('✅ Feedback logged: ${wasHelpful ? "Helpful" : "Not Helpful"} | Category: $appCategory | Source: $predictionSource');
    } catch (e, stackTrace) {
      print('❌ Error logging feedback: $e');
      print('Stack trace: $stackTrace');
      // ✅ CRITICAL: Don't throw - feedback logging failure shouldn't crash the app
      // Log the error but don't rethrow - let the app continue normally
      // The caller (LockFeedbackDialog) will handle the error gracefully
    }
    
    // ✅ TRIGGER 1: Immediate training check after feedback
    // This runs in background to avoid blocking UI
    // ✅ CRITICAL: Delay training check slightly to ensure feedback is committed to database first
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final trained = await MLTrainingService.autoRetrainIfNeeded();
        if (trained) {
          print('✅ Model trained immediately after feedback');
        }
      } catch (e) {
        print('⚠️ Auto-training check failed: $e');
        // Don't throw - feedback logging should succeed even if training fails
      }
    });
    
    // ✅ TRIGGER 2: Milestone-based training check
    // Check if we reached a feedback milestone (100, 200, 500, etc.)
    final stats = await getStats();
    final totalFeedback = stats['total_feedback'] as int;
    final milestones = [100, 200, 500, 1000, 2000, 5000];
    
    for (final milestone in milestones) {
      if (totalFeedback == milestone) {
        // Just reached milestone - trigger training
        Future.delayed(const Duration(seconds: 2), () async {
          try {
            await MLTrainingService.autoRetrainIfNeeded();
            print('✅ Model trained after reaching $milestone feedback milestone');
          } catch (e) {
            print('⚠️ Milestone training check failed: $e');
          }
        });
        break; // Only trigger once per milestone
      }
    }
  }

  /// Get feedback statistics
  /// ✅ CRITICAL: Excludes test data (is_test_data = 1) to prevent affecting real app statistics
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // ✅ CRITICAL FIX: Exclude test data from statistics (only count real feedback)
      // This ensures test data doesn't affect helpfulness rate, ML readiness checks, etc.
      final total = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE (is_test_data = 0 OR is_test_data IS NULL)')
      ) ?? 0;
      
      final helpful = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE was_helpful = 1 AND (is_test_data = 0 OR is_test_data IS NULL)')
      ) ?? 0;
      
      final mlPredictions = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE prediction_source = ? AND (is_test_data = 0 OR is_test_data IS NULL)', ['ml'])
      ) ?? 0;

      // ✅ COUNT BREAKDOWN: Get counts by feedback source for transparency
      final proactiveCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE prediction_source IN (?, ?, ?) AND (is_test_data = 0 OR is_test_data IS NULL)', ['rule_based', 'ml', 'learning_mode'])
      ) ?? 0;
      
      final passiveCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE prediction_source = ? AND (is_test_data = 0 OR is_test_data IS NULL)', ['passive_learning'])
      ) ?? 0;
      
      return {
        'total_feedback': total, // ✅ INCLUDES BOTH: Proactive + Passive learning samples
        'proactive_feedback': proactiveCount, // User-prompted feedback (from lock dialogs)
        'passive_feedback': passiveCount, // Automatic samples (from natural app closes/switches)
        'helpful_locks': helpful,
        'user_overrides': 0, // Deprecated - always 0
        'helpfulness_rate': total > 0 ? (helpful / total * 100) : 0.0,
        'override_rate': 0.0, // Deprecated - always 0 (feedback is for ML training only)
        'ml_predictions': mlPredictions,
        'rule_based_predictions': total - mlPredictions,
      };
    } catch (e) {
      print('⚠️ Error getting feedback stats: $e');
      // ✅ SAFE FALLBACK: Return zeros if database error
      return {
        'total_feedback': 0,
        'helpful_locks': 0,
        'user_overrides': 0,
        'helpfulness_rate': 0.0,
        'override_rate': 0.0,
        'ml_predictions': 0,
        'rule_based_predictions': 0,
      };
    }
  }

  /// Check if we have enough feedback to train ML model
  /// ✅ CRITICAL: Default is 300 (matches MIN_FEEDBACK_FOR_ML in HybridLockManager)
  /// Returns true if we have enough feedback samples
  static Future<bool> hasEnoughFeedbackForTraining({int minSamples = 300}) async {
    final stats = await getStats();
    return (stats['total_feedback'] as int) >= minSamples;
  }

  /// Export feedback data for ML training
  /// Returns complete dataset with all required columns for training
  /// 
  /// ✅ SHARED LIMITS: For monitored categories (Social, Games, Entertainment),
  /// daily_usage_minutes and session_usage_minutes are COMBINED across all 3 categories.
  /// This matches the actual lock decision logic (shared limits system).
  /// 
  /// ✅ COMPLETE DATASET STRUCTURE (Rows & Columns):
  /// Each row contains:
  /// - category: App category (Social, Games, Entertainment, Others)
  /// - daily_usage_minutes: COMBINED daily usage for monitored categories, per-category for Others (INTEGER)
  /// - session_usage_minutes: COMBINED session usage for monitored categories, per-category for Others (INTEGER)
  /// - time_of_day: Hour of day 0-23 (INTEGER)
  /// - day_of_week: Day of week 1-7 (INTEGER, kept for future use)
  /// - should_lock: Label from user feedback (1=Yes/Helpful, 0=No/Not Helpful) (INTEGER)
  /// - timestamp: When feedback was collected (INTEGER, milliseconds)
  /// - prediction_source: Which system made prediction (rule_based/ml/learning_mode) (STRING)
  /// 
  /// This dataset is ready for conversion to TrainingData format:
  /// TrainingData(categoryInt, dailyUsageMins, sessionUsageMins, timeOfDay, overuse)
  static Future<List<Map<String, dynamic>>> exportFeedbackForTraining() async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      // ✅ QUERY: Get all feedback with complete columns
      // ✅ CRITICAL: Exclude test data from real training (is_test_data = 0 or NULL)
      // ✅ CRITICAL: Wrap query in try-catch to handle database errors
      final results = await db.query(
        _tableName,
        columns: [
          'app_category',
          'daily_usage_minutes',
          'session_usage_minutes',
          'time_of_day',
          'day_of_week',
          'was_helpful',
          'timestamp',
          'prediction_source',
        ],
        where: '(is_test_data = 0 OR is_test_data IS NULL)',
        orderBy: 'timestamp DESC',
      );


    // ✅ CONVERT: Transform database rows to complete training dataset
    // Each row has all required columns for decision tree training
    // ✅ CRITICAL: Safe type casting with null checks to prevent crashes
    final trainingDataset = <Map<String, dynamic>>[];
    for (final row in results) {
      try {
        // ✅ SAFE TYPE CASTING: Handle null values gracefully
        final category = row['app_category'] as String?;
        final dailyMins = (row['daily_usage_minutes'] as num?)?.toInt();
        final sessionMins = (row['session_usage_minutes'] as num?)?.toInt();
        final timeOfDay = (row['time_of_day'] as num?)?.toInt();
        final dayOfWeek = (row['day_of_week'] as num?)?.toInt();
        final wasHelpful = (row['was_helpful'] as num?)?.toInt();
        final timestamp = (row['timestamp'] as num?)?.toInt();
        final predictionSource = row['prediction_source'] as String?;
        
        // ✅ VALIDATION: Skip rows with null or invalid values
        if (category == null || category.isEmpty ||
            dailyMins == null || sessionMins == null ||
            timeOfDay == null || dayOfWeek == null ||
            wasHelpful == null || timestamp == null) {
          print('⚠️ Skipping invalid feedback row: missing or null required fields');
          continue;
        }
        
        // ✅ VALIDATION: Ensure values are within reasonable ranges
        if (dailyMins < 0 || dailyMins > 1440 ||
            sessionMins < 0 || sessionMins > 1440 ||
            timeOfDay < 0 || timeOfDay > 23 ||
            dayOfWeek < 1 || dayOfWeek > 7 ||
            wasHelpful < 0 || wasHelpful > 1) {
          print('⚠️ Skipping invalid feedback row: out of range values');
          continue;
        }
        
        // ✅ SAFETY LIMIT FILTERING: Exclude high violations (6h daily, 2h continuous)
        // These are hard limits that always trigger locks - not useful for ML training
        // ML should learn from normal usage patterns, not extreme violations
        // Safety limits are enforced for protection, but training data should focus on normal behavior
        const int SAFETY_DAILY_MINUTES = 360;   // 6 hours/day maximum
        const int SAFETY_SESSION_MINUTES = 120;  // 2 hours/session maximum
        
        if (dailyMins >= SAFETY_DAILY_MINUTES || sessionMins >= SAFETY_SESSION_MINUTES) {
          print('⚠️ Skipping safety limit violation: ${dailyMins}min daily, ${sessionMins}min session (exceeds safety limits - not useful for training)');
          continue; // Skip this feedback - safety limits always lock, no learning value
        }
        
        // ✅ CRITICAL FIX: Handle label semantics correctly for different feedback sources
        // - Proactive feedback: wasHelpful=1 means "lock was helpful" → should_lock=1 (Yes)
        // - Passive learning: wasHelpful=1 means "satisfied, no lock needed" → should_lock=0 (No)
        // The label semantics are inverted for passive learning, so we need to invert it
        int shouldLockLabel;
        if (predictionSource == 'passive_learning') {
          // Passive learning: Natural stop = satisfied = no lock needed
          // wasHelpful=1 (satisfied) → should_lock=0 (No lock needed)
          // wasHelpful=0 (not satisfied) → should_lock=1 (Lock needed) - but this shouldn't happen in passive learning
          shouldLockLabel = wasHelpful == 1 ? 0 : 1; // Invert for passive learning
        } else {
          // Proactive feedback: User explicitly says if lock was helpful
          // wasHelpful=1 (lock was helpful) → should_lock=1 (Yes, lock needed)
          // wasHelpful=0 (lock was not helpful) → should_lock=0 (No, lock not needed)
          shouldLockLabel = wasHelpful; // Keep as-is for proactive feedback
        }
        
        trainingDataset.add({
          'category': category,
          'daily_usage_minutes': dailyMins,
          'session_usage_minutes': sessionMins,
          'time_of_day': timeOfDay,
          'day_of_week': dayOfWeek,
          'should_lock': shouldLockLabel, // ✅ CORRECTED: Properly converted label based on feedback source
          'timestamp': timestamp,
          'prediction_source': predictionSource ?? 'rule_based',
        });
      } catch (e) {
        print('⚠️ Error processing feedback row: $e - skipping');
        continue;
      }
    }

      print('✅ Dataset exported: ${trainingDataset.length} complete rows with all columns');
      print('   Columns: [category, daily_usage_minutes, session_usage_minutes, time_of_day, day_of_week, should_lock, timestamp, prediction_source]');
      return trainingDataset;
    } catch (e, stackTrace) {
      print('❌ Error exporting feedback for training: $e');
      print('Stack trace: $stackTrace');
      // ✅ CRITICAL: Return empty list instead of crashing
      // This allows training to fail gracefully with "not enough data" message
      return [];
    }
  }

  /// Get feedback count by category
  /// ✅ CRITICAL: Excludes test data (is_test_data = 1) to prevent affecting real app statistics
  static Future<Map<String, int>> getFeedbackByCategory() async {
    final db = await DatabaseHelper.instance.database;
    
    // ✅ CRITICAL FIX: Exclude test data from category counts
    final results = await db.rawQuery('''
      SELECT app_category, COUNT(*) as count 
      FROM $_tableName 
      WHERE (is_test_data = 0 OR is_test_data IS NULL)
      GROUP BY app_category
    ''');

    final Map<String, int> categoryCounts = {};
    for (final row in results) {
      categoryCounts[row['app_category'] as String] = row['count'] as int;
    }

    return categoryCounts;
  }

  /// ✅ SAFEGUARD 3: Undo last feedback (within 30 seconds)
  /// Allows user to correct accidental clicks
  static Future<bool> undoLastFeedback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastFeedbackId = prefs.getInt('last_feedback_id');
      final lastFeedbackTimestamp = prefs.getInt('last_feedback_timestamp');
      
      if (lastFeedbackId == null || lastFeedbackTimestamp == null) {
        print('⚠️ No recent feedback to undo');
        return false;
      }
      
      // Check if feedback is within 30 seconds
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceFeedback = (now - lastFeedbackTimestamp) / 1000;
      
      if (timeSinceFeedback > 30) {
        print('⚠️ Feedback is too old to undo (${timeSinceFeedback.toStringAsFixed(0)}s ago, max 30s)');
        return false;
      }
      
      // Delete the feedback entry
      final db = await DatabaseHelper.instance.database;
      final deleted = await db.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [lastFeedbackId],
      );
      
      if (deleted > 0) {
        // Clear undo tracking
        await prefs.remove('last_feedback_id');
        await prefs.remove('last_feedback_timestamp');
        print('✅ Feedback undone: ID $lastFeedbackId');
        return true;
      } else {
        print('⚠️ Feedback not found: ID $lastFeedbackId');
        return false;
      }
    } catch (e) {
      print('❌ Error undoing feedback: $e');
      return false;
    }
  }

  /// Get feedback since a specific date for a category
  /// Used by adaptive threshold manager to evaluate user behavior
  /// ✅ CRITICAL: Excludes test data (is_test_data = 1) to prevent affecting real app metrics
  static Future<List<Map<String, dynamic>>> getFeedbackSince(
    DateTime since,
    String category,
  ) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final sinceTimestamp = since.millisecondsSinceEpoch;
      
      // ✅ CRITICAL FIX: Exclude test data from feedback queries
      final results = await db.query(
        _tableName,
        where: 'timestamp >= ? AND app_category = ? AND (is_test_data = 0 OR is_test_data IS NULL)',
        whereArgs: [sinceTimestamp, category],
        orderBy: 'timestamp DESC',
      );
      
      return results;
    } catch (e) {
      print('⚠️ Error getting feedback since date: $e');
      return [];
    }
  }

  /// Clear old feedback (keep last N days)
  static Future<void> clearOldFeedback({int keepDays = 90}) async {
    final db = await DatabaseHelper.instance.database;
    final cutoff = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    
    await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}

