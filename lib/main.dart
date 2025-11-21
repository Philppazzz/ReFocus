import 'dart:async';
import 'package:flutter/material.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/screens/onboarding_screen.dart';
import 'package:refocus_app/pages/home_page.dart';
import 'package:refocus_app/services/notification_service.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/feedback_abuse_prevention.dart';
import 'package:refocus_app/services/ml_training_service.dart';
import 'package:refocus_app/services/ensemble_model_service.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';
import 'package:refocus_app/services/passive_learning_service.dart';
import 'package:refocus_app/services/adaptive_threshold_manager.dart';
import 'package:refocus_app/widgets/lock_feedback_dialog.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ LONG-TERM RELIABILITY: Clean old SharedPreferences keys with date suffixes
/// Removes keys older than 7 days to prevent accumulation over time
/// This is a safety measure - day change handlers already clean most keys
Future<void> _cleanOldSharedPreferencesKeys(SharedPreferences prefs) async {
  try {
    final now = DateTime.now();
    final cutoffDate = now.subtract(const Duration(days: 7));
    final allKeys = prefs.getKeys();
    int cleanedCount = 0;
    
    // Patterns for date-suffixed keys that should be cleaned
    final datePatterns = [
      'session_start_',
      'last_activity_',
      'session_accumulated_ms_',
      'per_app_usage_',
      'per_app_unlocks_',
      'per_app_longest_',
      'processed_',
      'active_app_',
      'active_start_',
      'active_recorded_',
      'session_violations_',
      'unlock_violations_',
      'last_session_violation_',
      'last_unlock_violation_',
      'unlock_base_',
      'daily_warning_50_',
      'daily_warning_75_',
      'daily_warning_90_',
      'daily_final_warning_',
      'session_warning_50_',
      'session_warning_75_',
      'session_warning_90_',
      'session_final_warning_',
      'unlock_warning_50_',
      'unlock_warning_75_',
      'unlock_warning_90_',
      'unlock_final_warning_',
      'daily_warning_sent_',
      'session_warning_sent_',
      'unlock_warning_sent_',
      'last_break_end_',
      'daily_usage_social_',
      'daily_usage_games_',
      'daily_usage_entertainment_',
      'daily_usage_others_',
      'session_usage_social_',
      'session_usage_games_',
      'session_usage_entertainment_',
      'session_usage_others_',
      'violation_count_',
    ];
    
    for (final key in allKeys) {
      // Check if key matches any date pattern
      bool shouldClean = false;
      
      for (final pattern in datePatterns) {
        if (key.startsWith(pattern)) {
          // Extract date suffix (format: YYYY-MM-DD)
          final suffix = key.substring(pattern.length);
          if (suffix.length == 10 && suffix.contains('-')) {
            try {
              final keyDate = DateTime.parse(suffix);
              if (keyDate.isBefore(cutoffDate)) {
                shouldClean = true;
                break;
              }
            } catch (e) {
              // Not a valid date format - skip
            }
          }
        }
      }
      
      if (shouldClean) {
        await prefs.remove(key);
        cleanedCount++;
      }
    }
    
    if (cleanedCount > 0) {
      print("   🗑️ Removed $cleanedCount old SharedPreferences keys (older than 7 days)");
    } else {
      print("   ℹ️ No old SharedPreferences keys to clean");
    }
  } catch (e) {
    print("   ⚠️ Error cleaning SharedPreferences keys: $e");
    // Don't throw - this is a cleanup operation, shouldn't break app
  }
}

