import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:refocus_app/services/usage_monitoring_service.dart';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/app_lock_manager.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/widgets/category_usage_card.dart';
import 'package:refocus_app/widgets/weekly_summary_card.dart';
import 'package:refocus_app/database_helper.dart';

/// Main dashboard screen showing real-time usage, insights, and analytics
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ✅ Access singleton monitoring service (don't create new instance)
  final UsageMonitoringService _monitoringService = UsageMonitoringService();
  bool _isLoading = true;
  Timer? _refreshTimer;
  Timer? _sessionRefreshTimer; // ✅ CRITICAL: Real-time session refresh timer
  double _currentSessionMinutes = 0.0; // ✅ CRITICAL: Real-time session minutes (matches home_page)
  Map<String, double> _categoryUsageMinutes = {
    'Social': 0,
    'Games': 0,
    'Entertainment': 0,
    'Others': 0,
  };
  
  // ✅ Learning mode state (matches home_page.dart)
  bool _isInLearningMode = false;
  
  // ✅ Day change tracking for reliable daily reset
  String? _currentDate;
  Timer? _dayChangeChecker;

  @override
  void initState() {
    super.initState();
    // Initialize current date
    _currentDate = DateTime.now().toIso8601String().substring(0, 10);
    _loadDashboardData();
    _startAutoRefresh();
    _startSessionRefresh(); // ✅ CRITICAL: Start real-time session refresh
    _startDayChangeChecker(); // ✅ CRITICAL: Start day change checker
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sessionRefreshTimer?.cancel(); // ✅ Cancel session refresh timer
    _dayChangeChecker?.cancel(); // ✅ Cancel day change checker
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    // ✅ CRITICAL FIX: Refresh every 3 seconds (reduced from 2) to prevent over-incrementing
    // UsageService now has rate limiting (500ms) and lock mechanism to prevent double-counting
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        // ✅ CRITICAL: Force update usage stats before refreshing
        // UsageService now has built-in rate limiting and lock to prevent double-counting
        final platform = const MethodChannel('com.example.refocus/monitor');
        final foregroundApp = await platform.invokeMethod<String>('getForegroundApp');
        if (foregroundApp != null && foregroundApp.isNotEmpty) {
          await UsageService.getUsageStatsWithEvents(
            currentForegroundApp: foregroundApp,
            updateSessionTracking: true,
          );
        }
        await _refreshCategoryUsage();
        // ✅ Force rebuild to update session usage from LockStateManager (real-time)
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print("⚠️ Error in dashboard auto refresh: $e");
        // Continue with refresh even if update fails
        await _refreshCategoryUsage();
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  /// ✅ CRITICAL: Real-time session refresh - updates every 1 second for accurate display
  /// This ensures the session timer updates immediately when user switches apps
  /// Matches home_page.dart behavior for consistency
  void _startSessionRefresh() {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      
      // ✅ CRITICAL: Use LockStateManager.getCurrentSessionMinutes() directly (source of truth)
      // This tracks accumulated time in milliseconds and accounts for 5-minute inactivity threshold
      // LockStateManager already handles combined session across all monitored categories
      final combinedSessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      
      // Only update if value changed (prevents unnecessary rebuilds)
      if (combinedSessionMinutes != _currentSessionMinutes) {
        // ✅ CRITICAL: Double-check mounted before setState (prevents errors if disposed during async operation)
        if (mounted) {
          setState(() {
            _currentSessionMinutes = combinedSessionMinutes;
          });
        }
      }
    });
  }

  /// ✅ CRITICAL: Day change checker - ensures frontend refreshes when day changes
  /// This ensures daily tracking resets properly in both frontend and backend
  /// Weekly stats are NOT affected (they query database for past week)
  void _startDayChangeChecker() {
    _dayChangeChecker?.cancel();
    // Check for day change every minute (catches midnight transitions)
    _dayChangeChecker = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      
      final today = DateTime.now().toIso8601String().substring(0, 10);
      
      // ✅ Day changed - trigger full refresh
      if (_currentDate != null && _currentDate != today) {
        print('🌅 Day change detected in DashboardScreen: $_currentDate → $today');
        print('   Triggering full refresh to reset daily tracking...');
        
        _currentDate = today;
        
        // ✅ Force refresh to pick up backend reset
        // Backend services already reset daily tracking - frontend just needs to refresh
        await _refreshCategoryUsage();
        
        print('✅ DashboardScreen refreshed after day change');
      }
    });
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      // ✅ Check learning mode to determine UI behavior
      final isLearningMode = await LearningModeManager.isLearningModeEnabled();
      final phase = await LearningModeManager.getLearningPhase();
      final isInLearningPhase = isLearningMode && 
          (phase == 'pure_learning' || phase == 'soft_learning');
      
      // ✅ CRITICAL: Get initial session minutes from LockStateManager (source of truth)
      final initialSessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      
      // Get usage from database
      final db = DatabaseHelper.instance;
      final usage = await db.getCategoryUsageForDate(DateTime.now());

      setState(() {
        _isLoading = false;
        _categoryUsageMinutes = usage;
        _currentSessionMinutes = initialSessionMinutes; // ✅ Initialize session minutes
        _isInLearningMode = isInLearningPhase; // ✅ Store learning mode state
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCategoryUsage() async {
    try {
      // ✅ Check learning mode on every refresh (user may switch modes)
      final isLearningMode = await LearningModeManager.isLearningModeEnabled();
      final phase = await LearningModeManager.getLearningPhase();
      final isInLearningPhase = isLearningMode && 
          (phase == 'pure_learning' || phase == 'soft_learning');
      
      // ✅ CRITICAL FIX: Force usage stats update before reading from database
      // This ensures database has latest data from UsageService
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
        print('⚠️ Error updating usage stats before refresh: $e');
        // Continue anyway - database might still have data
      }
      
      // ✅ CRITICAL FIX: Sync session usage with LockStateManager (source of truth)
      // This ensures dashboard shows accurate session time that matches home_page
      // LockStateManager tracks accumulated time in milliseconds and handles 5-minute inactivity
      try {
        // Sync session usage for all monitored categories (shared session)
        await _monitoringService.syncSessionUsage();
      } catch (e) {
        print('⚠️ Error syncing session usage: $e - using cached value');
      }
      
      // ✅ CRITICAL FIX: Read from database AFTER ensuring it's updated
      final usage =
          await DatabaseHelper.instance.getCategoryUsageForDate(DateTime.now());
      
      // ✅ CRITICAL FIX: Get session minutes IMMEDIATELY after reading daily usage
      // This ensures both are synchronized and read from the same point in time
      final sessionMinutes = await LockStateManager.getCurrentSessionMinutes();
      
      // ✅ CRITICAL FIX: Calculate combined daily usage for monitored categories (shared limit)
      final combinedDailyMinutes = (usage['Social'] ?? 0.0) +
                                   (usage['Games'] ?? 0.0) +
                                   (usage['Entertainment'] ?? 0.0);
      
      print("🔍 Dashboard Data Refresh:");
      print("   Social (individual): ${usage['Social']?.toStringAsFixed(1) ?? '0.0'}min");
      print("   Games (individual): ${usage['Games']?.toStringAsFixed(1) ?? '0.0'}min");
      print("   Entertainment (individual): ${usage['Entertainment']?.toStringAsFixed(1) ?? '0.0'}min");
      print("   Combined Daily (Social+Games+Entertainment): ${combinedDailyMinutes.toStringAsFixed(1)}min");
      print("   ✅ Others: ${usage['Others']?.toStringAsFixed(1) ?? '0.0'}min (tracked from all non-monitored apps, messaging apps, system apps)");
      print("   Session (combined): ${sessionMinutes.toStringAsFixed(1)}min (from LockStateManager - synchronized with daily)");
      print("   Learning mode: $isInLearningPhase");
      
      if (!mounted) return;
      setState(() {
        _categoryUsageMinutes = usage;
        _currentSessionMinutes = sessionMinutes; // ✅ Update real-time session minutes
        _isInLearningMode = isInLearningPhase; // ✅ Update learning mode state
      });
    } catch (e) {
      print('⚠️ Error refreshing category usage: $e');
    }
  }

  Future<void> _refreshData() async {
    await _loadDashboardData();
    // Trigger rebuild - this will re-read from singleton
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(
          'Screen Time',
          style: GoogleFonts.alice(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 8),

              // === HEADER SECTION ===
              _buildHeaderCard(),

              const SizedBox(height: 16),

              // === REAL-TIME USAGE SECTION ===
              _buildSectionTitle('Real-Time Usage'),
              const SizedBox(height: 8),
              _buildCategoryUsageSection(),

              const SizedBox(height: 16),

              // === TODAY'S USAGE GRAPH ===
              _buildSectionTitle('Today\'s Usage'),
              const SizedBox(height: 8),
              _buildTodayUsageGraph(),

              const SizedBox(height: 16),

              // === WEEKLY SUMMARY ===
              _buildSectionTitle('Week Summary'),
              const SizedBox(height: 8),
              const WeeklySummaryCard(),

              const SizedBox(height: 16),

              // === QUICK ACTIONS ===
              _buildSectionTitle('Quick Actions'),
              const SizedBox(height: 8),
              _buildQuickActionsSection(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final now = DateTime.now();
    final dateString = DateFormat('EEEE, MMMM d').format(now);
    final hour = now.hour;

    String greeting;
    IconData greetingIcon;

    if (hour < 12) {
      greeting = 'Good Morning';
      greetingIcon = Icons.wb_sunny;
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
      greetingIcon = Icons.wb_sunny_outlined;
    } else {
      greeting = 'Good Evening';
      greetingIcon = Icons.nightlight;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // ✅ Mode-aware gradient (matches home_page.dart)
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.black, const Color.fromARGB(255, 30, 30, 30)], // Always black theme
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3), // Always black shadow
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                greetingIcon, // Always use greeting icon (morning/afternoon/evening)
                color: Colors.white70,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  greeting,
                  style: GoogleFonts.alice(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              // ✅ Learning mode badge (subtle indicator)
              if (_isInLearningMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(left: 8),
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
          ),
          const SizedBox(height: 8),
          Text(
            dateString,
            style: GoogleFonts.alice(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          // ✅ Learning mode info text
          
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.alice(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryUsageSection() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final categories = ['Social', 'Games', 'Entertainment', 'Others'];

    // ✅ CRITICAL FIX: Use real-time session minutes from state (updated every 1 second)
    // This ensures dashboard shows accurate session time that matches home_page
    // _currentSessionMinutes is updated by _startSessionRefresh() timer every 1 second
    final combinedSessionMinutes = _currentSessionMinutes.round();
    
    return Column(
      children: categories.map((category) {
        final isMonitored = category != 'Others';
        
        // ✅ SCREEN TIME DISPLAY: Show INDIVIDUAL daily usage per category (for visibility)
        // This is just for display purposes - lock decisions still use combined values
        final dailyMinutes = (_categoryUsageMinutes[category] ?? 0).round();
        
        // ✅ CRITICAL FIX: For monitored categories, use real-time session from state (updated every 1 second)
        // For Others category, session is not tracked (no session limit for Others)
        // Others category only shows daily usage (no continuous session tracking)
        final sessionMinutes = isMonitored 
            ? combinedSessionMinutes  // Combined session for monitored categories (real-time from LockStateManager)
            : 0;  // Others category has no session tracking
        
        // ✅ SHARED LIMITS: All monitored categories share the same limits (for lock decisions)
        // But display shows individual usage per category (for screen time visibility)
        if (isMonitored) {
          // Get shared thresholds (360 min daily / 120 min session for all)
          return FutureBuilder<Map<String, int>>(
            future: AppLockManager.getThresholds(category),
            builder: (context, snapshot) {
              int dailyLimitMinutes = 360; // Default 6h
              int sessionLimitMinutes = 120; // Default 2h
              
              if (snapshot.hasData) {
                final thresholds = snapshot.data!;
                final currentHour = DateTime.now().hour;
                
                dailyLimitMinutes = thresholds['daily']!;
                sessionLimitMinutes = thresholds['session']!;
                
                // Apply peak hours penalty (6 PM - 11 PM)
                if (currentHour >= 18 && currentHour <= 23) {
                  dailyLimitMinutes = (dailyLimitMinutes * 0.85).round();
                  sessionLimitMinutes = (sessionLimitMinutes * 0.85).round();
                }
              }
              
              // ✅ Show INDIVIDUAL usage per category (for screen time display)
              // Lock decisions still use combined values in the backend
              return CategoryUsageCard(
                category: category,
                dailyUsage: dailyMinutes, // Individual daily usage for this category
                sessionUsage: sessionMinutes, // Individual session usage for this category
                isMonitored: isMonitored,
                dailyLimitMinutes: dailyLimitMinutes, // Shared limit (same for all)
                sessionLimitMinutes: sessionLimitMinutes, // Shared limit (same for all)
              );
            },
          );
        }
        
        // ✅ Others category - tracked but not monitored (no limits)
        // This includes: messaging apps, system apps, and any apps not categorized as Social/Games/Entertainment
        // Usage is tracked and displayed, but doesn't count toward lock limits
        return CategoryUsageCard(
          category: category,
          dailyUsage: dailyMinutes, // ✅ Shows actual usage from database
          sessionUsage: sessionMinutes, // ✅ Shows individual session usage for Others category
          isMonitored: false,
          dailyLimitMinutes: 0,
          sessionLimitMinutes: 0,
        );
      }).toList(),
    );
  }

  Widget _buildQuickActionsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.history,
                  label: 'Lock History',
                  color: Colors.black87,
                  onTap: () {
                    _showLockHistory();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.download,
                  label: 'Export Data',
                  color: Colors.black87,
                  onTap: () {
                    _exportData();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black87, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.alice(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLockHistory() async {
    final db = DatabaseHelper.instance;
    final database = await db.database;

    final result = await database.query(
      'lock_history',
      orderBy: 'timestamp DESC',
      limit: 50,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Lock History',
                    style: GoogleFonts.alice(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: result.isEmpty
                        ? Center(
                            child: Text(
                              'No lock history yet',
                              style: GoogleFonts.alice(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: result.length,
                            itemBuilder: (context, index) {
                              final lock = result[index];
                              final timestamp = lock['timestamp'] as int;
                              final category = lock['category'] as String;
                              final reason = lock['reason'] as String;
                              final duration = lock['lock_duration_seconds'] as int;

                              final dateTime = DateTime.fromMillisecondsSinceEpoch(
                                timestamp,
                              );
                              final dateString = DateFormat('MMM d, hh:mm a').format(dateTime);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.black.withOpacity(0.1),
                                  child: const Icon(
                                    Icons.lock,
                                    color: Colors.black87,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '$category - ${reason.replaceAll('_', ' ')}',
                                  style: GoogleFonts.alice(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  dateString,
                                  style: GoogleFonts.alice(fontSize: 12),
                                ),
                                trailing: Text(
                                  '${(duration / 60).round()} min',
                                  style: GoogleFonts.alice(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Data export feature coming soon!',
          style: GoogleFonts.alice(),
        ),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildTodayUsageGraph() {
    // Calculate total minutes for each category
    final socialMinutes = (_categoryUsageMinutes['Social'] ?? 0).round();
    final gamesMinutes = (_categoryUsageMinutes['Games'] ?? 0).round();
    final entertainmentMinutes = (_categoryUsageMinutes['Entertainment'] ?? 0).round();
    final othersMinutes = (_categoryUsageMinutes['Others'] ?? 0).round();
    
    // ✅ Professional Y-axis scaling (like phone screen time graphs)
    // Round up to next major interval for clean display
    final maxCategoryMinutes = [
      socialMinutes,
      gamesMinutes,
      entertainmentMinutes,
      othersMinutes,
    ].reduce((a, b) => a > b ? a : b);
    
    // Calculate maxY with professional intervals (like iOS/Android screen time)
    // ✅ Allow up to 10 hours (600 minutes) maximum
    double maxY;
    if (maxCategoryMinutes == 0) {
      maxY = 120; // Default 2h for empty data
    } else if (maxCategoryMinutes <= 30) {
      maxY = 120; // 2h max (increased from 1h)
    } else if (maxCategoryMinutes <= 60) {
      maxY = 180; // 3h max (increased from 1.5h)
    } else if (maxCategoryMinutes <= 120) {
      maxY = 240; // 4h max (increased from 3h)
    } else if (maxCategoryMinutes <= 180) {
      maxY = 300; // 5h max (increased from 4h)
    } else if (maxCategoryMinutes <= 240) {
      maxY = 360; // 6h max (increased from 5h)
    } else if (maxCategoryMinutes <= 300) {
      maxY = 420; // 7h max (increased from 6h)
    } else if (maxCategoryMinutes <= 360) {
      maxY = 480; // 8h max (increased from 7h)
    } else if (maxCategoryMinutes <= 420) {
      maxY = 540; // 9h max (increased from 8h)
    } else {
      maxY = 600; // 10h max
    }
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.show_chart,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Today\'s Usage',
                    style: GoogleFonts.alice(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: _buildCategoryBarChart(
                socialMinutes: socialMinutes,
                gamesMinutes: gamesMinutes,
                entertainmentMinutes: entertainmentMinutes,
                othersMinutes: othersMinutes,
                maxY: maxY.toDouble(),
              ),
            ),
            const SizedBox(height: 16),
            // Legend - Use Wrap to prevent overflow
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6, // ✅ Reduced spacing to prevent overflow
              runSpacing: 8,
              children: [
                _buildLegendItem('Social', const Color(0xFF3B82F6), socialMinutes),
                _buildLegendItem('Games', const Color(0xFFF59E0B), gamesMinutes),
                _buildLegendItem('Entertainment', const Color(0xFF8B5CF6), entertainmentMinutes),
                _buildLegendItem('Others', Colors.grey[600]!, othersMinutes),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBarChart({
    required int socialMinutes,
    required int gamesMinutes,
    required int entertainmentMinutes,
    required int othersMinutes,
    required double maxY,
  }) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: socialMinutes.toDouble(),
                color: const Color(0xFF3B82F6),
                width: 30,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: gamesMinutes.toDouble(),
                color: const Color(0xFFF59E0B),
                width: 30,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
          BarChartGroupData(
            x: 2,
            barRods: [
              BarChartRodData(
                toY: entertainmentMinutes.toDouble(),
                color: const Color(0xFF8B5CF6),
                width: 30,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
          BarChartGroupData(
            x: 3,
            barRods: [
              BarChartRodData(
                toY: othersMinutes.toDouble(),
                color: Colors.grey,
                width: 30,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
        ],
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final labels = ['Social', 'Games', 'Entertainment', 'Others'];
                if (value.toInt() >= 0 && value.toInt() < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[value.toInt()],
                      style: GoogleFonts.alice(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              // ✅ Professional intervals like phone screen time (clean, rounded values)
              interval: maxY <= 120 ? 30 : (maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180)),
              getTitlesWidget: (value, meta) {
                final interval = maxY <= 120 ? 30 : (maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180));
                if (value % interval == 0 && value <= maxY && value >= 0) {
                  final hours = (value ~/ 60).toInt();
                  final mins = (value % 60).toInt();
                  // ✅ Clean formatting like phone screen time graphs
                  if (hours == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${mins}m',
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    );
                  } else if (mins == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${hours}h',
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    );
                  }
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          horizontalInterval: maxY <= 120 ? 30 : (maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180)), // ✅ Match axis interval
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[200]!,
              strokeWidth: 0.5,
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final labels = ['Social', 'Games', 'Entertainment', 'Others'];
              final label = labels[group.x.toInt()];
              final usage = rod.toY.toInt();
              final hours = (usage / 60).toStringAsFixed(1);
              return BarTooltipItem(
                '$label\n$usage mins\n($hours hrs)',
                GoogleFonts.alice(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int minutes) {
    // ✅ Format minutes to hours if needed
    String formatTime(int mins) {
      if (mins < 60) return '$mins m';
      final hours = mins ~/ 60;
      final remainingMins = mins % 60;
      if (remainingMins == 0) return '$hours h';
      return '$hours h $remainingMins m';
    }
    
    return SizedBox(
      width: 75, // ✅ Slightly increased width to prevent overflow
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.alice(
              fontSize: 10,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            formatTime(minutes),
            style: GoogleFonts.alice(
              fontSize: 9,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
