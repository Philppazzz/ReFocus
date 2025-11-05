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
  Map<String, dynamic>? _todayStats;
  List<Map<String, dynamic>> _weekStats = [];
  List<Map<String, dynamic>> _topAppsByUsage = [];
  List<Map<String, dynamic>> _topAppsByUnlocks = [];
  double _todayTotal = 0.0;
  double _weekTotal = 0.0;
  double _lastWeekTotal = 0.0;
  double _improvementPercent = 0.0;

  double _avgUnlocksPerDay = 0.0;
  double _avgUnlocksPerDayPrev = 0.0;
  double _unlockChangePercent = 0.0;

  // Trends
  String _trendsView = 'daily'; // 'daily' | 'weekly'
  List<double> _weeklyTotals = []; // last 4 weeks

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;
      
      // Load today's stats
      _todayStats = await db.getTodayStats();
      _todayTotal = _todayStats?['daily_usage_hours'] as double? ?? 0.0;

      // Load week stats
      _weekStats = await db.getWeekStats();
      _weekTotal = await db.getWeekTotalUsage();
      _lastWeekTotal = await db.getLastWeekTotalUsage();

      // Calculate improvement
      if (_lastWeekTotal > 0) {
        _improvementPercent = ((_lastWeekTotal - _weekTotal) / _lastWeekTotal) * 100;
      }

      // Get today's date range
      final today = DateTime.now();
      final todayStr = today.toIso8601String().substring(0, 10);
      final weekAgo = today.subtract(const Duration(days: 7));
      final weekAgoStr = weekAgo.toIso8601String().substring(0, 10);

      // Load top apps
      _topAppsByUsage = await db.getTopApps(
        startDate: weekAgoStr,
        endDate: todayStr,
        limit: 10,
      );

      _topAppsByUnlocks = await db.getTopAppsByUnlocks(
        startDate: weekAgoStr,
        endDate: todayStr,
        limit: 10,
      );

      // Map package names to app names
      await _mapPackageNamesToAppNames();

      // Compute average unlocks per day (last 7 days)
      int daysCount = 0;
      int totalUnlocks7 = 0;
      for (int i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = date.toIso8601String().substring(0, 10);
        final summary = await db.getAnalyticsSummary(dateStr);
        totalUnlocks7 += (summary['total_unlocks'] as int? ?? 0);
        daysCount += 1;
      }
      _avgUnlocksPerDay = daysCount > 0 ? totalUnlocks7 / daysCount : 0.0;

      // Previous 7 days
      int prevDaysCount = 0;
      int totalUnlocksPrev7 = 0;
      for (int i = 7; i < 14; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = date.toIso8601String().substring(0, 10);
        final summary = await db.getAnalyticsSummary(dateStr);
        totalUnlocksPrev7 += (summary['total_unlocks'] as int? ?? 0);
        prevDaysCount += 1;
      }
      _avgUnlocksPerDayPrev = prevDaysCount > 0 ? totalUnlocksPrev7 / prevDaysCount : 0.0;
      if (_avgUnlocksPerDayPrev > 0) {
        _unlockChangePercent = ((_avgUnlocksPerDayPrev - _avgUnlocksPerDay) / _avgUnlocksPerDayPrev) * 100;
      } else {
        _unlockChangePercent = 0.0;
      }

      // Prepare weekly totals for last 4 weeks (Mon-Sun buckets)
      final recent = await db.getRecentStats(28);
      _weeklyTotals = _computeWeeklyTotals(recent);

    } catch (e) {
      print("⚠️ Error loading statistics: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<double> _computeWeeklyTotals(List<Map<String, dynamic>> recentDesc) {
    // recentDesc ordered DESC by date; group into chunks of 7 (last 4 weeks)
    final listAsc = recentDesc.reversed.toList();
    final buckets = <double>[];
    double running = 0.0;
    int count = 0;
    for (final row in listAsc) {
      running += ((row['daily_usage_hours'] as num?)?.toDouble() ?? 0.0);
      count++;
      if (count == 7) {
        buckets.add(running);
        running = 0.0;
        count = 0;
      }
    }
    if (count > 0) buckets.add(running);
    // Keep last 4 weeks max
    if (buckets.length > 4) {
      return buckets.sublist(buckets.length - 4);
    }
    return buckets;
  }

  Future<void> _mapPackageNamesToAppNames() async {
    // Load selected apps to map package names
    await SelectedAppsManager.loadFromPrefs();
    final selectedApps = SelectedAppsManager.selectedApps;
    final packageToName = <String, String>{};
    
    for (var app in selectedApps) {
      packageToName[app['package'] ?? ''] = app['name'] ?? 'Unknown';
    }

    // Map package names to app names
    for (var app in _topAppsByUsage) {
      final pkg = app['package_name'] as String? ?? '';
      app['app_name'] = packageToName[pkg] ?? pkg.split('.').last;
    }

    for (var app in _topAppsByUnlocks) {
      final pkg = app['package_name'] as String? ?? '';
      app['app_name'] = packageToName[pkg] ?? pkg.split('.').last;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Usage Statistics',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatistics,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Overview (today + week + comparison)
                    _buildOverview(),
                    const SizedBox(height: 20),

                    // Improvement Summary
                    if (_lastWeekTotal > 0) ...[
                      _buildImprovementSummary(),
                      const SizedBox(height: 20),
                    ],

                    // Usage Trends Chart
                    _buildUsageTrendsChart(),
                    const SizedBox(height: 20),

                    // Most Used Apps
                    _buildMostUsedApps(),
                    const SizedBox(height: 20),

                    // Most Unlocked Apps
                    _buildMostUnlockedApps(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverview() {
    final todayHours = _todayTotal.floor();
    final todayMinutes = ((_todayTotal - todayHours) * 60).floor();
    final weekHours = _weekTotal.floor();
    final weekMinutes = ((_weekTotal - weekHours) * 60).floor();
    final isImproving = _improvementPercent > 0;
    final trendColor = isImproving ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final trendIcon = isImproving ? Icons.trending_down : Icons.trending_up;
    final trendText = isImproving
        ? "${_improvementPercent.abs().toStringAsFixed(1)}% less than last week"
        : "${_improvementPercent.abs().toStringAsFixed(1)}% more than last week";

    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.schedule, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    Text("${todayHours}h ${todayMinutes}m",
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700)),
                  ],
                ),
              ]),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_today, color: Color(0xFF8B5CF6)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("This Week", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                    Text("${weekHours}h ${weekMinutes}m",
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700)),
                  ],
                ),
              ]),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(trendIcon, color: trendColor, size: 20),
              const SizedBox(width: 8),
              Text(trendText, style: GoogleFonts.inter(color: trendColor, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  

  Widget _buildImprovementSummary() {
    final isImproving = _improvementPercent > 0;
    final color = isImproving ? Colors.green : Colors.orange;
    final icon = isImproving ? Icons.trending_down : Icons.trending_up;
    final message = isImproving
        ? "You're using ${_improvementPercent.toStringAsFixed(1)}% less screen time!"
        : "You're using ${_improvementPercent.abs().toStringAsFixed(1)}% more screen time";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Progress This Week",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _metricChip(
                      title: 'Avg daily usage',
                      value: _formatHoursMinutes((_weekStats.isNotEmpty ? _weekTotal / _weekStats.length : 0.0)),
                      color: const Color(0xFF6366F1),
                      icon: Icons.timelapse,
                    ),
                    const SizedBox(width: 10),
                    _metricChip(
                      title: 'Avg unlocks/day',
                      value: _avgUnlocksPerDay.toStringAsFixed(0),
                      color: const Color(0xFFF59E0B),
                      icon: Icons.lock_open,
                      trailing: _avgUnlocksPerDayPrev > 0
                          ? (_unlockChangePercent > 0
                              ? '↓${_unlockChangePercent.abs().toStringAsFixed(0)}%'
                              : '↑${_unlockChangePercent.abs().toStringAsFixed(0)}%')
                          : null,
                      trailingColor: _unlockChangePercent > 0 ? Colors.green : Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHoursMinutes(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).floor();
    return "${h}h ${m}m";
  }

  Widget _metricChip({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    String? trailing,
    Color? trailingColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(height: 2),
                  Text(value,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
            if (trailing != null)
              Text(trailing,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: trailingColor ?? color,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageTrendsChart() {
    if (_weekStats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            "No data available yet",
            style: GoogleFonts.inter(color: Colors.grey),
          ),
        ),
      );
    }

    // Prepare chart data
    final spots = <FlSpot>[];
    final barGroups = <BarChartGroupData>[];
    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    if (_trendsView == 'daily') {
      for (int i = 0; i < _weekStats.length && i < 7; i++) {
        final stat = _weekStats[i];
        final hours = (stat['daily_usage_hours'] as num? ?? 0.0).toDouble();
        final dateStr = stat['date'] as String? ?? '';
        final isToday = dateStr == todayStr;
        spots.add(FlSpot(i.toDouble(), hours));
        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: hours,
                color: isToday ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.show_chart, color: Color(0xFF6366F1)),
              const SizedBox(width: 12),
              Text(
                _trendsView == 'daily' ? "Daily Usage Trends" : "Weekly Usage Trends",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildToggleChip('Daily', _trendsView == 'daily', () {
                      setState(() => _trendsView = 'daily');
                    }),
                    _buildToggleChip('Weekly', _trendsView == 'weekly', () {
                      setState(() => _trendsView = 'weekly');
                    }),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: _trendsView == 'daily'
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: spots.isNotEmpty
                          ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2
                          : 6.0,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xFF6366F1),
                          tooltipRoundedRadius: 8,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < _weekStats.length) {
                                final dateStr = _weekStats[index]['date'] as String? ?? '';
                                final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    weekDays[date.weekday - 1],
                                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                            reservedSize: 30,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              return Text("${value.toInt()}h",
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey));
                            },
                            reservedSize: 40,
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withOpacity(0.1),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: barGroups,
                    ),
                  )
                : LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          isCurved: true,
                          color: const Color(0xFF6366F1),
                          barWidth: 4,
                          spots: List.generate(_weeklyTotals.length, (i) => FlSpot(i.toDouble(), _weeklyTotals[i])),
                          dotData: const FlDotData(show: true),
                        )
                      ],
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < _weeklyTotals.length) {
                                return Text("W${idx + 1}", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey));
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) => Text(
                              "${value.toInt()}h",
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                            ),
                            reservedSize: 40,
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      minX: 0,
                      maxX: (_weeklyTotals.length - 1).clamp(0, 3).toDouble(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withOpacity(0.1),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildMostUsedApps() {
    if (_topAppsByUsage.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.phone_android, color: Color(0xFF6366F1)),
              const SizedBox(width: 12),
              Text(
                "Most Used Apps",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._topAppsByUsage.take(5).map((app) {
            final totalUsage = (app['total_usage'] as num? ?? 0.0).toDouble();
            final hours = (totalUsage / 3600).floor();
            final minutes = ((totalUsage / 60) % 60).floor();
            final appName = app['app_name'] as String? ?? 'Unknown';
            final maxUsage = _topAppsByUsage.first['total_usage'] as num? ?? 1.0;
            final percentage = (totalUsage / maxUsage.toDouble() * 100).clamp(0.0, 100.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _buildAppAvatar(appName),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "${hours}h ${minutes}m",
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildMostUnlockedApps() {
    if (_topAppsByUnlocks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(Icons.lock_open, color: Colors.orange),
              const SizedBox(width: 12),
              Text(
                "Most Unlocked Apps",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._topAppsByUnlocks.take(5).map((app) {
            final unlocks = app['total_unlocks'] as int? ?? 0;
            final appName = app['app_name'] as String? ?? 'Unknown';
            final maxUnlocks = _topAppsByUnlocks.first['total_unlocks'] as int? ?? 1;
            final percentage = (unlocks / maxUnlocks * 100).clamp(0.0, 100.0);
            final totalUnlocksAll = _topAppsByUnlocks.fold<int>(0, (sum, a) => sum + (a['total_unlocks'] as int? ?? 0));
            final percentOfTotal = totalUnlocksAll > 0 ? (unlocks / totalUnlocksAll * 100).toStringAsFixed(0) : '0';

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _buildAppAvatar(appName, tint: Colors.orange),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "$unlocks • ${percentOfTotal}%",
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAppAvatar(String name, {Color tint = const Color(0xFF6366F1)}) {
    final letter = name.isNotEmpty ? name.trim().characters.first.toUpperCase() : '?';
    final bg = tint.withOpacity(0.12);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        letter,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}

