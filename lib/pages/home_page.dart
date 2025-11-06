import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_picker_page.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/services/selected_apps.dart';
import 'package:refocus_app/pages/usage_statistics_page.dart';
import 'package:refocus_app/pages/terms_page.dart';
import 'package:refocus_app/database_helper.dart';

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
  bool _isLoading = true;
  String _lastUpdateTime = '';
  Map<String, dynamic>? _cooldownInfo;
  double _dailyLimitMinutes = 0.0;
  double _sessionLimitMinutes = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ CRITICAL: Reset Emergency Override on app startup to ensure clean state
    AppState().isOverrideEnabled = false;
    print("✅ Emergency Override reset to OFF on startup");
    
    _initializeHome();
  }

  Future<void> _initializeHome() async {
    print("🚀 Initializing HomePage...");
    
    // Load selected apps
    await _loadSelectedApps();
    
    // Request overlay permission
    await MonitorService.requestOverlayPermission();
    
    // Start monitoring service
    await MonitorService.startMonitoring();
    print("✅ Monitoring service started");
    
    // Fetch initial usage
    await _fetchUsage();
    
    // Start auto-refresh
    _startAutoRefresh();
    
    // Start cooldown checker
    _startCooldownChecker();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _cooldownChecker?.cancel();
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
      _fetchUsage();
      _checkCooldown();
        MonitorService.restartMonitoring();
        break;
      case AppLifecycleState.paused:
        // App went to background - monitoring continues via foreground service
        print("📱 App paused - monitoring continues in background");
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
    await SelectedAppsManager.loadFromPrefs();
    print("📱 Loaded ${SelectedAppsManager.selectedApps.length} selected apps");
  }

  Future<void> _fetchUsage() async {
    if (SelectedAppsManager.selectedApps.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      setState(() => _isLoading = true);

      final newData = await UsageService.getUsageStatsWithEvents(
          SelectedAppsManager.selectedApps);
      final thresholds = await LockStateManager.getThresholds();
      final double dailyHours = (thresholds['dailyHours'] as num?)?.toDouble() ?? 0.0;
      final double sessionMinutes = (thresholds['sessionMinutes'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        setState(() {
          _usageStats = newData;
          _isLoading = false;
          _lastUpdateTime = _formatTime(DateTime.now());
          _dailyLimitMinutes = dailyHours * 60.0;
          _sessionLimitMinutes = sessionMinutes;
        });
      }
    } catch (e) {
      print("⚠️ Error fetching usage: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchUsage();
    });
  }

  void _startCooldownChecker() {
    _cooldownChecker?.cancel();
    _cooldownChecker = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkCooldown();
    });
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
    final totalUsageMinutes = (_usageStats?['daily_usage_hours'] ?? 0.0) * 60; // Convert to minutes
    final mostUnlockedApp = _usageStats?['most_unlock_app'] ?? "None";
    final unlockCount = _usageStats?['most_unlock_count'] ?? 0;

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
                        const SizedBox(height: 10),
                        _buildDailyUsageCard(totalUsageMinutes, _dailyLimitMinutes > 0 ? _dailyLimitMinutes : 1.2),

                        const SizedBox(height: 24),
                        _buildSessionProgressCard(
                          currentMinutes: (_usageStats?['current_session'] as num?)?.toDouble() ?? 0.0,
                          limitMinutes: _sessionLimitMinutes > 0 ? _sessionLimitMinutes : 20.0,
                        ),
                        const SizedBox(height: 16),
                        _buildStatCard(
                          icon: Icons.smartphone,
                          title: "Most Unlocked App",
                          subtitle: mostUnlockedApp,
                          value: "$unlockCount times",
                          color: Colors.black,
                        ),
                        const SizedBox(height: 24),
                        const SizedBox(height: 8),
                        // Button to view detailed statistics
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const UsageStatisticsPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.analytics),
                            label: const Text("More details"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
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
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black, Color.fromARGB(255, 11, 12, 12)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.access_time, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text(
            "Today's Screen Time",
            style: TextStyle(
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
              Text(
                _fmtHM(dailyLimitMinutes),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
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
                progress < 0.5
                    ? Colors.green
                    : progress < 0.8
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "$percentage% of daily limit used",
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          )),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
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
    if (progress < 0.5) {
      barColor = Colors.green;
    } else if (progress < 0.8) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }

    String _fmt(double m) {
      if (m < 60) return "${m.toStringAsFixed(0)}m";
      final h = (m / 60).floor();
      final mm = (m % 60).floor();
      if (mm == 0) return "${h}h";
      return "${h}h ${mm}m";
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
            children: const [
              Icon(Icons.timer_outlined, color: Colors.black),
              SizedBox(width: 10),
              Text("Max Session", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Selected apps only", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
              Text(_fmt(currentMinutes), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(_fmt(limitMinutes), style: const TextStyle(color: Colors.grey)),
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

    if (appState.isOverrideEnabled) {
      _controller.repeat(reverse: true);
    }
  }

  void _toggleOverride() async {
    final newState = !appState.isOverrideEnabled;
    final prefs = await SharedPreferences.getInstance();
    
    setState(() {
      appState.isOverrideEnabled = newState;
      if (newState) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    });
    
    if (newState) {
      // Override enabled
      await prefs.setBool('emergency_override_enabled', true); // ✅ Sync with SharedPreferences
      
      // ✅ CRITICAL: Mark the timestamp when override is turned ON
      // This will be used to skip all events that occur during override period
      await prefs.setInt('emergency_override_start_time', DateTime.now().millisecondsSinceEpoch);
      print("🚨 Emergency Override: ENABLED at ${DateTime.now().toString().substring(11, 19)}");
      
      // Cache current stats before stopping tracking
      final currentStats = await UsageService.getUsageStatsWithEvents(
        SelectedAppsManager.selectedApps,
        updateSessionTracking: false,
      );
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await prefs.setDouble('cached_daily_usage_$today', currentStats['daily_usage_hours'] ?? 0.0);
      await prefs.setDouble('cached_max_session_$today', currentStats['max_session'] ?? 0.0);
      await prefs.setString('cached_most_unlock_app_$today', currentStats['most_unlock_app'] ?? 'None');
      await prefs.setInt('cached_most_unlock_count_$today', currentStats['most_unlock_count'] ?? 0);
      
      LockStateManager.clearCooldown();
      await prefs.remove('daily_locked'); // Clear daily lock too
      MonitorService.clearLockState(); // Clear lock screen visibility
      print("✅ Stats cached - will remain frozen while override is ON");
      print("✅ All events during override period will be ignored when tracking resumes");
    } else {
      // Override disabled - restart monitoring
      await prefs.setBool('emergency_override_enabled', false); // ✅ Sync with SharedPreferences
      
      // ✅ CRITICAL: Mark the timestamp when override is turned OFF
      // Update last_check to NOW so events during override period are skipped
      final overrideEndTime = DateTime.now().millisecondsSinceEpoch;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await prefs.setInt('last_check_$today', overrideEndTime);
      await prefs.remove('emergency_override_start_time'); // Clean up
      
      print("🚨 Emergency Override: DISABLED at ${DateTime.now().toString().substring(11, 19)}");
      print("✅ Events during override period will be skipped - tracking resumes from NOW");
      
      // ✅ CRITICAL: Restart monitoring and clear cache when override is disabled
      print("🔄 Clearing cache and restarting monitoring...");
      MonitorService.clearStatsCache(); // Clear any stale cache
      
      // Wait a moment to ensure state is updated
      await Future.delayed(const Duration(milliseconds: 100));
      
      try {
        await MonitorService.restartMonitoring();
        print("✅ Monitoring restarted after Emergency Override disabled");
        print("✅ AppState.isOverrideEnabled = ${AppState().isOverrideEnabled}");
        print("✅ MonitorService.isMonitoring = ${MonitorService.isMonitoring}");
      } catch (e) {
        print("⚠️ Error restarting monitoring: $e");
      }
    }
    
    widget.onRefresh();
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
                  leading: const Icon(Icons.apps, color: Colors.white),
                  title: const Text('Select Apps', style: TextStyle(color: Colors.white)),
                  onTap: () => _navigateTo(context, const AppPickerPage()),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.white),
                  title: const Text('About Us', style: TextStyle(color: Colors.white)),
                  onTap: () => _navigateTo(context, const AboutPage()),
                ),
                        const Divider(color: Colors.white24),
                        ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: Colors.orange),
                  title: const Text('Reset All Usage Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                    'Clear all tracking data for today',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                          onTap: () async {
                    // Show confirmation dialog
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('⚠️ Reset All Usage Data?'),
                        content: const Text(
                          'This will reset ALL tracking data for today including:\n\n'
                          '• Usage statistics\n'
                          '• Unlock counts\n'
                          '• Session data\n'
                          '• Violation counts\n\n'
                          'This action cannot be undone. Are you sure?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Reset All Data'),
                        ),
                      ],
                      ),
                    );
                    
                    if (confirm != true) return;
                    
                    // Clear lock state
                    MonitorService.clearLockState();
                    MonitorService.clearStatsCache();
                    
                    // Clear cooldown and daily lock
                    await LockStateManager.clearCooldown();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('daily_locked');
                    
                    // Reset ALL tracking state
                    final today = DateTime.now().toIso8601String().substring(0, 10);
                    await prefs.remove('session_violations_$today');
                    await prefs.remove('unlock_violations_$today');
                    await prefs.remove('daily_limit_reached_$today');
                    await prefs.remove('session_start_$today');
                    await prefs.remove('last_activity_$today');
                    await prefs.remove('unlock_base_$today');
                    await prefs.remove('last_session_violation_$today');
                    await prefs.remove('last_unlock_violation_$today');
                    await prefs.remove('cooldown_end');
                    await prefs.remove('cooldown_reason');
                    await prefs.remove('cooldown_app');
                    
                    // Reset usage statistics
                    final now = DateTime.now().millisecondsSinceEpoch;
                    await prefs.setInt('last_check_$today', now);
                            await UsageService.resetTodayAggregates();
                    
                    // Clear all usage-related SharedPreferences
                    await prefs.setString('per_app_usage_$today', '{}');
                    await prefs.setString('per_app_unlocks_$today', '{}');
                    await prefs.setString('per_app_longest_$today', '{}');
                    await prefs.setString('processed_$today', '[]');
                    await prefs.remove('active_app_$today');
                    await prefs.remove('active_start_$today');
                    
                    // Clear database
                    final db = await DatabaseHelper.instance.database;
                    await db.delete('usage_stats', where: 'date = ?', whereArgs: [today]);
                    await db.delete('app_details', where: 'date = ?', whereArgs: [today]);
                    
                    await Future.delayed(const Duration(milliseconds: 300));
                    await MonitorService.checkLimits();
                    
                    print("🔓 All usage data reset successfully");
                    
                    if (context.mounted) {
                      Navigator.pop(context); // Close drawer
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                          content: Text('✅ All usage data reset successfully'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                                ),
                              );
                      widget.onRefresh(); // Refresh home page
                            }
                  },
                ),
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
                  SelectedAppsManager.selectedApps.clear();
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
          style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Tagline
            Text(
              'Take Control of Your Screen Time',
              style: GoogleFonts.inter(
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
                        style: GoogleFonts.inter(
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
                    style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            
            const SizedBox(height: 16),
            
            _buildFeatureCard(
              icon: Icons.access_time,
              title: 'Smart Usage Tracking',
              description: 'Monitor your screen time across selected apps with detailed analytics and insights.',
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
              icon: Icons.insights,
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
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Have questions or feedback? We\'d love to hear from you!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
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
                      style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              '© 2024 ReFocus. All rights reserved.',
              style: GoogleFonts.inter(
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
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: GoogleFonts.inter(
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