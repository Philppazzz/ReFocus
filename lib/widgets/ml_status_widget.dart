import 'dart:async';
import 'package:flutter/material.dart';
import 'package:refocus_app/services/hybrid_lock_manager.dart';
import 'package:google_fonts/google_fonts.dart';

/// ✅ ML Status Widget - Shows ML readiness and current lock decision source
/// This widget helps verify ML pipeline is working in real-time
class MLStatusWidget extends StatefulWidget {
  const MLStatusWidget({super.key});

  @override
  State<MLStatusWidget> createState() => _MLStatusWidgetState();
}

class _MLStatusWidgetState extends State<MLStatusWidget> {
  Map<String, dynamic>? _mlStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMLStatus();
    // Refresh every 5 seconds to show real-time status
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _startAutoRefresh();
      }
    });
  }

  void _startAutoRefresh() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _loadMLStatus();
    });
  }

  Future<void> _loadMLStatus() async {
    try {
      final status = await HybridLockManager.getMLStatus();
      if (mounted) {
        setState(() {
          _mlStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('⚠️ Error loading ML status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_mlStatus == null) {
      return const SizedBox.shrink();
    }

    final mlReady = _mlStatus!['ml_ready'] as bool? ?? false;
    final feedbackCount = _mlStatus!['feedback_count'] as int? ?? 0;
    final minFeedbackNeeded = _mlStatus!['min_feedback_needed'] as int? ?? 300;
    final modelTrained = _mlStatus!['model_trained'] as bool? ?? false;
    final modelAccuracy = (_mlStatus!['model_accuracy'] as num?)?.toDouble() ?? 0.0;
    final currentSource = _mlStatus!['current_source'] as String? ?? 'rule_based';

    // Determine status color and icon
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusSubtext;

    if (mlReady && modelTrained) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'ML Active';
      statusSubtext = 'Using ML + Rule-based';
    } else if (modelTrained && !mlReady) {
      statusColor = Colors.orange;
      statusIcon = Icons.pending;
      statusText = 'ML Trained';
      statusSubtext = 'Waiting for activation';
    } else if (feedbackCount >= minFeedbackNeeded) {
      statusColor = Colors.blue;
      statusIcon = Icons.school;
      statusText = 'Ready to Train';
      statusSubtext = '$feedbackCount feedback samples';
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.info;
      statusText = 'Collecting Data';
      statusSubtext = '$feedbackCount / $minFeedbackNeeded samples';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      statusText,
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (mlReady && modelTrained)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          currentSource == 'ml' ? 'ML' : 'Ensemble',
                          style: GoogleFonts.alice(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  statusSubtext,
                  style: GoogleFonts.alice(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
                if (modelTrained && modelAccuracy > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Accuracy: ${(modelAccuracy * 100).toStringAsFixed(1)}%',
                      style: GoogleFonts.alice(
                        fontSize: 10,
                        color: Colors.white60,
                      ),
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

