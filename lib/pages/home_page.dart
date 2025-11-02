import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_picker_page.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/services/limit_manager.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/pages/lock_screen.dart';

/// ------------------- GLOBAL SINGLETON -------------------
class AppState {
  static final AppState _instance = AppState._internal();
  bool isOverrideEnabled = false;

  factory AppState() => _instance;
  AppState._internal();
}

/// ------------------- SELECTED APPS MANAGER -------------------
class SelectedAppsManager {
  static List<Map<String, String>> selectedApps = [];
}

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    MonitorService.stopMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchUsage();
      _checkCooldown();
    }
  }

  Future<void> _loadSelectedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('selectedApps');
    if (jsonString != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        SelectedAppsManager.selectedApps = decodedList
            .map<Map<String, String>>(
                (item) => Map<String, String>.from(item as Map))
            .toList();
      } catch (_) {
        SelectedAppsManager.selectedApps = [];
      }
    }
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

      if (mounted) {
        setState(() {
          _usageStats = newData;
          _isLoading = false;
          _lastUpdateTime = _formatTime(DateTime.now());
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
    final cooldown = await LimitManager.getActiveCooldown();
    if (mounted) {
      setState(() {
        _cooldownInfo = cooldown;
      });
      
      // Show lock screen if cooldown active
      if (cooldown != null && Navigator.of(context).canPop() == false) {
        _showLockScreen(cooldown);
      }
    }
  }

  void _showLockScreen(Map<String, dynamic> cooldown) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LockScreen(
          reason: cooldown['reason'],
          remainingSeconds: cooldown['remainingSeconds'],
          appName: cooldown['appName'],
        ),
        fullscreenDialog: true,
      ),
    ).then((_) {
      // Refresh when lock screen closes
      _checkCooldown();
    });
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
  }

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final totalUsage =
        _usageStats?['daily_usage_hours']?.toStringAsFixed(2) ?? "0.00";
    final maxSession = _usageStats?['max_session']?.toStringAsFixed(1) ?? "0.0";
    final longestApp = _usageStats?['longest_session_app'] ?? "None";
    final mostUnlockedApp = _usageStats?['most_unlock_app'] ?? "None";
    final unlockCount = _usageStats?['most_unlock_count'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: GoogleFonts.alice(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
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
                        _buildStatCardContainer(
                          icon: Icons.access_time,
                          title: "Today's Screen Time",
                          value: "${_usageStats?['daily_usage_hours']?.floor() ?? 0} h",
                          subtitle: "${((_usageStats?['daily_usage_hours'] ?? 0) * 60 % 60).toInt()} min",
                          gradient: const LinearGradient(
                            colors: [Colors.black, Color.fromARGB(255, 11, 12, 12)],
                          ),
                        ),

                        const SizedBox(height: 24),
                        _buildStatCard(
                          icon: Icons.timer_outlined,
                          title: "Longest Binge Session",
                          subtitle: longestApp,
                          value: "$maxSession mins",
                          color: Colors.black,
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Quick Stats",
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_isLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildQuickStats(
                            totalUsage, maxSession, longestApp, mostUnlockedApp, unlockCount),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// --- UI BUILDERS ---
  Widget _buildStatCardContainer({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Gradient gradient,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: gradient,
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
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold)),
          Text(subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
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

  Widget _buildQuickStats(String totalUsage, String longestSession, String longestApp,
      String mostUnlockedApp, int unlockCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickStatRow("📱 Total Today:", "$totalUsage hours"),
          const Divider(height: 24),
          _buildQuickStatRow("⏱️ Longest Binge:", "$longestApp ($longestSession mins)"),
          const Divider(height: 24),
          _buildQuickStatRow("🔓 Most Opened:", "$mostUnlockedApp ($unlockCount times)"),
        ],
      ),
    );
  }

  Widget _buildQuickStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, color: Colors.grey)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
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
    setState(() {
      appState.isOverrideEnabled = !appState.isOverrideEnabled;
      if (appState.isOverrideEnabled) {
        _controller.repeat(reverse: true);
        // Clear cooldown when override enabled
        LimitManager.clearCooldown();
      } else {
        _controller.stop();
      }
    });
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
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.white),
                title: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () async {
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
      appBar: AppBar(title: const Text('About Us'), backgroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.black)),
      body: const Center(child: Text('This is the About page')),
    );
  }
}