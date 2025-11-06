import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/selected_apps.dart';

class UsageStatisticsPage extends StatefulWidget {
  const UsageStatisticsPage({super.key});

  @override
  State<UsageStatisticsPage> createState() => _UsageStatisticsPageState();
}

class _UsageStatisticsPageState extends State<UsageStatisticsPage> {
  bool _isLoading = true;
  
  // Today's data
  double _todayUsageHours = 0.0;
  List<Map<String, dynamic>> _todayTopApps = [];
  List<Map<String, dynamic>> _todayTopUnlocks = [];
  
  // Week's data
  List<Map<String, dynamic>> _weekStats = [];
  List<Map<String, dynamic>> _weekTopApps = [];
  List<Map<String, dynamic>> _weekTopUnlocks = [];
  double _weekTotal = 0.0;
  
  // Improvement data
  double _yesterdayUsage = 0.0;
  double _dailyImprovement = 0.0;
  
  // Graph data
  Map<int, double> _hourlyUsage = {}; // Hour (0-23) -> Minutes (total)
  Map<int, Map<String, double>> _hourlyUsageByApp = {}; // Hour -> {package -> minutes}
  List<Map<String, dynamic>> _weeklyDailyUsage = []; // Daily usage for past 7 days
  List<Map<String, dynamic>> _weeklyDailyUsageByApp = []; // With per-app breakdown
  double _lastWeekTotal = 0.0; // For weekly comparison

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _isLoading = true);

    try {
      // Load selected apps first
      await SelectedAppsManager.loadFromPrefs();
      print('📱 Selected Apps Loaded: ${SelectedAppsManager.selectedApps.length}');
      for (var app in SelectedAppsManager.selectedApps) {
        print('   - ${app['name']} (${app['package']})');
      }
      
      final db = DatabaseHelper.instance;
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      
      // Get today's stats
      final todayStats = await db.getTodayStats();
      _todayUsageHours = (todayStats?['daily_usage_hours'] as num?)?.toDouble() ?? 0.0;
      print('📊 Today Total Usage: ${_todayUsageHours.toStringAsFixed(2)}h');
      
      // Get today's top apps
      _todayTopApps = await db.getTopApps(
        startDate: today.toIso8601String().substring(0, 10),
        endDate: today.toIso8601String().substring(0, 10),
        limit: 3,
      );
      print('📊 Today Top Apps: ${_todayTopApps.length} apps loaded');
      for (var app in _todayTopApps) {
        final pkg = app['app_package'] as String? ?? 'null';
        final seconds = app['total_usage_seconds'] ?? 'null';
        final appName = _getAppName(pkg);
        print('   - Package: $pkg -> Name: $appName (${seconds}s)');
      }
      
      _todayTopUnlocks = await db.getTopAppsByUnlocks(
        startDate: today.toIso8601String().substring(0, 10),
        endDate: today.toIso8601String().substring(0, 10),
        limit: 3,
      );
      print('📊 Today Top Unlocks: ${_todayTopUnlocks.length} apps loaded');
      for (var app in _todayTopUnlocks) {
        print('   - ${app['app_package']}: ${app['total_unlocks']} unlocks');
      }
      
      // Get yesterday's usage for comparison
      final yesterdayStats = await db.getTopApps(
        startDate: yesterday.toIso8601String().substring(0, 10),
        endDate: yesterday.toIso8601String().substring(0, 10),
        limit: 100,
      );
      _yesterdayUsage = yesterdayStats.fold<double>(
        0.0,
        (sum, app) => sum + ((app['total_usage_seconds'] as num?)?.toDouble() ?? 0.0) / 3600,
      );
      
      // Get this week's stats
      _weekStats = await db.getWeekStats();
      _weekTotal = _weekStats.fold<double>(
        0.0,
        (sum, day) => sum + ((day['total_usage_hours'] as num?)?.toDouble() ?? 0.0),
      );
      
      // Get week's top apps
      final weekAgo = today.subtract(const Duration(days: 6));
      _weekTopApps = await db.getTopApps(
        startDate: weekAgo.toIso8601String().substring(0, 10),
        endDate: today.toIso8601String().substring(0, 10),
        limit: 3,
      );
      print('📊 Week Top Apps: ${_weekTopApps.length} apps loaded');
      for (var app in _weekTopApps) {
        print('   - ${app['app_package']}: ${app['total_usage_seconds']}s');
      }
      
      _weekTopUnlocks = await db.getTopAppsByUnlocks(
        startDate: weekAgo.toIso8601String().substring(0, 10),
        endDate: today.toIso8601String().substring(0, 10),
        limit: 3,
      );
      print('📊 Week Top Unlocks: ${_weekTopUnlocks.length} apps loaded');
      for (var app in _weekTopUnlocks) {
        print('   - ${app['app_package']}: ${app['total_unlocks']} unlocks');
      }
      
      // Calculate daily improvement
      if (_yesterdayUsage > 0) {
        _dailyImprovement = ((_yesterdayUsage - _todayUsageHours) / _yesterdayUsage) * 100;
      }
      
      // Load graph data (with per-app breakdown for stacked bars)
      print('🔄 Loading hourly usage data...');
      
      // First check if there's any data in app_details table
      final todayDetails = await db.getTodayAppDetails();
      print('📊 Today App Details: ${todayDetails.length} apps in database');
      if (todayDetails.isNotEmpty) {
        for (var app in todayDetails) {
          print('   - ${app['package_name']}: ${app['usage_seconds']}s');
        }
      }
      
      _hourlyUsageByApp = await db.getTodayHourlyUsageByApp();
      _hourlyUsage = await db.getTodayHourlyUsage();
      print('📊 Hourly Usage: ${_hourlyUsage.length} hours loaded');
      print('📊 Hourly By App: ${_hourlyUsageByApp.length} hours with app breakdown');
      
      // Debug: Print sample hourly data
      if (_hourlyUsageByApp.isNotEmpty) {
        final sampleHour = _hourlyUsageByApp.keys.first;
        final sampleData = _hourlyUsageByApp[sampleHour];
        print('   Sample hour $sampleHour: ${sampleData?.length ?? 0} apps');
        sampleData?.forEach((pkg, mins) {
          print('      - $pkg: ${mins.toStringAsFixed(1)} mins');
        });
      } else {
        print('   ⚠️ No hourly data found - app_details table might be empty');
      }
      
      print('🔄 Loading weekly usage data...');
      _weeklyDailyUsageByApp = await db.getWeeklyDailyUsageByApp();
      _weeklyDailyUsage = await db.getWeeklyDailyUsage();
      print('📊 Weekly Daily Usage: ${_weeklyDailyUsage.length} days loaded');
      print('📊 Weekly By App: ${_weeklyDailyUsageByApp.length} days with app breakdown');
      
      // Debug: Print sample weekly data
      if (_weeklyDailyUsageByApp.isNotEmpty) {
        final sampleDay = _weeklyDailyUsageByApp.first;
        final appsUsage = sampleDay['apps_usage'] as Map<String, double>? ?? {};
        print('   Sample day ${sampleDay['date']}: ${appsUsage.length} apps');
        appsUsage.forEach((pkg, hours) {
          print('      - $pkg: ${hours.toStringAsFixed(2)}h');
        });
      } else {
        print('   ⚠️ No weekly data found - app_details table might be empty');
      }
      
      _lastWeekTotal = await db.getLastWeekTotalUsage();
      print('📊 Last Week Total: ${_lastWeekTotal.toStringAsFixed(2)}h');
      
    } catch (e) {
      print('Error loading statistics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Usage Statistics',
          style: GoogleFonts.alice(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadStatistics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatistics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05,
                  vertical: screenHeight * 0.02,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Improvement Summary Card (Top)
                    _buildImprovementSummary(screenHeight, screenWidth),
                    
                    SizedBox(height: screenHeight * 0.025),
                    
                    // Today's Usage Section
                    _buildSectionTitle('Today\'s Usage', Icons.today),
                    SizedBox(height: screenHeight * 0.015),
                    _buildTodayUsageCard(screenHeight, screenWidth),
                    SizedBox(height: screenHeight * 0.015),
                    _buildTopAppsSection('Most Used Apps', _todayTopApps, screenHeight, screenWidth),
                    SizedBox(height: screenHeight * 0.015),
                    _buildTopAppsSection('Most Unlocked Apps', _todayTopUnlocks, screenHeight, screenWidth, isUnlocks: true),
                    
                    SizedBox(height: screenHeight * 0.03),
                    
                    // This Week's Usage Section
                    _buildSectionTitle('This Week\'s Usage', Icons.calendar_view_week),
                    SizedBox(height: screenHeight * 0.015),
                    _buildWeekChartCard(screenHeight, screenWidth),
                    SizedBox(height: screenHeight * 0.015),
                    _buildTopAppsSection('Most Used Apps This Week', _weekTopApps, screenHeight, screenWidth),
                    SizedBox(height: screenHeight * 0.015),
                    _buildTopAppsSection('Most Unlocked Apps This Week', _weekTopUnlocks, screenHeight, screenWidth, isUnlocks: true),
                    
                    SizedBox(height: screenHeight * 0.03),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.alice(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildImprovementSummary(double screenHeight, double screenWidth) {
    final bool isImproving = _dailyImprovement > 0;
    final bool isFirstDay = _yesterdayUsage == 0;
    
    // Simple improvement status for LSTM judgment
    String statusText;
    IconData icon;
    Color borderColor;
    Color bgColor;
    Color textColor;
    
    if (isFirstDay) {
      statusText = 'Start tracking your progress today';
      icon = Icons.auto_awesome_rounded;
      borderColor = const Color(0xFF6366F1);
      bgColor = const Color(0xFF6366F1).withOpacity(0.08);
      textColor = const Color(0xFF6366F1);
    } else if (isImproving) {
      statusText = 'You are improving! 🎉';
      icon = Icons.trending_up_rounded;
      borderColor = const Color(0xFF10B981);
      bgColor = const Color(0xFF10B981).withOpacity(0.08);
      textColor = const Color(0xFF059669);
    } else {
      statusText = 'You are not improving';
      icon = Icons.trending_down_rounded;
      borderColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFFEF4444).withOpacity(0.08);
      textColor = const Color(0xFFDC2626);
    }
    
    // Format hours and minutes for display
    final todayHours = _todayUsageHours.floor();
    final todayMins = ((_todayUsageHours - todayHours) * 60).round();
    final yesterdayHours = _yesterdayUsage.floor();
    final yesterdayMins = ((_yesterdayUsage - yesterdayHours) * 60).round();
    
    final todayDisplay = todayHours > 0 ? '${todayHours}h ${todayMins}m' : '${todayMins}m';
    final yesterdayDisplay = yesterdayHours > 0 ? '${yesterdayHours}h ${yesterdayMins}m' : '${yesterdayMins}m';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: borderColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: textColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: GoogleFonts.alice(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
                if (!isFirstDay) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Today: $todayDisplay • Yesterday: $yesterdayDisplay',
                    style: GoogleFonts.alice(
                      fontSize: 13,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayUsageCard(double screenHeight, double screenWidth) {
    final hours = _todayUsageHours.floor();
    final minutes = ((_todayUsageHours - hours) * 60).round();
    
    // Comparison with yesterday
    String comparisonText = '';
    Color comparisonColor = Colors.grey;
    IconData comparisonIcon = Icons.remove;
    
    if (_yesterdayUsage > 0) {
      final diff = _todayUsageHours - _yesterdayUsage;
      final percentChange = (diff / _yesterdayUsage * 100).abs();
      
      if (diff > 0) {
        comparisonText = 'Up ${percentChange.toStringAsFixed(0)}% from yesterday';
        comparisonColor = const Color(0xFFEF4444);
        comparisonIcon = Icons.trending_up;
      } else if (diff < 0) {
        comparisonText = 'Down ${percentChange.toStringAsFixed(0)}% from yesterday';
        comparisonColor = const Color(0xFF10B981);
        comparisonIcon = Icons.trending_down;
      } else {
        comparisonText = 'Same as yesterday';
        comparisonColor = Colors.grey;
        comparisonIcon = Icons.remove;
      }
    }
    
    // ✅ SIMPLIFIED: Create simple hourly bars showing total usage (easier to read)
    final now = DateTime.now();
    final currentHour = now.hour;
    final List<BarChartGroupData> barGroups = [];
    
    // Calculate total minutes per hour (simpler than stacked bars)
    Map<int, double> hourlyTotals = {};
    double maxMinutes = 0;
    
    for (int hour = 0; hour <= currentHour; hour++) {
      final hourData = _hourlyUsageByApp[hour] ?? {};
      final totalMinutes = hourData.values.fold(0.0, (sum, val) => sum + val);
      hourlyTotals[hour] = totalMinutes;
      if (totalMinutes > maxMinutes) maxMinutes = totalMinutes;
    }
    
    // Create simple bars (one color per bar - much easier to read)
    for (int hour = 0; hour <= currentHour; hour++) {
      final totalMinutes = hourlyTotals[hour] ?? 0.0;
      final hoursValue = totalMinutes / 60.0;
      
      // Color based on usage intensity
      Color barColor;
      if (hoursValue == 0) {
        barColor = Colors.grey.shade200;
      } else if (hoursValue < 0.5) {
        barColor = const Color(0xFF10B981); // Green (low usage)
      } else if (hoursValue < 1.0) {
        barColor = const Color(0xFFF59E0B); // Orange (medium usage)
      } else {
        barColor = const Color(0xFFEF4444); // Red (high usage)
      }
      
      barGroups.add(
        BarChartGroupData(
          x: hour,
          barRods: [
            BarChartRodData(
              toY: hoursValue,
              width: screenWidth * 0.025, // Wider bars for better visibility
              borderRadius: BorderRadius.circular(6),
              color: barColor,
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxMinutes / 60.0 * 1.1,
                color: Colors.grey.shade100,
              ),
            ),
          ],
        ),
      );
    }
    
    // Set max Y to show at least 1 hour, or scale based on max usage
    final maxY = (maxMinutes / 60.0 * 1.2).clamp(1.0, 5.0);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with total time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today',
                    style: GoogleFonts.alice(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m',
                    style: GoogleFonts.alice(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              if (comparisonText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: comparisonColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(comparisonIcon, size: 16, color: comparisonColor),
                      const SizedBox(width: 4),
                      Text(
                        comparisonText,
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: comparisonColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          SizedBox(height: screenHeight * 0.025),
          
          // Hourly usage chart
          SizedBox(
            height: screenHeight * 0.18,
            child: barGroups.isEmpty || _hourlyUsageByApp.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No usage data yet',
                          style: GoogleFonts.alice(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use your selected apps to see graphs',
                          style: GoogleFonts.alice(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceEvenly,
                      maxY: maxY,
                      minY: 0,
                      barGroups: barGroups,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 2, // Show every 2 hours for better readability
                            getTitlesWidget: (value, meta) {
                              final hour = value.toInt();
                              if (hour % 2 == 0 && hour <= currentHour) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    hour < 10 ? '0$hour:00' : '$hour:00',
                                    style: GoogleFonts.alice(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
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
                            reservedSize: 45,
                            interval: maxY / 4,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const Text('');
                              final hours = value.floor();
                              final mins = ((value - hours) * 60).round();
                              String label;
                              if (hours > 0) {
                                label = mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
                              } else {
                                label = '${mins}m';
                              }
                              return Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: Text(
                                  label,
                                  style: GoogleFonts.alice(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.black87,
                          tooltipRoundedRadius: 10,
                          tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final hour = group.x.toInt();
                            final totalHours = rod.toY;
                            final hours = totalHours.floor();
                            final mins = ((totalHours - hours) * 60).round();
                            
                            String timeLabel;
                            if (hours > 0) {
                              timeLabel = mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
                            } else {
                              timeLabel = '${mins}m';
                            }
                            
                            return BarTooltipItem(
                              '${hour.toString().padLeft(2, '0')}:00 - ${(hour + 1).toString().padLeft(2, '0')}:00\n\n$timeLabel',
                              GoogleFonts.alice(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAppsSection(
    String title,
    List<Map<String, dynamic>> apps,
    double screenHeight,
    double screenWidth, {
    bool isUnlocks = false,
  }) {
    if (apps.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(screenWidth * 0.05),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child:           Text(
            'No data available',
            style: GoogleFonts.alice(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }
    
    // Find max value for progress bars
    final maxValue = apps.fold<double>(
      0.0,
      (max, app) {
        final value = isUnlocks
            ? ((app['total_unlocks'] as num?)?.toDouble() ?? 0.0)
            : ((app['total_usage_seconds'] as num?)?.toDouble() ?? 0.0);
        return value > max ? value : max;
      },
    );
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.alice(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: screenHeight * 0.015),
          ...apps.asMap().entries.map((entry) {
            final index = entry.key;
            final app = entry.value;
            final appPackage = app['app_package'] as String? ?? '';
            final appName = _getAppName(appPackage);
            
            final value = isUnlocks
                ? ((app['total_unlocks'] as num?)?.toDouble() ?? 0.0)
                : ((app['total_usage_seconds'] as num?)?.toDouble() ?? 0.0);
            
            final displayValue = isUnlocks
                ? '${value.toInt()} times'
                : _formatDuration(value.toInt());
            
            final progress = maxValue > 0 ? value / maxValue : 0.0;
            
            return Padding(
              padding: EdgeInsets.only(bottom: index < apps.length - 1 ? screenHeight * 0.015 : 0),
              child: _buildAppRow(
                appName,
                displayValue,
                progress,
                index + 1,
                screenHeight,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAppRow(
    String appName,
    String value,
    double progress,
    int rank,
    double screenHeight,
  ) {
    final rankColors = [
      const Color(0xFFFFD700), // Gold
      const Color(0xFFC0C0C0), // Silver
      const Color(0xFFCD7F32), // Bronze
    ];
    
    final rankColor = rank <= 3 ? rankColors[rank - 1] : Colors.grey;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Rank badge
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: GoogleFonts.alice(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // App name
            Expanded(
              child: Text(
                appName,
                style: GoogleFonts.alice(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Value
            Text(
              value,
              style: GoogleFonts.alice(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6366F1),
              ),
            ),
          ],
        ),
        SizedBox(height: screenHeight * 0.008),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              rank == 1 ? const Color(0xFF6366F1) : Colors.blue.shade300,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekChartCard(double screenHeight, double screenWidth) {
    if (_weeklyDailyUsage.isEmpty) {
      return Container(
        width: double.infinity,
        height: screenHeight * 0.25,
        padding: EdgeInsets.all(screenWidth * 0.05),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'No weekly data available',
            style: GoogleFonts.alice(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }
    
    // Calculate average and comparison
    final weekHours = _weekTotal.floor();
    final weekMins = ((_weekTotal - weekHours) * 60).round();
    final dailyAverage = _weekTotal / 7;
    final avgHours = dailyAverage.floor();
    final avgMins = ((dailyAverage - avgHours) * 60).round();
    
    String comparisonText = '';
    Color comparisonColor = Colors.grey;
    IconData comparisonIcon = Icons.remove;
    
    if (_lastWeekTotal > 0) {
      final diff = _weekTotal - _lastWeekTotal;
      final percentChange = (diff / _lastWeekTotal * 100).abs();
      
      if (diff > 0) {
        comparisonText = 'Up ${percentChange.toStringAsFixed(0)}% from last week';
        comparisonColor = const Color(0xFFEF4444);
        comparisonIcon = Icons.trending_up;
      } else if (diff < 0) {
        comparisonText = 'Down ${percentChange.toStringAsFixed(0)}% from last week';
        comparisonColor = const Color(0xFF10B981);
        comparisonIcon = Icons.trending_down;
      } else {
        comparisonText = 'Same as last week';
        comparisonColor = Colors.grey;
        comparisonIcon = Icons.remove;
      }
    }
    
    // ✅ SIMPLIFIED: Create simple daily bars showing total usage (easier to read)
    final List<BarChartGroupData> barGroups = [];
    double maxHours = 0;
    
    for (int i = 0; i < _weeklyDailyUsageByApp.length; i++) {
      final day = _weeklyDailyUsageByApp[i];
      final totalHours = (day['usage_hours'] as num?)?.toDouble() ?? 0.0;
      
      if (totalHours > maxHours) maxHours = totalHours;
      
      // Color based on usage intensity
      Color barColor;
      if (totalHours == 0) {
        barColor = Colors.grey.shade200;
      } else if (totalHours < 1.0) {
        barColor = const Color(0xFF10B981); // Green (low usage)
      } else if (totalHours < 2.0) {
        barColor = const Color(0xFFF59E0B); // Orange (medium usage)
      } else {
        barColor = const Color(0xFFEF4444); // Red (high usage)
      }
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: totalHours,
              width: screenWidth * 0.09, // Wider bars for better visibility
              borderRadius: BorderRadius.circular(6),
              color: barColor,
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxHours * 1.1,
                color: Colors.grey.shade100,
              ),
            ),
          ],
        ),
      );
    }
    
    final maxY = (maxHours * 1.3).clamp(1.0, 10.0);
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with total and average
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This Week',
                    style: GoogleFonts.alice(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    weekHours > 0 ? '${weekHours}h ${weekMins}m' : '${weekMins}m',
                    style: GoogleFonts.alice(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Daily Avg: ${avgHours > 0 ? '${avgHours}h ${avgMins}m' : '${avgMins}m'}',
                    style: GoogleFonts.alice(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (comparisonText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: comparisonColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(comparisonIcon, size: 16, color: comparisonColor),
                      const SizedBox(width: 4),
                      Text(
                        comparisonText,
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: comparisonColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          
          SizedBox(height: screenHeight * 0.025),
          
          // Weekly bar chart with average line
          SizedBox(
            height: screenHeight * 0.22,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: 0,
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _weeklyDailyUsage.length) {
                          final dayName = _weeklyDailyUsage[index]['day_name'] as String? ?? '';
                          final isToday = _weeklyDailyUsage[index]['is_today'] as bool? ?? false;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              dayName,
                              style: GoogleFonts.alice(
                                fontSize: 12,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                                color: isToday ? const Color(0xFF6366F1) : Colors.black87,
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
                      interval: maxY / 4,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const Text('');
                        final hours = value.floor();
                        final mins = ((value - hours) * 60).round();
                        String label;
                        if (hours > 0) {
                          label = mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
                        } else {
                          label = '${mins}m';
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Text(
                            label,
                            style: GoogleFonts.alice(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.black87,
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(8),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = _weeklyDailyUsage[group.x.toInt()];
                      final dayName = day['day_name'] as String? ?? '';
                      final totalHours = rod.toY;
                      final hours = totalHours.floor();
                      final mins = ((totalHours - hours) * 60).round();
                      
                      String timeLabel;
                      if (hours > 0) {
                        timeLabel = mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
                      } else {
                        timeLabel = '${mins}m';
                      }
                      
                      return BarTooltipItem(
                        '$dayName\n\n$timeLabel',
                        GoogleFonts.alice(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                // Add average line
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: dailyAverage,
                      color: const Color(0xFFF59E0B).withOpacity(0.6),
                      strokeWidth: 2,
                      dashArray: [5, 5],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        padding: const EdgeInsets.only(right: 5, bottom: 5),
                        style: GoogleFonts.alice(
                          fontSize: 10,
                          color: const Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                        labelResolver: (line) => 'Avg',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getAppName(String packageName) {
    if (packageName.isEmpty || packageName == 'null') {
      print('⚠️ Empty or null package name received');
      return 'Unknown App';
    }
    
    // Known app names mapping (same as in MainActivity.kt)
    const knownApps = {
      'com.facebook.katana': 'Facebook',
      'com.facebook.lite': 'Facebook Lite',
      'com.facebook.orca': 'Messenger',
      'com.instagram.android': 'Instagram',
      'com.twitter.android': 'X (Twitter)',
      'com.snapchat.android': 'Snapchat',
      'com.tiktok.android': 'TikTok',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.whatsapp': 'WhatsApp',
      'com.whatsapp.w4b': 'WhatsApp Business',
      'org.telegram.messenger': 'Telegram',
      'com.discord': 'Discord',
      'com.reddit.frontpage': 'Reddit',
      'com.viber.voip': 'Viber',
      'com.google.android.youtube': 'YouTube',
      'com.google.android.apps.youtube.music': 'YouTube Music',
      'com.linkedin.android': 'LinkedIn',
      'com.bereal.ft': 'BeReal',
      'com.pinterest': 'Pinterest',
      'com.tumblr': 'Tumblr',
      'com.clubhouse.app': 'Clubhouse',
      'com.instagram.barcelona': 'Threads',
    };
    
    try {
      // First, try known apps mapping
      if (knownApps.containsKey(packageName)) {
        final name = knownApps[packageName]!;
        print('✅ Found in known apps: $packageName -> $name');
        return name;
      }
      
      // Second, try to find in selected apps
      print('🔍 Searching in selected apps (${SelectedAppsManager.selectedApps.length} apps)...');
      for (var app in SelectedAppsManager.selectedApps) {
        final appPkg = app['package'];
        print('   Comparing: $packageName == $appPkg');
        if (appPkg == packageName) {
          final name = app['name'];
          if (name != null && name.isNotEmpty) {
            print('✅ Found in selected apps: $packageName -> $name');
            return name;
          }
        }
      }
      
      // If not found, return a readable name from package
      print('⚠️ App not found in known apps or selected apps: $packageName');
      final parts = packageName.split('.');
      if (parts.isNotEmpty) {
        // Capitalize first letter
        final lastPart = parts.last;
        final fallbackName = lastPart[0].toUpperCase() + lastPart.substring(1);
        print('   Using fallback name: $fallbackName');
        return fallbackName;
      }
      return packageName;
    } catch (e) {
      print('⚠️ Error getting app name for $packageName: $e');
      return packageName.split('.').last;
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final mins = (seconds / 60).round();
      return '${mins}m';
    } else {
      final hours = seconds ~/ 3600;
      final mins = (seconds % 3600) ~/ 60;
      if (mins == 0) {
        return '${hours}h';
      }
      return '${hours}h ${mins}m';
    }
  }
}
