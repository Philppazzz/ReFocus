import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:refocus_app/database_helper.dart';

/// Card showing weekly usage summary with charts and statistics
class WeeklySummaryCard extends StatefulWidget {
  const WeeklySummaryCard({super.key});

  @override
  State<WeeklySummaryCard> createState() => _WeeklySummaryCardState();
}

class _WeeklySummaryCardState extends State<WeeklySummaryCard> {
  Map<String, int> _dailyUsage = {}; // Map of date -> total minutes
  int _totalViolations = 0;
  int _avgDailyUsage = 0;
  String _bestDay = 'None';
  String? _improvementTip;
  bool _isLoading = true;
  Timer? _refreshTimer;

  String _formatDateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  @override
  void initState() {
    super.initState();
    _loadWeeklyStats();
    // ✅ Refresh weekly stats every 30 seconds to keep data current
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _loadWeeklyStats();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWeeklyStats() async {
    setState(() => _isLoading = true);

    try {
      final db = DatabaseHelper.instance;

      // Get last 7 days of data
      final now = DateTime.now();
      final List<DateTime> last7Days = List.generate(
        7,
        (index) => now.subtract(Duration(days: 6 - index)),
      );

      final usageTotals =
          await db.getUsageTotalsSince(now.subtract(const Duration(days: 6)));

      Map<String, int> dailyUsageMap = {};

      for (var day in last7Days) {
        final dateKey = DateFormat('E').format(day);
        final storageKey = _formatDateKey(day);
        final minutes = (usageTotals[storageKey] ?? 0).round();
        dailyUsageMap[dateKey] = minutes;
      }

      // Get weekly violations count
      final weekStart = now.subtract(const Duration(days: 7));
      final weekTimestamp = weekStart.millisecondsSinceEpoch;

      final database = await db.database;
      final violationsResult = await database.rawQuery('''
        SELECT COUNT(*) as count
        FROM lock_history
        WHERE timestamp >= ?
      ''', [weekTimestamp]);

      final violationsCount = violationsResult.first['count'] as int? ?? 0;

      // Calculate average daily usage
      final totalMinutes = dailyUsageMap.values.fold<int>(0, (sum, val) => sum + val);
      final avgMinutes = (totalMinutes / 7).round();

      // Find best day (lowest usage)
      String bestDayKey = 'None';
      int lowestUsage = 999999;
      dailyUsageMap.forEach((day, usage) {
        if (usage > 0 && usage < lowestUsage) {
          lowestUsage = usage;
          bestDayKey = day;
        }
      });

      // Generate improvement tip
      String? tip;
      if (violationsCount > 5) {
        tip = 'You had $violationsCount violations this week. Try setting reminders to take breaks!';
      } else if (violationsCount > 0) {
        tip = 'Good progress! Only $violationsCount ${violationsCount == 1 ? 'violation' : 'violations'} this week.';
      } else if (avgMinutes > 180) {
        tip = 'Great job avoiding violations! Consider reducing daily usage for even better results.';
      } else if (avgMinutes > 120) {
        tip = 'You\'re managing your usage well! Keep maintaining this healthy balance.';
      } else {
        tip = 'Excellent! You\'re maintaining very healthy usage patterns.';
      }

      setState(() {
        _dailyUsage = dailyUsageMap;
        _totalViolations = violationsCount;
        _avgDailyUsage = avgMinutes;
        _bestDay = bestDayKey;
        _improvementTip = tip;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading weekly stats: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart,
                      color: Colors.black87,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'This Week',
                    style: GoogleFonts.alice(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              if (!_isLoading) ...[
                // Bar chart
                SizedBox(
                  height: 180,
                  child: _buildBarChart(),
                ),

                const SizedBox(height: 24),

                // Summary stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      label: 'Total Violations',
                      value: '$_totalViolations',
                      icon: Icons.warning_amber_outlined,
                      color: const Color(0xFFDC2626),
                    ),
                    _buildStatColumn(
                      label: 'Avg Daily Usage',
                      value: '$_avgDailyUsage mins',
                      icon: Icons.timer_outlined,
                      color: const Color(0xFF3B82F6),
                    ),
                    _buildStatColumn(
                      label: 'Best Day',
                      value: _bestDay,
                      icon: Icons.star_outline,
                      color: const Color(0xFF3B82F6), // Blue instead of green
                    ),
                  ],
                ),

                // Improvement tip
                if (_improvementTip != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _totalViolations > 3
                          ? const Color(0xFFF59E0B).withOpacity(0.1)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _totalViolations > 3
                            ? const Color(0xFFF59E0B).withOpacity(0.3)
                            : Colors.grey[400]!,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _totalViolations > 3
                              ? Icons.trending_up
                              : Icons.trending_down,
                          color: _totalViolations > 3
                              ? const Color(0xFFF59E0B)
                              : Colors.grey[700],
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weekly Insight',
                                style: GoogleFonts.alice(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _totalViolations > 3
                                      ? const Color(0xFFF59E0B)
                                      : Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _improvementTip!,
                                style: GoogleFonts.alice(
                                  fontSize: 12,
                                  color: Colors.grey[800],
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    if (_dailyUsage.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: GoogleFonts.alice(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    // Get ordered list of days
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final barGroups = <BarChartGroupData>[];

    for (int i = 0; i < days.length; i++) {
      final day = days[i];
      final usage = _dailyUsage[day] ?? 0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: usage.toDouble(),
              color: _getBarColor(usage),
              width: 20,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Professional Y-axis scaling (like phone screen time graphs)
    final maxUsage = _dailyUsage.values.isEmpty ? 0 : _dailyUsage.values.reduce((a, b) => a > b ? a : b);
    
    // Calculate maxY with professional intervals (like iOS/Android screen time)
    // ✅ Allow up to 10 hours (600 minutes) maximum
    double maxY;
    if (maxUsage == 0) {
      maxY = 240; // Default 4h for empty data (increased from 3h)
    } else if (maxUsage <= 60) {
      maxY = 180; // 3h max (increased from 2h)
    } else if (maxUsage <= 120) {
      maxY = 240; // 4h max (increased from 3h)
    } else if (maxUsage <= 180) {
      maxY = 300; // 5h max (increased from 4h)
    } else if (maxUsage <= 240) {
      maxY = 360; // 6h max (increased from 5h)
    } else if (maxUsage <= 300) {
      maxY = 420; // 7h max (increased from 6h)
    } else if (maxUsage <= 360) {
      maxY = 480; // 8h max (increased from 7h)
    } else if (maxUsage <= 420) {
      maxY = 540; // 9h max (increased from 8h)
    } else {
      maxY = 600; // 10h max
    }
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY.toDouble(),
        barGroups: barGroups,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < days.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      days[value.toInt()],
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
              interval: maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180),
              getTitlesWidget: (value, meta) {
                final interval = maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180);
                if (value % interval == 0 && value <= maxY && value >= 0) {
                  final hours = (value ~/ 60).toInt();
                  // ✅ Clean formatting like phone screen time graphs (hours only for clarity)
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
          horizontalInterval: maxY <= 240 ? 60 : (maxY <= 420 ? 120 : 180), // ✅ Match axis interval
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
              final day = days[group.x.toInt()];
              final usage = rod.toY.toInt();
              final hours = (usage / 60).toStringAsFixed(1);
              return BarTooltipItem(
                '$day\n$usage mins\n($hours hrs)',
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

  Color _getBarColor(int minutes) {
    // ✅ Black/white theme: black for normal, orange/red for high usage
    if (minutes >= 240) return const Color(0xFFDC2626); // 4+ hours - red
    if (minutes >= 180) return const Color(0xFFF59E0B); // 3+ hours - orange
    return Colors.grey[800]!; // < 3 hours - dark grey/black (no green)
  }

  Widget _buildStatColumn({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.alice(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.alice(
            fontSize: 11,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