class Nav {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

/// Background task handler - runs even when app is closed
/// This keeps monitoring and enforcement active at all times
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

/// Handler for background monitoring tasks
class BackgroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('🚀 Background task started at $timestamp');
    // Monitoring will be started by MonitorService when app initializes
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This is called periodically by the foreground service
    // The actual monitoring is handled by MonitorService's timer
    // This just keeps the service alive
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool sendPort) async {
    print('🛑 Background task destroyed at $timestamp');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize foreground task
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'refocus_monitoring',
      channelName: 'ReFocus Monitoring',
      channelDescription: 'Keeps ReFocus monitoring your app usage',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000), // Check every 5 seconds
      autoRunOnBoot: true, // Auto-start on device boot
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  // Initialize notification service
  await NotificationService.initialize();
  await NotificationService.requestPermission();

  // ✅ CRITICAL: Initialize database BEFORE app starts
  // This ensures any corrupted database is deleted and recreated
  // This prevents login from hanging
  print("🗄️ Pre-initializing database...");
  try {
    await DatabaseHelper.instance.database;
    print("✅ Database ready");
    
    // Initialize feedback logger for ML training
    await FeedbackLogger.initialize();
    print("✅ Feedback logger initialized");
    
    // Reset daily unlock counts (cleanup old data)
    await FeedbackAbusePrevention.resetDailyUnlocks();
    print("✅ Abuse prevention initialized");
    
    // Initialize ensemble model service (loads user model, rule-based always available)
    await EnsembleModelService.initialize();
    print("✅ Ensemble model service initialized");
    
    // ✅ CRITICAL: Reset training flag on app start (handles app kill scenario)
    MLTrainingService.resetTrainingFlag();
    print("✅ ML training flag reset");
    
    // Initialize learning mode manager
    // Set default to learning mode if not set
    final learningEnabled = await LearningModeManager.isLearningModeEnabled();
    if (learningEnabled) {
      final startDate = await LearningModeManager.getLearningStartDate();
      if (startDate == null) {
        // First time - set learning start date
        await LearningModeManager.setLearningModeEnabled(true);
      }
    }
    print("✅ Learning mode manager initialized");
    
    // Reset daily proactive feedback tracking
    await ProactiveFeedbackService.resetDailyTracking();
    
    // Initialize passive learning service (cleanup old data)
    await PassiveLearningService.cleanup();
    print("✅ Passive learning service initialized");
    print("✅ Proactive feedback service initialized");
    
    // ✅ LONG-TERM RELIABILITY: Automatic database cleanup (every 7 days)
    // Prevents database from growing too large over time
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getInt('last_db_cleanup') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceCleanup = (now - lastCleanup) / (1000 * 60 * 60 * 24);
      
      // Run cleanup if 7+ days have passed since last cleanup
      if (daysSinceCleanup >= 7 || lastCleanup == 0) {
        print("🧹 Running automatic database cleanup (last cleanup: ${lastCleanup == 0 ? 'never' : '${daysSinceCleanup.toStringAsFixed(1)} days ago'})");
        await DatabaseHelper.instance.cleanOldData();
        await prefs.setInt('last_db_cleanup', now);
        print("✅ Database cleanup complete");
      } else {
        print("ℹ️ Database cleanup not needed (last cleanup: ${daysSinceCleanup.toStringAsFixed(1)} days ago)");
      }
    } catch (e) {
      // Don't block app startup if cleanup fails
      print("⚠️ Database cleanup error (non-critical): $e");
    }
    
    // ✅ LONG-TERM RELIABILITY: Clean old SharedPreferences keys (every 30 days)
    // Removes date-suffixed keys older than 7 days to prevent accumulation
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPrefsCleanup = prefs.getInt('last_prefs_cleanup') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSincePrefsCleanup = (now - lastPrefsCleanup) / (1000 * 60 * 60 * 24);
      
      // Run cleanup if 30+ days have passed since last cleanup
      if (daysSincePrefsCleanup >= 30 || lastPrefsCleanup == 0) {
        print("🧹 Running SharedPreferences cleanup (last cleanup: ${lastPrefsCleanup == 0 ? 'never' : '${daysSincePrefsCleanup.toStringAsFixed(1)} days ago'})");
        await _cleanOldSharedPreferencesKeys(prefs);
        await prefs.setInt('last_prefs_cleanup', now);
        print("✅ SharedPreferences cleanup complete");
      }
    } catch (e) {
      // Don't block app startup if cleanup fails
      print("⚠️ SharedPreferences cleanup error (non-critical): $e");
    }
  } catch (e) {
    print("❌ Database initialization failed: $e");
    // App will still run - database will retry when needed
  }

  // ✅ Start periodic ML training check (every hour)
  _startMLTrainingTimer();

  // ✅ Start adaptive threshold evaluation (daily)
  _startAdaptiveThresholdTimer();

  runApp(const MyApp());
}

/// Start periodic timer for automatic ML training
void _startMLTrainingTimer() {
  // Check immediately after 5 minutes (to avoid blocking startup)
  Future.delayed(const Duration(minutes: 5), () async {
    try {
      await MLTrainingService.autoRetrainIfNeeded();
    } catch (e) {
      print('⚠️ Initial ML training check failed: $e');
    }
  });

  // Then check every hour
  Timer.periodic(const Duration(hours: 1), (timer) async {
    try {
      await MLTrainingService.autoRetrainIfNeeded();
      print('✅ Periodic ML training check completed');
    } catch (e) {
      print('⚠️ Periodic ML training check failed: $e');
    }
  });
  
  print('✅ ML training timer started (checks every hour)');
}

