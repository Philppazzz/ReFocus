import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/services/app_name_service.dart';
import 'package:refocus_app/services/app_categorization_service.dart';
// Old stats page removed - using DashboardScreen instead
import 'package:refocus_app/pages/terms_page.dart';
import 'package:refocus_app/pages/permissions_guide_page.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/emergency_service.dart';
import 'package:refocus_app/screens/dashboard_screen.dart';
import 'package:refocus_app/screens/learning_mode_settings_screen.dart';
import 'package:refocus_app/screens/ml_pipeline_test_screen.dart';
import 'package:refocus_app/widgets/proactive_feedback_dialog.dart';
import 'package:refocus_app/widgets/learning_insights_card.dart';
import 'package:refocus_app/widgets/ml_status_widget.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/usage_monitoring_service.dart';
import 'package:refocus_app/services/permission_service.dart';
import 'package:flutter/services.dart';

/// ------------------- GLOBAL SINGLETON -------------------
class AppState {
  static final AppState _instance = AppState._internal();
  bool isOverrideEnabled = false;

  factory AppState() => _instance;
  AppState._internal();
}

/// ------------------- SELECTED APPS MANAGER -------------------
// Moved to services/selected_apps.dart

/// ------------------- HOME PAGE -------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _usageStats;
  Timer? _refreshTimer;
  Timer? _cooldownChecker;
  Timer? _proactiveFeedbackChecker;
  Timer? _sessionRefreshTimer; // ✅ Real-time session refresh
  bool _isLoading = false; // ✅ Start with false - show UI immediately
  String _lastUpdateTime = '';
  Map<String, dynamic>? _cooldownInfo;
  double _dailyLimitMinutes = 0.0;
  double _sessionLimitMinutes = 0.0;
  double _currentSessionMinutes = 0.0; // Continuous session across Social + Games + Entertainment
  String? _lastCheckedApp;  // Track last app checked for proactive feedback
  Map<String, bool>? _permissionStatus; // Permission status
  Timer? _permissionChecker; // Check permissions periodically
  
  // ✅ Learning mode state
  bool _isInLearningMode = false;
  
  // Weekly and longest used apps data
  List<Map<String, dynamic>> _weeklyMostUnlockedApps = [];
  List<Map<String, dynamic>> _weeklyLongestUsedApps = [];
  
  // ✅ Day change tracking for reliable daily reset
  String? _currentDate;
  Timer? _dayChangeChecker;

  @override
  void initState() {
    super.initState();
    print("🏠 HomePage initState START");
    WidgetsBinding.instance.addObserver(this);

    print("🏠 Scheduling background initialization");
    // ✅ Run everything in the NEXT frame to avoid blocking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("🏠 PostFrameCallback executing");
      _syncEmergencyState();
      _initializeHome();
    });

    print("🏠 HomePage initState END");
  }
  
  Future<void> _syncEmergencyState() async {
    final prefs = await SharedPreferences.getInstance();
    final isEmergencyActive = prefs.getBool('emergency_override_enabled') ?? false;
    AppState().isOverrideEnabled = isEmergencyActive;
    print("✅ Emergency Override synced on startup: ${isEmergencyActive ? 'ON' : 'OFF'}");
  }

  Future<void> _initializeHome() async {
    print("🚀 Initializing HomePage...");

    // ✅ Stop loading spinner immediately so UI shows up
    setState(() => _isLoading = false);

    // ✅ Run ALL initialization in background to avoid blocking login/signup
    _initializeInBackground();

    // Start auto-refresh (will call _fetchUsage periodically)
    _startAutoRefresh();

    // Start cooldown checker
    _startCooldownChecker();

    // Start proactive feedback checker (learning mode)
    _startProactiveFeedbackChecker();

    // Check permissions and start periodic checking
    _checkPermissions();
    _startPermissionChecker();

    // Start real-time session refresh (updates every 1 second for accuracy)
    _startSessionRefresh();
    
    // ✅ Start day change checker (ensures frontend refreshes on day change)
    _startDayChangeChecker();

    // Fetch initial usage in background (non-blocking)
    _fetchUsage();
  }

  /// Initialize all services in background without blocking UI
  void _initializeInBackground() {
    Future.microtask(() async {
      try {
        print("📱 Starting background initialization...");

        // Sync apps
        try {
          final stats = await AppCategorizationService.syncInstalledApps();
          print("✅ App sync complete: ${stats['categorized']} apps categorized");
        } catch (e) {
          print("⚠️ App sync failed: $e");
        }

        // Load selected apps
        await _loadSelectedApps();

        // ✅ DO NOT request overlay permission here - it opens Settings and blocks the user
        // Permission will be requested when first needed (when trying to lock an app)

        // Start monitoring service
        try {
          await MonitorService.startMonitoring();
          print("✅ Monitoring service started");
        } catch (e) {
          print("⚠️ Monitoring service failed: $e");
        }

        print("✅ Background initialization complete");
      } catch (e) {
        print("⚠️ Background initialization error: $e");
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _cooldownChecker?.cancel();
    _proactiveFeedbackChecker?.cancel();
    _sessionRefreshTimer?.cancel(); // ✅ Cancel session refresh timer
    _permissionChecker?.cancel();
    _dayChangeChecker?.cancel(); // ✅ Cancel day change checker // ✅ Cancel permission checker
    // ✅ CRITICAL: DO NOT stop monitoring when HomePage is disposed
    // Monitoring must continue in background even when app is closed
    // MonitorService.stopMonitoring(); // REMOVED - monitoring continues
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - refresh data and restart monitoring if needed
        print("📱 App resumed - refreshing and ensuring monitoring is active");
        
        // ✅ Check for day change on resume (handles app killed overnight scenario)
        final today = DateTime.now().toIso8601String().substring(0, 10);
        if (_currentDate != null && _currentDate != today) {
          print('🌅 Day change detected on resume: $_currentDate → $today');
          _currentDate = today;
        }
        
        _fetchUsage();
        _checkCooldown();
        MonitorService.restartMonitoring();
        // ✅ CRITICAL: Refresh session immediately when app resumes
        // This ensures continuous usage continues correctly (only resets after 5 min inactivity)
        _startSessionRefresh();
        break;
      case AppLifecycleState.paused:
        // App went to background - monitoring continues via foreground service
        // ✅ Session tracking continues in background (LockStateManager handles 5-min threshold)
        print("📱 App paused - monitoring continues in background, session tracking continues");
        break;
      case AppLifecycleState.inactive:
        // App is transitioning - monitoring continues
        break;
      case AppLifecycleState.detached:
        // App is being terminated - monitoring will stop
        print("📱 App detached - monitoring will stop");
        break;
      case AppLifecycleState.hidden:
        // App is hidden - monitoring continues
        break;
    }
  }

  Future<void> _loadSelectedApps() async {
    // No longer needed - UsageService tracks all apps automatically
    print("📱 App tracking is now automatic (all non-system apps)");
  }


  Future<void> _fetchUsage() async {
    try {
      // ✅ Don't set loading = true here - it blocks login
      // Loading state is managed in _initializeHome()

      // ✅ CRITICAL FIX: Force update usage stats FIRST to ensure database is up-to-date
      // Add small delay to ensure database write completes
      try {
        final platform = const MethodChannel('com.example.refocus/monitor');
        final foregroundApp = await platform.invokeMethod<String>('getForegroundApp');
        if (foregroundApp != null && foregroundApp.isNotEmpty) {
          await UsageService.getUsageStatsWithEvents(
            currentForegroundApp: foregroundApp,
            updateSessionTracking: true,
          );
          // ✅ CRITICAL: Small delay to ensure database write completes
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        print('⚠️ Error updating usage stats: $e - continuing with cached data');
      }

      final newData = await UsageService.getUsageStatsWithEvents();
      
      // ✅ CRITICAL: Check learning mode to determine correct limits to display
      final isLearningMode = await LearningModeManager.isLearningModeEnabled();
      final phase = await LearningModeManager.getLearningPhase();
      final isInLearningPhase = isLearningMode && 
          (phase == 'pure_learning' || phase == 'soft_learning');
      
      // ✅ Use safety limits in learning mode, rule-based limits otherwise
      double effectiveDailyMinutes;
      double effectiveSessionMinutes;
      
      if (isInLearningPhase) {
        // Learning mode: Show safety limits (6h daily / 2h session)
        effectiveDailyMinutes = 360.0;  // 6 hours
        effectiveSessionMinutes = 120.0; // 2 hours
      } else {
        // Rule-based or ML mode: Show configured limits
        final thresholds = await LockStateManager.getThresholds();
        final double dailyHours = (thresholds['dailyHours'] as num?)?.toDouble() ?? 0.0;
        effectiveDailyMinutes = dailyHours * 60.0;
        effectiveSessionMinutes = (thresholds['sessionMinutes'] as num?)?.toDouble() ?? 0.0;
      }
      
      // ✅ CRITICAL FIX: Get accurate daily usage from database (read after update)
      // Only count monitored categories (Social, Games, Entertainment) - exclude "Others"
      final db = DatabaseHelper.instance;
      // ✅ CRITICAL: Read from database AFTER ensuring it's updated
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      final monitoredDailyMinutes = (categoryUsage['Social'] ?? 0.0) +
                                     (categoryUsage['Games'] ?? 0.0) +
                                     (categoryUsage['Entertainment'] ?? 0.0);
      // "Others" category is tracked separately but NOT counted in daily limit
      // ✅ Always update daily_usage_hours (even if 0) to ensure progress bar works
      newData['daily_usage_hours'] = monitoredDailyMinutes / 60.0;
      
      // ✅ CRITICAL FIX: Get session usage IMMEDIATELY after reading daily usage
      // This ensures both are synchronized and read from the same point in time
      // ✅ SINGLE SOURCE OF TRUTH: LockStateManager.getCurrentSessionMinutes() is used by:
      //    - home_page.dart (this file) - for UI display
      //    - hybrid_lock_manager.dart - for ML model predictions
      //    - feedback_logger.dart - for training data collection
      //    - dashboard_screen.dart - for UI display
      // LockStateManager tracks accumulated time in milliseconds and accounts for 5-minute inactivity threshold
      // Session only increments when monitored apps are actually open, stops when closed/switched away
      final combinedSessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      
      print("📊 Home Page - Daily Usage from DB: ${monitoredDailyMinutes.toStringAsFixed(1)}min (Social: ${categoryUsage['Social']?.toStringAsFixed(1) ?? '0.0'}, Games: ${categoryUsage['Games']?.toStringAsFixed(1) ?? '0.0'}, Entertainment: ${categoryUsage['Entertainment']?.toStringAsFixed(1) ?? '0.0'}, Others: ${categoryUsage['Others']?.toStringAsFixed(1) ?? '0.0'})");
      print("📊 Home Page - Session Usage from LockStateManager (SAME AS ML MODEL): ${combinedSessionMinutes.toStringAsFixed(1)}min");
      
      // ✅ Calculate unlock delta for display (matches limit check logic)
      // This shows "unlocks in current cycle" (0-5, then resets after violation)
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final unlockBase = prefs.getInt('unlock_base_$today') ?? 0;
      final totalUnlocks = (newData['most_unlock_count'] as num?)?.toInt() ?? 0;
      final unlockDelta = (totalUnlocks - unlockBase).clamp(0, 999);
      
      // Add delta to stats for display
      newData['unlock_count_delta'] = unlockDelta;
      
      print("🔍 Home Page Unlock Display:");
      print("   Total unlocks today: $totalUnlocks");
      print("   Base (from last violation): $unlockBase");
      print("   Delta (current cycle): $unlockDelta / 5");
      
      // Get monitoring service for breakdown display
      final monitoringService = UsageMonitoringService();
      
      print("🔍 Home Page Data Refresh:");
      print("   Daily usage: ${monitoredDailyMinutes.toStringAsFixed(1)}min / ${effectiveDailyMinutes.toStringAsFixed(0)}min (${((monitoredDailyMinutes / effectiveDailyMinutes) * 100).toStringAsFixed(1)}%)");
      print("   Session usage: ${combinedSessionMinutes.toStringAsFixed(1)}min / ${effectiveSessionMinutes.toStringAsFixed(0)}min (${((combinedSessionMinutes / effectiveSessionMinutes) * 100).toStringAsFixed(1)}%)");
      print("   Session breakdown - Social: ${monitoringService.sessionUsage['Social'] ?? 0}min, Games: ${monitoringService.sessionUsage['Games'] ?? 0}min, Entertainment: ${monitoringService.sessionUsage['Entertainment'] ?? 0}min");
      print("   Learning mode: $isInLearningPhase");


      // ✅ Fetch weekly and longest used apps data
      final weeklyUnlocked = await db.getTopUnlockedAppsWeek();
      final weeklyLongest = await db.getTopLongestUsedAppsWeek();
      
      print("📊 Home Page - Longest Apps Data:");
      print("   Week: ${weeklyLongest.length} apps (${weeklyLongest.map((a) => a['package_name']).join(', ')})");
      print("   Weekly Unlocked: ${weeklyUnlocked.length} apps (${weeklyUnlocked.map((a) => a['package_name']).join(', ')})");

      if (mounted) {
        setState(() {
          _usageStats = newData;
          _weeklyMostUnlockedApps = weeklyUnlocked;
          _weeklyLongestUsedApps = weeklyLongest;
          _lastUpdateTime = _formatTime(DateTime.now());
          _dailyLimitMinutes = effectiveDailyMinutes;
          _sessionLimitMinutes = effectiveSessionMinutes;
          _currentSessionMinutes = combinedSessionMinutes.toDouble(); // ✅ REAL-TIME: Updated from UsageMonitoringService (same as dashboard)
          _isInLearningMode = isInLearningPhase; // ✅ Store learning mode state
        });
      }
    } catch (e) {
      print("⚠️ Error fetching usage: $e");
      print("   This is normal on first launch or if permissions not granted yet");
      // Don't change loading state - let HomePage show with empty data
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    // ✅ CRITICAL FIX: Update every 3 seconds (reduced from 2) to prevent over-incrementing
    // UsageService now has rate limiting (500ms) and lock mechanism to prevent double-counting
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        // ✅ CRITICAL: _fetchUsage() already calls getUsageStatsWithEvents() internally
        // UsageService now has built-in rate limiting and lock to prevent double-counting
        await _fetchUsage();
      } catch (e) {
        print("⚠️ Error in auto refresh: $e");
        // Continue with fetch even if update fails
        await _fetchUsage();
      }
    });
  }

  void _startCooldownChecker() {
    _cooldownChecker?.cancel();
    _cooldownChecker = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkCooldown();
    });
  }

  void _startProactiveFeedbackChecker() {
    _proactiveFeedbackChecker?.cancel();
    // Check every 30 seconds for proactive feedback prompts
    _proactiveFeedbackChecker = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkProactiveFeedback();
    });
  }

  /// Check all permissions status
  Future<void> _checkPermissions() async {
    final status = await PermissionService.checkAllPermissions();
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
    }
  }

  /// Start periodic permission checking
  void _startPermissionChecker() {
    _permissionChecker?.cancel();
    // Check permissions every 5 seconds
    _permissionChecker = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkPermissions();
    });
  }

  /// ✅ CRITICAL: Day change checker - ensures frontend refreshes when day changes
  /// This ensures daily tracking resets properly in both frontend and backend
  /// Weekly stats are NOT affected (they query database for past week)
  void _startDayChangeChecker() {
    // Initialize current date
    _currentDate = DateTime.now().toIso8601String().substring(0, 10);
    
    _dayChangeChecker?.cancel();
    // Check for day change every minute (catches midnight transitions)
    _dayChangeChecker = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      // ✅ Day changed - trigger full refresh
      if (_currentDate != null && _currentDate != today) {
        print('🌅 Day change detected in HomePage: $_currentDate → $today');
        print('   Triggering full refresh to reset daily tracking...');
        
        _currentDate = today;
        
        // ✅ Force refresh to pick up backend reset
        // Backend services (UsageService, LockStateManager, UsageMonitoringService) 
        // already reset daily tracking - frontend just needs to refresh
        await _fetchUsage();
        
        print('✅ HomePage refreshed after day change');
      }
    });
  }

  /// ✅ Real-time session refresh - updates every 50ms for maximum responsiveness (matches daily usage speed)
  /// This ensures the session timer updates immediately when user switches apps
  /// ✅ CRITICAL FIX: Now uses LockStateManager.getCurrentSessionMinutes() with in-memory cache (instant reads)
  /// ✅ SINGLE SOURCE OF TRUTH: Same function used by ML model for predictions - ensures frontend matches backend
  /// ✅ OPTIMIZED: Update interval 50ms (faster than backend 200ms) to catch updates immediately
  /// ✅ CRITICAL: LockStateManager now uses in-memory cache (updated every 200ms, valid for 1s) - matches daily usage pattern
  void _startSessionRefresh() {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!mounted) return;
      
      try {
        // ✅ CRITICAL FIX: Use LockStateManager.getCurrentSessionMinutes() with in-memory cache
        // Cache is updated immediately when updateSessionActivity() is called (every 200ms by MonitorService)
        // Cache validity is 1 second (longer than update interval), so cache is always fresh
        // This makes reads instant (synchronous return when cache valid) - matches daily usage speed
        // This tracks accumulated time in milliseconds and accounts for 5-minute inactivity threshold
        // LockStateManager already handles combined session across all monitored categories
        // ✅ ACCURACY: Session only increments when monitored apps are open, stops when closed/switched away
        // This ensures frontend display matches exactly what ML model uses for predictions
        final combinedSessionMinutes = await LockStateManager.getCurrentSessionMinutes();
        
        // ✅ DEBUG: Log session updates every 5 seconds to track if it's working
        final now = DateTime.now();
        if (now.millisecond < 50 && now.second % 5 == 0) {
          print("🔄 Home Page - Session refresh: ${combinedSessionMinutes.toStringAsFixed(2)}min (previous: ${_currentSessionMinutes.toStringAsFixed(2)}min)");
        }
        
        // ✅ OPTIMIZED: Reduced threshold to 0.0005 minutes (0.03 seconds) for maximum responsiveness
        // This ensures even tiny changes are reflected immediately (matches daily usage responsiveness)
        // Only update if value changed (prevents unnecessary rebuilds)
        if ((combinedSessionMinutes - _currentSessionMinutes).abs() > 0.0005) {
          // ✅ CRITICAL: Double-check mounted before setState (prevents errors if disposed during async operation)
          if (mounted) {
            setState(() {
              _currentSessionMinutes = combinedSessionMinutes;
            });
            // Only log when minute changes to reduce log spam
            if ((combinedSessionMinutes.floor() != _currentSessionMinutes.floor())) {
              print("✅ Home Page - Session updated: ${combinedSessionMinutes.toStringAsFixed(2)}min");
            }
          }
        }
      } catch (e) {
        print("⚠️ Error in session refresh: $e");
        // Continue - don't break the timer if one update fails
      }
    });
  }

  Future<void> _checkProactiveFeedback() async {
    try {
      // Only check in learning mode
      final shouldShow = await LearningModeManager.shouldShowProactiveFeedback();
      if (!shouldShow) return;

      // Get current foreground app
      const platform = MethodChannel('com.example.refocus_app/monitor');
      final foregroundApp = await platform.invokeMethod<String>('getForegroundApp');
      
      if (foregroundApp == null || foregroundApp.isEmpty) return;
      if (foregroundApp == _lastCheckedApp) return;  // Avoid duplicate prompts
      
      _lastCheckedApp = foregroundApp;

      // Get category and usage
      final category = await AppCategorizationService.getCategoryForPackage(foregroundApp);
      
      // ✅ CRITICAL: Sync usage from database before checking proactive feedback
      // This ensures we detect 50% threshold accurately
      // Database is updated by UsageService which processes Android UsageStats
      final db = DatabaseHelper.instance;
      final categoryUsage = await db.getCategoryUsageForDate(DateTime.now());
      
      // ✅ For monitored categories (Social/Games/Entertainment), use COMBINED usage
      // This matches how lock decisions work (shared limits system)
      final monitoredCategories = ['Social', 'Games', 'Entertainment'];
      int dailyUsage;
      if (monitoredCategories.contains(category)) {
        // Combined daily usage for monitored categories
        dailyUsage = ((categoryUsage['Social'] ?? 0.0) +
                     (categoryUsage['Games'] ?? 0.0) +
                     (categoryUsage['Entertainment'] ?? 0.0)).round();
      } else {
        // Per-category usage for Others
        dailyUsage = (categoryUsage[category] ?? 0.0).round();
      }
      
      // ✅ CRITICAL: Get session usage from LockStateManager (source of truth)
      // LockStateManager tracks continuous session across monitored categories
      // with 5-minute inactivity threshold
      final sessionUsage = await LockStateManager.getCurrentSessionMinutes();

      // Check if we should show proactive feedback
      final promptResult = await ProactiveFeedbackService.shouldShowPrompt(
        category: category,
        sessionUsageMinutes: sessionUsage.round(),
        dailyUsageMinutes: dailyUsage,
      );

      if (promptResult['shouldShow'] as bool && mounted) {
        final usageLevel = promptResult['usageLevel'] as int;
        
        // Get app name
        final appName = await AppNameService.getAppName(foregroundApp);

        // Show proactive feedback dialog
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: true,  // Allow dismissing (non-blocking)
            builder: (context) => ProactiveFeedbackDialog(
              appName: appName,
              appCategory: category,
              dailyUsage: dailyUsage,
              sessionUsage: sessionUsage.round(),
              usageLevel: usageLevel,
            ),
          );
        }
      }
    } catch (e) {
      print('⚠️ Error checking proactive feedback: $e');
    }
  }

  Future<void> _checkCooldown() async {
    final cooldown = await LockStateManager.getActiveCooldown();
    if (mounted) {
      setState(() {
        _cooldownInfo = cooldown;
      });
      
      // NOTE: MonitorService handles showing lock screen automatically
      // We only update UI state here, don't show lock screen from HomePage
      // to avoid conflicts with MonitorService's automatic locking
    }
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
  }

  void refresh() {
    _fetchUsage();
    _checkCooldown();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Get accurate daily usage from stats (updated with database data in _fetchUsage)
    final totalUsageMinutes = ((_usageStats?['daily_usage_hours'] ?? 0.0) * 60);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
          'Dashboard',
          style: GoogleFonts.alice(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          // Cooldown indicator
          if (_cooldownInfo != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        '${(_cooldownInfo!['remainingSeconds'] / 60).ceil()} min',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_lastUpdateTime.isNotEmpty && _cooldownInfo == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _lastUpdateTime,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardScreen(),
                ),
              );
            },
            tooltip: 'Analytics Dashboard',
          ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchUsage,
            tooltip: 'Refresh',
          ),
        ],
      ),
      drawer: AppDrawer(onRefresh: refresh),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading && _usageStats == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
                  children: [
                      // ✅ Permission Request Card (show if permissions missing)
                      if (_permissionStatus != null && !(_permissionStatus!['all_granted'] ?? false))
                        _buildPermissionRequestCard(),

                // Active cooldown warning
                if (_cooldownInfo != null)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade900,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Apps locked: ${_cooldownInfo!['reason'].toString().replaceAll('_', ' ')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${(_cooldownInfo!['remainingSeconds'] / 60).ceil()}m left',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ ML Status Widget - Shows ML readiness in real-time
                        const MLStatusWidget(),
                        const SizedBox(height: 16),
                        
                        _buildDailyUsageCard(totalUsageMinutes, _dailyLimitMinutes > 0 ? _dailyLimitMinutes : 1.2),

                        const SizedBox(height: 16),
                        // ✅ Learning Insights Card (show during learning mode - below daily usage)
                        const LearningInsightsCard(),

                        const SizedBox(height: 16),
                        // ✅ REAL-TIME: Use state value updated by _sessionRefreshTimer (every 1 second)
                        // This ensures immediate updates when user switches apps or session changes
                        _buildSessionProgressCard(
                          currentMinutes: _currentSessionMinutes,
                          limitMinutes: _sessionLimitMinutes > 0 ? _sessionLimitMinutes : 60.0,
                        ),
                        const SizedBox(height: 16),
                        _buildWeeklyMostUnlockedAppsCard(),
                        const SizedBox(height: 16),
                        _buildLongestUsedAppsCard('week'),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// --- UI BUILDERS ---
  Widget _buildDailyUsageCard(double usageMinutes, double dailyLimitMinutes) {
    final progress = (usageMinutes / dailyLimitMinutes).clamp(0.0, 1.0);
    final percentage = (progress * 100).toInt();
    String _fmtHM(double minutes) {
      final h = (minutes / 60).floor();
      final m = (minutes % 60).floor();
      if (h <= 0) return "${m}m";
      if (m <= 0) return "${h}h";
      return "${h}h ${m}m";
    }
    
    // ✅ Mode-aware display
    String limitLabel = _isInLearningMode 
        ? "Safety Limit"
        : "Daily Limit";
    
    String percentageLabel = _isInLearningMode
        ? "$percentage% of safety limit (monitoring)"
        : "$percentage% of daily limit used";
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black, const Color.fromARGB(255, 30, 30, 30)], // Always black theme
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5), // Always black shadow
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isInLearningMode ? Icons.psychology : Icons.access_time,
                color: Colors.white,
                size: 40,
              ),
              if (_isInLearningMode) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'LEARNING',
                    style: GoogleFonts.alice(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Today's Screen Time",
            style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fmtHM(usageMinutes),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              const Text("/", style: TextStyle(color: Colors.white54, fontSize: 18)),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fmtHM(dailyLimitMinutes),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    limitLabel,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 0.9
                    ? const Color(0xFFDC2626) // Red when nearly at limit
                    : progress >= 0.75
                        ? const Color(0xFFF59E0B) // Orange when approaching limit
                        : Colors.white, // White for normal usage (on black background)
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            percentageLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSessionProgressCard({
    required double currentMinutes,
    required double limitMinutes,
  }) {
    final progress = limitMinutes > 0 ? (currentMinutes / limitMinutes).clamp(0.0, 1.0) : 0.0;
    Color barColor;
    if (progress >= 0.9) {
      barColor = const Color(0xFFDC2626); // Red when nearly at limit
    } else if (progress >= 0.75) {
      barColor = const Color(0xFFF59E0B); // Orange when approaching limit
    } else {
      barColor = Colors.black87; // Always black theme
    }

    String _fmt(double m) {
      if (m < 60) return "${m.toStringAsFixed(0)}m";
      final h = (m / 60).floor();
      final mm = (m % 60).floor();
      if (mm == 0) return "${h}h";
      return "${h}h ${mm}m";
    }
    
    // ✅ Mode-aware labels
    String limitLabel = _isInLearningMode 
        ? "Safety limit (${_fmt(limitMinutes)})"
        : "Session limit (${_fmt(limitMinutes)})";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        border: null, // No special border for learning mode
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timer_outlined, // Always timer icon
                color: Colors.black87, // Always black
              ),
              const SizedBox(width: 10),
              Text(
                "Continuous Session",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87, // Always black
                ),
              ),
              if (_isInLearningMode) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200], // Subtle gray background
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[400]!), // Gray border
                  ),
                  child: Text(
                    'LEARNING',
                    style: GoogleFonts.alice(
                      color: Colors.grey[700], // Dark gray text
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isInLearningMode
                ? "Monitoring only - locks at safety limit"
                : "Social, Games & Entertainment apps",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600], // Always gray
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(currentMinutes), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
              Text(
                limitLabel,
                style: TextStyle(
                  color: Colors.grey[700], // Always gray
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyMostUnlockedAppsCard() {
    if (_weeklyMostUnlockedApps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_today, color: Colors.black87, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Most Unlocked Apps (Week)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Top 3 apps opened this week',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._weeklyMostUnlockedApps.asMap().entries.map((entry) {
            final index = entry.key;
            final app = entry.value;
            final packageName = app['package_name'] as String;
            final unlockCount = (app['total_unlocks'] as num?)?.toInt() ?? 0;

            // Medal colors for top 3
            Color medalColor;
            IconData medalIcon;
            if (index == 0) {
              medalColor = const Color(0xFFFFD700); // Gold
              medalIcon = Icons.emoji_events;
            } else if (index == 1) {
              medalColor = const Color(0xFFC0C0C0); // Silver
              medalIcon = Icons.emoji_events;
            } else {
              medalColor = const Color(0xFFCD7F32); // Bronze
              medalIcon = Icons.emoji_events;
            }

            return Padding(
              padding: EdgeInsets.only(bottom: index < _weeklyMostUnlockedApps.length - 1 ? 12 : 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!, width: 1),
                ),
                child: Row(
                  children: [
                    // Medal
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: medalColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(medalIcon, color: medalColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // App name (use cached value to prevent blinking)
                    Expanded(
                      child: FutureBuilder<String>(
                        future: AppNameService.getAppName(packageName),
                        builder: (context, snapshot) {
                          final appName = snapshot.data ?? packageName.split('.').last;
                          return Text(
                            appName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          );
                        },
                      ),
                    ),
                    // Unlock count
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$unlockCount times',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildLongestUsedAppsCard(String period) {
    // ✅ Only support 'week' period now - 'today' widget removed
    if (period != 'week') {
      return const SizedBox.shrink();
    }
    
    final List<Map<String, dynamic>> apps = _weeklyLongestUsedApps;
    
    if (apps.isEmpty) {
      return const SizedBox.shrink();
    }

    final String title = 'Longest Used Apps (Week)';
    final String subtitle = 'Top 3 apps used longest this week';
    // ✅ Always use black theme
    final Color iconColor = Colors.black87;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.timer, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...apps.asMap().entries.map((entry) {
            final index = entry.key;
            final app = entry.value;
            final packageName = app['package_name'] as String;
            final totalSeconds = (app['total_seconds'] as num?)?.toInt() ?? 0;

            // ✅ Format time accurately - show seconds for short durations
            String formatTime(int seconds) {
              final hours = seconds ~/ 3600;
              final minutes = (seconds % 3600) ~/ 60;
              final secs = seconds % 60;
              
              if (hours > 0) {
                return '${hours}h ${minutes}m';
              } else if (minutes > 0) {
                return '${minutes}m';
              } else {
                return '${secs}s';
              }
            }

            // Medal colors for top 3
            Color medalColor;
            IconData medalIcon;
            if (index == 0) {
              medalColor = const Color(0xFFFFD700); // Gold
              medalIcon = Icons.emoji_events;
            } else if (index == 1) {
              medalColor = const Color(0xFFC0C0C0); // Silver
              medalIcon = Icons.emoji_events;
            } else {
              medalColor = const Color(0xFFCD7F32); // Bronze
              medalIcon = Icons.emoji_events;
            }

            return Padding(
              padding: EdgeInsets.only(bottom: index < apps.length - 1 ? 12 : 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!, width: 1),
                ),
                child: Row(
                  children: [
                    // Medal
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: medalColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(medalIcon, color: medalColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    // App name
                    Expanded(
                      child: FutureBuilder<String>(
                        future: AppNameService.getAppName(packageName),
                        builder: (context, snapshot) {
                          final appName = snapshot.data ?? packageName.split('.').last;
                          return Text(
                            appName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          );
                        },
                      ),
                    ),
                    // Usage time
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: iconColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        formatTime(totalSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  /// ✅ Build permission request card - shows when permissions are missing
  Widget _buildPermissionRequestCard() {
    if (_permissionStatus == null) return const SizedBox.shrink();

    final usageAccess = _permissionStatus!['usage_access'] ?? false;
    final overlay = _permissionStatus!['overlay'] ?? false;
    final notification = _permissionStatus!['notification'] ?? false;

    final missingPermissions = <String>[];
    if (!usageAccess) missingPermissions.add('Usage Access');
    if (!overlay) missingPermissions.add('Display Over Other Apps');
    if (!notification) missingPermissions.add('Notifications');

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF59E0B), // Orange warning
            Color(0xFFDC2626), // Red alert
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permissions Required',
                      style: GoogleFonts.alice(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${missingPermissions.length} permission${missingPermissions.length > 1 ? 's' : ''} needed',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Missing permissions list
          ...missingPermissions.map((permission) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.cancel_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        permission,
                        style: GoogleFonts.alice(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          
          const SizedBox(height: 20),
          const Divider(color: Colors.white70),
          const SizedBox(height: 16),
          
          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'How to Grant Permissions:',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '1. Tap "Open Settings" below\n'
                  '2. Find "ReFocus" in the app list\n'
                  '3. Tap "Permissions" or "App permissions"\n'
                  '4. Enable all required permissions\n'
                  '5. Return to this app',
                  style: GoogleFonts.alice(
                    fontSize: 13,
                    height: 1.6,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Request each missing permission
                    if (!usageAccess) {
                      await PermissionService.requestUsageAccess();
                    }
                    if (!overlay) {
                      await PermissionService.requestOverlayPermission();
                    }
                    if (!notification) {
                      await PermissionService.requestNotificationPermission();
                    }
                    
                    // Recheck permissions after a delay
                    await Future.delayed(const Duration(seconds: 1));
                    await _checkPermissions();
                    
                    // Show message
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Please grant permissions in the settings that opened',
                            style: GoogleFonts.alice(),
                          ),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.settings, size: 20),
                  label: Text(
                    'Grant Permissions',
                    style: GoogleFonts.alice(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await PermissionService.openAppSettings();
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  'Open Settings',
                  style: GoogleFonts.alice(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.5)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Quick stats removed per request; replaced by "More details" button
}

/// ------------------- APP DRAWER -------------------
class AppDrawer extends StatefulWidget {
  final VoidCallback onRefresh;
  const AppDrawer({super.key, required this.onRefresh});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> with SingleTickerProviderStateMixin {
  final appState = AppState();
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _colorAnimation = ColorTween(
      begin: Colors.redAccent,
      end: Colors.red.shade900,
    ).animate(_controller);

    // Sync emergency state from SharedPreferences
    _syncEmergencyState();
  }
  
  Future<void> _syncEmergencyState() async {
    final isActive = await EmergencyService.isEmergencyActive();
    if (mounted) {
      setState(() {
        appState.isOverrideEnabled = isActive;
        if (isActive) {
          _controller.repeat(reverse: true);
        }
      });
    }
  }

  Future<void> _toggleOverride() async {
    final context = this.context;
    final isCurrentlyActive = await EmergencyService.isEmergencyActive();
    
    if (isCurrentlyActive) {
      // Deactivate emergency
      await EmergencyService.deactivateEmergency();
      if (mounted) {
        setState(() {
          appState.isOverrideEnabled = false;
          _controller.stop();
        });
      }
      widget.onRefresh();
      return;
    }
    
    // Check if already used today
    if (await EmergencyService.hasUsedEmergencyToday()) {
      final hoursUntil = await EmergencyService.getHoursUntilAvailable();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency override already used today. Available in $hoursUntil hours.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    // Show confirmation dialog
    if (context.mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
              const SizedBox(width: 10),
              const Text('Emergency Override'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to activate emergency override?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text('This will:'),
              const SizedBox(height: 8),
              const Text('✓ Remove all active locks'),
              const Text('✓ Reset session timer'),
              const Text('✓ Reset unlock counter'),
              const Text('✓ Stop all tracking temporarily'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: const Text(
                  '⚠️ Can only be used ONCE per day',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: Daily usage limit will still apply when you turn this off.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      
      if (confirm == true && context.mounted) {
        // Activate emergency
        final result = await EmergencyService.activateEmergency();
        
        if (result['success'] == true && mounted) {
          setState(() {
            appState.isOverrideEnabled = true;
            _controller.repeat(reverse: true);
          });
          widget.onRefresh();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOn = appState.isOverrideEnabled;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.65,
      child: Drawer(
        backgroundColor: const Color(0xFF141414),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              children: [
                Container(
                  color: const Color(0xFF141414),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 10),
                          Text('ReFocus', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Emergency Override
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: GestureDetector(
                    onTap: _toggleOverride,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final color = isOn ? _colorAnimation.value : Colors.grey[300];
                        final textColor = isOn ? Colors.white : Colors.black;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: textColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isOn ? 'Emergency Override: ON' : 'Emergency Override: OFF',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(color: Colors.white24),
                ListTile(
                  leading: const Icon(Icons.home_outlined, color: Colors.white),
                  title: const Text('Home', style: TextStyle(color: Colors.white)),
                  onTap: () => _navigateTo(context, const HomePage()),
                ),
                ListTile(
                  leading: const Icon(Icons.security, color: Colors.white),
                  title: const Text('Setup Permissions', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Grant required permissions', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PermissionsGuidePage()),
                    );
                  },
                ),
                // App selection removed - now tracks all apps automatically
                ListTile(
                  leading: const Icon(Icons.psychology, color: Colors.white),
                  title: const Text('AI Learning Mode', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Configure learning vs rule-based', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LearningModeSettingsScreen(),
                      ),
                    );
                  },
                ),
                // ⚠️ DEVELOPER TESTING TOOL - Can be removed for production
                ListTile(
                  leading: const Icon(Icons.science, color: Colors.orange),
                  title: const Text('ML Pipeline Testing', style: TextStyle(color: Colors.orange)),
                  subtitle: const Text('Developer testing tool', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MLPipelineTestScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.white),
                  title: const Text('About Us', style: TextStyle(color: Colors.white)),
                  onTap: () => _navigateTo(context, const AboutPage()),
                ),
                        const Divider(color: Colors.white24),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.white),
                title: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () async {
                  // Stop monitoring only when user logs out
                  MonitorService.stopMonitoring();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const IntroPage()),
                        (route) => false);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------- ABOUT PAGE -------------------
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
            );
          },
        ),
        title: Text(
          'About Us',
          style: GoogleFonts.alice(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            
            // Logo/Icon Section
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(255, 13, 13, 29).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.timer_outlined,
                color: Colors.white,
                size: 60,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // App Name
            Text(
              'ReFocus',
              style: GoogleFonts.alice(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Tagline
            Text(
              'Take Control of Your Screen Time',
              style: GoogleFonts.alice(
                fontSize: 16,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Mission Statement Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.flag_outlined,
                          color: Color(0xFF6366F1),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Our Mission',
                        style: GoogleFonts.alice(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ReFocus is designed to help you build healthy digital habits and improve your focus. '
                    'We believe that technology should enhance your life, not dominate it. '
                    'Our app empowers you to take control of your screen time, reduce distractions, '
                    'and create a healthier balance between your digital and real-world experiences.',
                    style: GoogleFonts.alice(
                      fontSize: 15,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Features Section
            Text(
              'What We Offer',
              style: GoogleFonts.alice(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 16),
            
            _buildFeatureCard(
              icon: Icons.access_time,
              title: 'Smart Category Tracking',
              description: 'Monitor screen time by category (Social, Games, Entertainment) with AI-powered insights.',
              color: const Color(0xFF6366F1),
            ),
            
            const SizedBox(height: 12),
            
            _buildFeatureCard(
              icon: Icons.lock_outline,
              title: 'Flexible Limits',
              description: 'Set daily, session, and unlock limits with automatic cooldowns to help you stay focused.',
              color: Colors.orange,
            ),
            
            const SizedBox(height: 12),
            
            _buildFeatureCard(
              icon: Icons.trending_up,
              title: 'Progress Tracking',
              description: 'View your usage trends, track improvements, and celebrate your progress over time.',
              color: Colors.green,
            ),
            
            const SizedBox(height: 12),
            
            const SizedBox(height: 32),
            
            // Contact Section
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.email_outlined,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Contact Us',
                    style: GoogleFonts.alice(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Have questions or feedback? We\'d love to hear from you!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.alice(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'support@refocus.app',
                      style: GoogleFonts.alice(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Link to Terms
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsPage(),
                  ),
                );
              },
              child: Text(
                'Terms & Conditions',
                style: GoogleFonts.alice(
                  fontSize: 14,
                  color: const Color(0xFF6366F1),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Version/Footer
            Text(
              'Version 1.0.0',
              style: GoogleFonts.alice(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              '© 2024 ReFocus. All rights reserved.',
              style: GoogleFonts.alice(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.alice(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.alice(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}