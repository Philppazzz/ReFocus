import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../database_helper.dart';
import '../services/feedback_logger.dart';
import '../services/learning_mode_manager.dart';

/// Shows daily insights during learning phase
/// Gives users value even before ML is ready
class LearningInsightsCard extends StatefulWidget {
  const LearningInsightsCard({super.key});

  @override
  State<LearningInsightsCard> createState() => _LearningInsightsCardState();
}

class _LearningInsightsCardState extends State<LearningInsightsCard> with WidgetsBindingObserver {
  Map<String, dynamic>? _cachedInsights;
  Timer? _refreshTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInsights();
    // ✅ Refresh insights every 5 seconds for real-time accuracy
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadInsights();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User returned to app (e.g., from settings) - refresh immediately
      _loadInsights();
    }
  }

  Future<void> _loadInsights() async {
    try {
      final insights = await _getInsights();
      if (mounted) {
        setState(() {
          _cachedInsights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('⚠️ Error loading insights: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show nothing while loading initially
    if (_isLoading || _cachedInsights == null) {
      return const SizedBox.shrink();
    }

    final insights = _cachedInsights!;
    final isLearning = insights['is_learning'] as bool? ?? false;
    
    if (!isLearning) {
      return const SizedBox.shrink(); // Don't show if not in learning mode
    }

    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: Colors.grey[200]!,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Learning Insights',
                          style: GoogleFonts.alice(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Day ${insights['days_since_start']} of Learning',
                          style: GoogleFonts.alice(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...(_buildInsightItems(insights)),
            ],
          ),
        );
  }

  List<Widget> _buildInsightItems(Map<String, dynamic> insights) {
    final items = <Widget>[];

    // Feedback progress
    final feedbackCount = insights['feedback_count'] as int;
    final feedbackNeeded = insights['feedback_needed'] as int;
    final feedbackPercent = (feedbackCount / feedbackNeeded * 100).clamp(0, 100);
    
    items.add(_buildInsightItem(
      icon: Icons.feedback,
      title: 'Feedback Collected',
      value: '$feedbackCount / $feedbackNeeded',
      subtitle: '${feedbackPercent.toStringAsFixed(0)}% complete',
      color: Colors.black87, // Black theme
    ));

    // Most used category
    if (insights['top_category'] != null) {
      items.add(const SizedBox(height: 12));
      items.add(_buildInsightItem(
        icon: Icons.trending_up,
        title: 'Most Used',
        value: insights['top_category'] as String,
        subtitle: '${insights['top_category_hours']} hours today',
        color: Colors.black87, // Black theme
      ));
    }

    // Daily patterns
    if (insights['peak_hour'] != null) {
      items.add(const SizedBox(height: 12));
      items.add(_buildInsightItem(
        icon: Icons.schedule,
        title: 'Peak Usage Time',
        value: _formatHour(insights['peak_hour'] as int),
        subtitle: 'Your busiest hour',
        color: Colors.black87, // Black theme
      ));
    }

    // Progress indicator
    final daysLeft = (insights['days_until_ready'] as int).clamp(0, 999);
    if (daysLeft > 0 && feedbackCount >= feedbackNeeded) {
      items.add(const SizedBox(height: 12));
      items.add(_buildInsightItem(
        icon: Icons.timer,
        title: 'ML Readiness',
        value: '$daysLeft more days',
        subtitle: 'Need time diversity',
        color: Colors.black87, // Black theme
      ));
    } else if (feedbackCount >= feedbackNeeded && daysLeft == 0) {
      items.add(const SizedBox(height: 12));
      items.add(_buildInsightItem(
        icon: Icons.check_circle,
        title: 'ML Ready Soon!',
        value: 'Checking diversity',
        subtitle: 'Almost there!',
        color: Colors.black87, // Black theme
      ));
    }

    return items;
  }

  Widget _buildInsightItem({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.alice(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.alice(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.alice(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  Future<Map<String, dynamic>> _getInsights() async {
    try {
      // Check if in learning mode
      final isLearning = await LearningModeManager.isLearningModeEnabled();
      if (!isLearning) {
        return {'is_learning': false};
      }
      
      final phase = await LearningModeManager.getLearningPhase();
      if (phase != 'pure_learning' && phase != 'soft_learning') {
        return {'is_learning': false};
      }

      // Get days since start
      final daysSinceStart = await LearningModeManager.getDaysSinceLearningStart();
      
      // Get feedback count
      final feedbackStats = await FeedbackLogger.getStats();
      final feedbackCount = feedbackStats['total_feedback'] as int? ?? 0;
      
      // Get mode info for feedback needed
      final modeInfo = await LearningModeManager.getModeInfo();
      final feedbackNeeded = modeInfo['min_feedback_needed'] as int? ?? 300;
      
      // Calculate days until ready (minimum 5 days)
      final daysUntilReady = (5 - daysSinceStart).clamp(0, 5);
      
      // Get top category (with safety checks for new users)
      String? topCategory;
      String? topCategoryHours;
      
      try {
        final db = await DatabaseHelper.instance.database;
        final today = DateTime.now();
        final dateKey = _dateKey(today);
        
        final categoryResult = await db.rawQuery('''
          SELECT category, SUM(usage_seconds) as total_seconds
          FROM app_details
          WHERE date = ?
          AND category IN ('Social', 'Games', 'Entertainment')
          GROUP BY category
          ORDER BY total_seconds DESC
          LIMIT 1
        ''', [dateKey]);
        
        if (categoryResult.isNotEmpty && categoryResult[0]['category'] != null) {
          topCategory = categoryResult[0]['category'] as String;
          final seconds = (categoryResult[0]['total_seconds'] as num?)?.toDouble() ?? 0;
          if (seconds > 0) {
            topCategoryHours = (seconds / 3600).toStringAsFixed(1);
          }
        }
      } catch (e) {
        print('⚠️ Error getting top category: $e');
        // Continue without top category data
      }
      
      // Get peak hour (with safety checks)
      int? peakHour;
      try {
        final db = await DatabaseHelper.instance.database;
        final hourResult = await db.rawQuery('''
          SELECT CAST(strftime('%H', timestamp / 1000, 'unixepoch', 'localtime') AS INTEGER) as hour,
                 COUNT(*) as event_count
          FROM lock_history
          WHERE date(timestamp / 1000, 'unixepoch', 'localtime') = date('now', 'localtime')
          GROUP BY hour
          ORDER BY event_count DESC
          LIMIT 1
        ''');
        
        if (hourResult.isNotEmpty && hourResult[0]['hour'] != null) {
          peakHour = hourResult[0]['hour'] as int;
        }
      } catch (e) {
        print('⚠️ Error getting peak hour: $e');
        // Continue without peak hour data
      }
      
      return {
        'is_learning': true,
        'days_since_start': daysSinceStart,
        'feedback_count': feedbackCount,
        'feedback_needed': feedbackNeeded,
        'days_until_ready': daysUntilReady,
        'top_category': topCategory,
        'top_category_hours': topCategoryHours,
        'peak_hour': peakHour,
      };
    } catch (e) {
      print('⚠️ Error getting learning insights: $e');
      return {'is_learning': false};
    }
  }

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