/// Start periodic timer for adaptive threshold evaluation
void _startAdaptiveThresholdTimer() {
  // Check immediately after 10 minutes (to avoid blocking startup)
  Future.delayed(const Duration(minutes: 10), () async {
    try {
      final result = await AdaptiveThresholdManager.evaluateAndAdjust();
      if (result['adjusted'] == true) {
        print('✅ Initial adaptive threshold evaluation: ${result['adjustments']}');
      } else {
        print('✅ Initial adaptive threshold evaluation: No adjustments needed');
      }
    } catch (e) {
      print('⚠️ Initial adaptive threshold evaluation failed: $e');
    }
  });

  // Then check every 24 hours
  Timer.periodic(const Duration(hours: 24), (timer) async {
    try {
      final result = await AdaptiveThresholdManager.evaluateAndAdjust();
      if (result['adjusted'] == true) {
        print('✅ Periodic adaptive threshold evaluation: ${result['adjustments']}');
      } else {
        print('✅ Periodic adaptive threshold evaluation: No adjustments needed');
      }
    } catch (e) {
      print('⚠️ Periodic adaptive threshold evaluation failed: $e');
    }
  });
  
  print('✅ Adaptive threshold timer started (checks every 24 hours)');
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Ensure monitoring continues when app resumes
    if (state == AppLifecycleState.resumed) {
      // Restart monitoring service if it was killed
      MonitorService.restartMonitoring();
      
      // ✅ Check for pending lock feedback when app resumes
      // This shows feedback dialog if user didn't respond to notification
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final hasPending = prefs.getBool('has_pending_lock_feedback') ?? false;
          
          if (hasPending) {
            // Get pending feedback data
            final appName = prefs.getString('pending_lock_feedback_app');
            final category = prefs.getString('pending_lock_feedback_category');
            final sessionUsage = prefs.getInt('pending_lock_feedback_session');
            final dailyUsage = prefs.getInt('pending_lock_feedback_daily');
            final lockReason = prefs.getString('pending_lock_feedback_reason');
            final predictionSource = prefs.getString('pending_lock_feedback_source');
            final confidenceStr = prefs.getString('pending_lock_feedback_confidence');
            final modelConfidence = confidenceStr != null ? double.tryParse(confidenceStr) : null;
            
            if (appName != null && category != null && sessionUsage != null && dailyUsage != null) {
              // Show feedback dialog via navigator
              final navigator = Nav.navigatorKey.currentState;
              if (navigator != null && navigator.context.mounted) {
                try {
                  await showDialog(
                    context: navigator.context,
                    barrierDismissible: false,
                    builder: (context) => LockFeedbackDialog(
                      appName: appName,
                      appCategory: category,
                      dailyUsage: dailyUsage,
                      sessionUsage: sessionUsage,
                      lockReason: lockReason ?? 'App locked',
                      predictionSource: predictionSource ?? 'rule_based',
                      modelConfidence: modelConfidence,
                    ),
                  );
                  
                  print('✅ Pending lock feedback dialog shown');
                } catch (e) {
                  print('⚠️ Error showing pending feedback dialog: $e');
                  // ✅ CRITICAL: Still clear pending flag even if dialog fails
                  // This prevents infinite retry loop
                } finally {
                  // ✅ CRITICAL: Always clear pending flag after attempting to show dialog
                  await prefs.setBool('has_pending_lock_feedback', false);
                }
              } else {
                // ✅ CRITICAL: Clear pending flag if navigator is not available
                await prefs.setBool('has_pending_lock_feedback', false);
                print('⚠️ Navigator not available, cleared pending feedback flag');
              }
            } else {
              // ✅ CRITICAL: Clear pending flag if data is incomplete
              await prefs.setBool('has_pending_lock_feedback', false);
              print('⚠️ Incomplete pending feedback data, cleared flag');
            }
          }
        } catch (e) {
          print('⚠️ Error checking pending lock feedback: $e');
        }
      });
      
      // ✅ TRIGGER 3: Check for ML training when app resumes
      // This ensures training happens even if timer was missed
      Future.delayed(const Duration(seconds: 10), () async {
        try {
          await MLTrainingService.autoRetrainIfNeeded();
          print('✅ ML training check completed on app resume');
        } catch (e) {
          print('⚠️ ML training check failed on app resume: $e');
        }
      });
      
      // ✅ TRIGGER 4: Check adaptive threshold evaluation when app resumes
      // This ensures evaluation happens even if timer was missed
      Future.delayed(const Duration(seconds: 15), () async {
        try {
          final result = await AdaptiveThresholdManager.evaluateAndAdjust();
          if (result['adjusted'] == true) {
            print('✅ Adaptive threshold evaluation on app resume: ${result['adjustments']}');
          }
        } catch (e) {
          print('⚠️ Adaptive threshold evaluation failed on app resume: $e');
        }
      });
    }
  }
  

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ReFocus',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey: Nav.navigatorKey,
      home: FutureBuilder<bool>(
        future: _checkOnboardingCompleted(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          
          final onboardingCompleted = snapshot.data!;
          if (onboardingCompleted) {
            return const IntroPage(); // Go to login/intro
          } else {
            return const OnboardingScreen(); // Show onboarding first
          }
        },
      ),
      routes: {
        '/home': (context) => const HomePage(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
  
  Future<bool> _checkOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('onboarding_completed') ?? false;
    } catch (e) {
      print('⚠️ Error checking onboarding status: $e');
      // Default to showing onboarding if error
      return false;
    }
  }
}
