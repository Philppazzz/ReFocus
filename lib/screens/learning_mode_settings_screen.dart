import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/services/ml_training_service.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/hybrid_lock_manager.dart';
import 'package:refocus_app/services/ensemble_model_service.dart';
import 'package:refocus_app/screens/model_analytics_screen.dart';

/// Settings screen for learning mode vs rule-based mode
class LearningModeSettingsScreen extends StatefulWidget {
  const LearningModeSettingsScreen({super.key});

  @override
  State<LearningModeSettingsScreen> createState() => _LearningModeSettingsScreenState();
}

class _LearningModeSettingsScreenState extends State<LearningModeSettingsScreen> {
  bool _learningModeEnabled = true;
  bool _ruleBasedEnabled = false;
  bool _isLoading = true;
  Map<String, dynamic>? _modeInfo;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    // Refresh every 5 seconds to show real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      await _refreshData(); // Use separate refresh method that doesn't show loading
    });
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    await _refreshData();
    setState(() => _isLoading = false);
  }

  Future<void> _refreshData() async {
    final learningEnabled = await LearningModeManager.isLearningModeEnabled();
    final ruleBasedEnabled = await LearningModeManager.isRuleBasedEnabled();
    final modeInfo = await LearningModeManager.getModeInfo();

    if (!mounted) return;

    // ✅ OPTIMIZATION: Only update state if values actually changed (prevents unnecessary rebuilds)
    bool needsUpdate = false;
    
    if (_learningModeEnabled != learningEnabled ||
        _ruleBasedEnabled != ruleBasedEnabled) {
      needsUpdate = true;
    }
    
    // Check if mode info changed (compare key fields)
    if (_modeInfo == null || 
        (_modeInfo!['phase'] as String) != (modeInfo['phase'] as String) ||
        (_modeInfo!['days_since_start'] as int) != (modeInfo['days_since_start'] as int) ||
        (_modeInfo!['feedback_count'] as int) != (modeInfo['feedback_count'] as int)) {
      needsUpdate = true;
    }

    if (needsUpdate) {
      setState(() {
        _learningModeEnabled = learningEnabled;
        _ruleBasedEnabled = ruleBasedEnabled;
        _modeInfo = modeInfo;
      });
    }
  }

  Future<void> _toggleLearningMode(bool value) async {
    setState(() {
      _learningModeEnabled = value;
      if (value) {
        _ruleBasedEnabled = false;  // Can't have both enabled
      }
    });

    await LearningModeManager.setLearningModeEnabled(value);
    if (value) {
      await LearningModeManager.setRuleBasedEnabled(false);
    }
    
    await _loadSettings();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value 
            ? 'Learning mode enabled - collecting unbiased data'
            : 'Learning mode disabled'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _toggleRuleBasedMode(bool value) async {
    setState(() {
      _ruleBasedEnabled = value;
      if (value) {
        _learningModeEnabled = false;  // Can't have both enabled
      }
    });

    await LearningModeManager.setRuleBasedEnabled(value);
    if (value) {
      await LearningModeManager.setLearningModeEnabled(false);
    }
    
    await _loadSettings();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value 
            ? 'Rule-based mode enabled - locks active from Day 1'
            : 'Rule-based mode disabled'),
          backgroundColor: const Color(0xFFF59E0B),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'AI Learning Mode',
          style: GoogleFonts.alice(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      'Choose Your Mode',
                      style: GoogleFonts.alice(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select how the app should learn your usage patterns',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Learning Mode Card
                    _buildModeCard(
                      title: 'Learning Mode (Recommended)',
                      subtitle: 'Best for unbiased AI training',
                      icon: Icons.psychology,
                      iconColor: const Color(0xFFA855F7),
                      enabled: _learningModeEnabled,
                      onToggle: _toggleLearningMode,
                      features: [
                        '✅ No locks during learning phase',
                        '✅ Collects unbiased usage data',
                        '✅ Learns your natural patterns',
                        '✅ Better personalization',
                        '⚠️ No protection for 30-60 days',
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Rule-Based Mode Card
                    _buildModeCard(
                      title: 'Rule-Based Mode',
                      subtitle: 'Traditional locks from Day 1',
                      icon: Icons.security,
                      iconColor: const Color(0xFFF59E0B),
                      enabled: _ruleBasedEnabled,
                      onToggle: _toggleRuleBasedMode,
                      features: [
                        '✅ Immediate protection',
                        '✅ Works from Day 1',
                        '✅ Predictable limits',
                        '⚠️ Less personalized',
                        '⚠️ May collect biased data',
                      ],
                    ),

                    const SizedBox(height: 32),

                    // ✅ NEW: Real-Time Model Activity Status (when learning mode is on)
                    if (_learningModeEnabled) _buildRealTimeModelStatusCard(),

                    const SizedBox(height: 20),

                    // ML Training Status Card
                    _buildTrainingStatusCard(),

                    const SizedBox(height: 20),

                    // Current Status
                    if (_modeInfo != null) _buildStatusCard(_modeInfo!),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool enabled,
    required Function(bool) onToggle,
    required List<String> features,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? iconColor : Colors.grey[300]!,
          width: enabled ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: enabled ? iconColor.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.alice(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.alice(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: iconColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        feature,
                        style: GoogleFonts.alice(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> modeInfo) {
    final phase = modeInfo['phase'] as String;
    final daysSinceStart = modeInfo['days_since_start'] as int;
    final feedbackCount = modeInfo['feedback_count'] as int;
    final progress = modeInfo['progress_percentage'] as double;

    String phaseText = 'Unknown';
    Color phaseColor = Colors.grey;
    IconData phaseIcon = Icons.help_outline;

    switch (phase) {
      case 'pure_learning':
        phaseText = 'Pure Learning (Day 1-30)';
        phaseColor = const Color(0xFF3B82F6);
        phaseIcon = Icons.school;
        break;
      case 'soft_learning':
        phaseText = 'Soft Learning (Day 30-60)';
        phaseColor = const Color(0xFFF59E0B);
        phaseIcon = Icons.trending_up;
        break;
      case 'ml_ready':
        phaseText = 'ML Active';
        phaseColor = const Color(0xFF10B981);
        phaseIcon = Icons.psychology;
        break;
      case 'rule_based':
        phaseText = 'Rule-Based Mode';
        phaseColor = const Color(0xFFF59E0B);
        phaseIcon = Icons.security;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(phaseIcon, color: phaseColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'Current Status',
                style: GoogleFonts.alice(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusRow('Mode', phaseText, phaseColor),
          if (modeInfo['learning_mode_enabled'] as bool) ...[
            const SizedBox(height: 12),
            _buildStatusRow('Days Since Start', '$daysSinceStart days', const Color(0xFF3B82F6)),
            const SizedBox(height: 12),
            _buildStatusRow('Feedback Collected', '$feedbackCount / ${modeInfo['min_feedback_needed'] ?? 300}', const Color(0xFFA855F7)),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Training Progress',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    Text(
                      '${progress.toStringAsFixed(1)}%',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFA855F7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.alice(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.alice(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }


  Widget _buildTrainingStatusCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getTrainingStatusWithMetrics(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final status = snapshot.data!;
        final totalFeedback = status['total_feedback'] as int;
        final lastTrainingText = status['last_training_text'] as String;
        final modelTrainedCount = status['model_trained_count'] as int;
        final modelAccuracy = (status['model_accuracy'] as double) * 100;
        final shouldRetrain = status['should_retrain'] as bool;
        final helpfulnessRate = status['helpfulness_rate'] as double? ?? 0.0;
        final helpfulLocks = status['helpful_locks'] as int? ?? 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
                    child: Icon(Icons.psychology, color: Colors.black87, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'ML Training Status',
                    style: GoogleFonts.alice(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatusRow('Total Feedback', '$totalFeedback samples', const Color(0xFFA855F7)),
              const SizedBox(height: 12),
              _buildStatusRow('Model Trained On', '$modelTrainedCount samples', const Color(0xFF3B82F6)),
              if (modelTrainedCount > 0) ...[
                const SizedBox(height: 12),
                // ✅ ENHANCED: Model Accuracy with visual indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Model Accuracy',
                      style: GoogleFonts.alice(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    Row(
                      children: [
                        // Accuracy percentage
                        Text(
                          '${modelAccuracy.toStringAsFixed(1)}%',
                          style: GoogleFonts.alice(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: modelAccuracy >= 70 
                                ? const Color(0xFF10B981) 
                                : (modelAccuracy >= 50 
                                    ? const Color(0xFFF59E0B) 
                                    : Colors.red),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Visual indicator
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: modelAccuracy >= 70 
                                ? const Color(0xFF10B981) 
                                : (modelAccuracy >= 50 
                                    ? const Color(0xFFF59E0B) 
                                    : Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // ✅ ENHANCED: Accuracy evaluation info
                if (modelAccuracy > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: modelAccuracy >= 70 
                          ? const Color(0xFF10B981).withOpacity(0.1)
                          : (modelAccuracy >= 50 
                              ? const Color(0xFFF59E0B).withOpacity(0.1)
                              : Colors.red.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          modelAccuracy >= 70 
                              ? Icons.check_circle_outline
                              : (modelAccuracy >= 50 
                                  ? Icons.info_outline
                                  : Icons.warning_amber_rounded),
                          size: 14,
                          color: modelAccuracy >= 70 
                              ? const Color(0xFF10B981) 
                              : (modelAccuracy >= 50 
                                  ? const Color(0xFFF59E0B) 
                                  : Colors.red),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            modelAccuracy >= 70 
                                ? 'Model performing well'
                                : (modelAccuracy >= 50 
                                    ? 'Model needs more data'
                                    : 'Model accuracy low - retraining recommended'),
                            style: GoogleFonts.alice(
                              fontSize: 11,
                              color: modelAccuracy >= 70 
                                  ? const Color(0xFF10B981) 
                                  : (modelAccuracy >= 50 
                                      ? const Color(0xFFF59E0B) 
                                      : Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              _buildStatusRow('Last Training', lastTrainingText, Colors.grey[700]!),
              // ✅ PROFESSIONAL METRICS: Button to view detailed analytics
              if (modelTrainedCount > 0) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ModelAnalyticsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'View Detailed Analytics',
                          style: GoogleFonts.alice(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios, color: Colors.blue[700], size: 16),
                      ],
                    ),
                  ),
                ),
              ],
              // ✅ ENHANCED: Evaluation Metrics Section
              if (totalFeedback > 0) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Evaluation Metrics',
                  style: GoogleFonts.alice(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                // Helpfulness Rate
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.thumb_up_outlined,
                          size: 16,
                          color: helpfulnessRate >= 50 
                              ? const Color(0xFF10B981) 
                              : const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Helpfulness Rate',
                          style: GoogleFonts.alice(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${helpfulnessRate.toStringAsFixed(1)}%',
                      style: GoogleFonts.alice(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: helpfulnessRate >= 50 
                            ? const Color(0xFF10B981) 
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Helpful vs Not Helpful breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Helpful: $helpfulLocks',
                      style: GoogleFonts.alice(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      'Not Helpful: ${totalFeedback - helpfulLocks}',
                      style: GoogleFonts.alice(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                // ✅ ENHANCED: Data Quality Indicator
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: helpfulnessRate >= 50 
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: helpfulnessRate >= 50 
                          ? const Color(0xFF10B981).withOpacity(0.3)
                          : const Color(0xFFF59E0B).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        helpfulnessRate >= 50 
                            ? Icons.verified_outlined
                            : Icons.info_outline,
                        size: 14,
                        color: helpfulnessRate >= 50 
                            ? const Color(0xFF10B981) 
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          helpfulnessRate >= 50 
                              ? 'Good data quality - model learning effectively'
                              : 'Data quality needs improvement - consider providing more feedback',
                          style: GoogleFonts.alice(
                            fontSize: 11,
                            color: helpfulnessRate >= 50 
                                ? const Color(0xFF10B981) 
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (shouldRetrain) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Training recommended - new feedback available',
                          style: GoogleFonts.alice(
                            fontSize: 12,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: totalFeedback >= 100
                      ? () => _handleManualTraining()
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    totalFeedback >= 100
                        ? 'Train Model Now'
                        : 'Need ${100 - totalFeedback} more feedback',
                    style: GoogleFonts.alice(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleManualTraining() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Training model...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await MLTrainingService.manualTrain();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Model trained successfully!\n'
                'Accuracy: ${((result['accuracy'] as double? ?? 0.0) * 100).toStringAsFixed(1)}%',
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
          // Refresh status
          setState(() {});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${result['error'] ?? 'Training failed'}'),
              backgroundColor: const Color(0xFFF59E0B),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// ✅ ENHANCED: Get training status with evaluation metrics
  Future<Map<String, dynamic>> _getTrainingStatusWithMetrics() async {
    final status = await MLTrainingService.getTrainingStatus();
    
    // Get detailed feedback stats for evaluation
    final feedbackStats = await FeedbackLogger.getStats();
    
    return {
      ...status,
      'helpfulness_rate': feedbackStats['helpfulness_rate'] as double? ?? 0.0,
      'helpful_locks': feedbackStats['helpful_locks'] as int? ?? 0,
    };
  }

  /// ✅ NEW: Get real-time model activity status
  Future<Map<String, dynamic>> _getRealTimeModelStatus() async {
    try {
      // Get ML readiness status
      final mlStatus = await HybridLockManager.getMLStatus();
      
      // Get ensemble model stats
      await EnsembleModelService.initialize();
      final ensembleStats = await EnsembleModelService.getModelStats();
      final userModelStats = ensembleStats['userTrained'] as Map<String, dynamic>;
      final ensembleInfo = ensembleStats['ensemble'] as Map<String, dynamic>;
      
      // Get feedback stats
      final feedbackStats = await FeedbackLogger.getStats();
      final feedbackCount = feedbackStats['total_feedback'] as int;
      
      // Determine model activity status
      String activityStatus;
      String activityDescription;
      Color statusColor;
      IconData statusIcon;
      bool isActive = false;
      bool isTraining = false;
      bool isReady = false;
      bool isGettingReady = false;
      
      // ✅ CRITICAL FIX: Use safe training count (validates model wasn't trained on test data)
      final modelIsValid = userModelStats['isValid'] as bool? ?? true;
      final safeTrainingCount = modelIsValid 
          ? (userModelStats['trainingDataCount'] as int? ?? 0)
          : 0; // If model is invalid (trained on test data), treat as not trained
      final modelTrained = safeTrainingCount > 0;
      final minFeedbackNeeded = mlStatus['min_feedback_needed'] as int? ?? 300;
      final hasEnoughFeedback = feedbackCount >= minFeedbackNeeded;
      final mlReady = mlStatus['ml_ready'] as bool? ?? false;
      
      if (mlReady && modelTrained) {
        // Model is active and making predictions
        activityStatus = 'Active';
        activityDescription = 'Model is actively making predictions';
        statusColor = const Color(0xFF10B981); // Green
        statusIcon = Icons.psychology;
        isActive = true;
        isReady = true;
      } else if (hasEnoughFeedback && !modelTrained) {
        // Has enough feedback but model not trained yet
        activityStatus = 'Ready to Train';
        activityDescription = 'Enough feedback collected - ready for training';
        statusColor = const Color(0xFF3B82F6); // Blue
        statusIcon = Icons.school;
        isGettingReady = true;
      } else if (modelTrained && !mlReady) {
        // Model trained but not enough feedback for ML mode
        activityStatus = 'Training Complete';
        activityDescription = 'Model trained but needs more feedback for ML mode';
        statusColor = const Color(0xFFF59E0B); // Orange
        statusIcon = Icons.check_circle_outline;
        isReady = false;
      } else if (feedbackCount >= 100 && feedbackCount < minFeedbackNeeded) {
        // Collecting feedback
        activityStatus = 'Collecting Data';
        activityDescription = 'Gathering feedback (${feedbackCount}/$minFeedbackNeeded samples)';
        statusColor = const Color(0xFF8B5CF6); // Purple
        statusIcon = Icons.collections;
        isGettingReady = true;
      } else {
        // Just starting
        activityStatus = 'Getting Ready';
        activityDescription = 'Initializing - need more feedback (${feedbackCount}/$minFeedbackNeeded)';
        statusColor = Colors.grey[600]!;
        statusIcon = Icons.hourglass_empty;
        isGettingReady = true;
      }
      
      return {
        'activity_status': activityStatus,
        'activity_description': activityDescription,
        'status_color': statusColor,
        'status_icon': statusIcon,
        'is_active': isActive,
        'is_training': isTraining,
        'is_ready': isReady,
        'is_getting_ready': isGettingReady,
        'ml_ready': mlReady,
        'model_trained': modelTrained,
        'feedback_count': feedbackCount,
        'min_feedback_needed': minFeedbackNeeded,
        'model_accuracy': modelIsValid 
            ? ((userModelStats['accuracy'] as double? ?? 0.0) * 100)
            : 0.0, // ✅ Only show accuracy if model is valid
        'model_is_valid': modelIsValid, // ✅ Flag for UI
        'model_training_count': safeTrainingCount, // ✅ Safe count (excludes test data)
        'rule_based_weight': (ensembleInfo['ruleBasedWeight'] as double? ?? 1.0) * 100,
        'user_trained_weight': (ensembleInfo['userTrainedWeight'] as double? ?? 0.0) * 100,
        'current_source': mlReady ? 'ML Ensemble' : 'Rule-Based',
      };
    } catch (e) {
      print('⚠️ Error getting real-time model status: $e');
      return {
        'activity_status': 'Unknown',
        'activity_description': 'Unable to determine status',
        'status_color': Colors.grey,
        'status_icon': Icons.help_outline,
        'is_active': false,
        'is_training': false,
        'is_ready': false,
        'is_getting_ready': false,
        'ml_ready': false,
        'model_trained': false,
        'feedback_count': 0,
        'min_feedback_needed': 300,
        'model_accuracy': 0.0,
        'rule_based_weight': 100.0,
        'user_trained_weight': 0.0,
        'current_source': 'Rule-Based',
      };
    }
  }

  /// ✅ NEW: Build real-time model activity status card
  Widget _buildRealTimeModelStatusCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getRealTimeModelStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final status = snapshot.data!;
        final activityStatus = status['activity_status'] as String;
        final activityDescription = status['activity_description'] as String;
        final statusColor = status['status_color'] as Color;
        final statusIcon = status['status_icon'] as IconData;
        final isActive = status['is_active'] as bool;
        final isGettingReady = status['is_getting_ready'] as bool;
        final mlReady = status['ml_ready'] as bool;
        final modelTrained = status['model_trained'] as bool;
        final feedbackCount = status['feedback_count'] as int;
        final minFeedbackNeeded = status['min_feedback_needed'] as int? ?? 300;
        final modelAccuracy = (status['model_accuracy'] as double);
        final ruleBasedWeight = (status['rule_based_weight'] as double);
        final userTrainedWeight = (status['user_trained_weight'] as double);
        final currentSource = status['current_source'] as String;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withOpacity(0.1),
                Colors.white,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: statusColor.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status indicator
              Row(
                children: [
                  // Animated status indicator
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcon,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Model Activity Status',
                          style: GoogleFonts.alice(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          activityStatus,
                          style: GoogleFonts.alice(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pulsing indicator for active status
                  if (isActive)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(seconds: 2),
                        builder: (context, value, child) {
                          return Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: statusColor.withOpacity(1.0 - value),
                            ),
                          );
                        },
                        onEnd: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Status description
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      isActive ? Icons.check_circle_outline
                          : isGettingReady ? Icons.hourglass_empty
                          : Icons.info_outline,
                      size: 16,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        activityDescription,
                        style: GoogleFonts.alice(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Model details (only show if model is trained or ready)
              if (modelTrained || mlReady) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                
                // Current prediction source
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Prediction Source',
                      style: GoogleFonts.alice(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: mlReady ? const Color(0xFF10B981).withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentSource,
                        style: GoogleFonts.alice(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: mlReady ? const Color(0xFF10B981) : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Ensemble weights (only if ML is ready)
                if (mlReady) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Ensemble Weights',
                    style: GoogleFonts.alice(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWeightBar('Rule-Based', ruleBasedWeight, const Color(0xFFF59E0B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildWeightBar('User Model', userTrainedWeight, const Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${ruleBasedWeight.toStringAsFixed(0)}%',
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${userTrainedWeight.toStringAsFixed(0)}%',
                        style: GoogleFonts.alice(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
                
                // Model accuracy (if trained)
                if (modelTrained && modelAccuracy > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Model Accuracy',
                        style: GoogleFonts.alice(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '${modelAccuracy.toStringAsFixed(1)}%',
                        style: GoogleFonts.alice(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: modelAccuracy >= 70 
                              ? const Color(0xFF10B981) 
                              : (modelAccuracy >= 50 
                                  ? const Color(0xFFF59E0B) 
                                  : Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              
              // Progress indicator for getting ready
              if (isGettingReady && feedbackCount < minFeedbackNeeded) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Progress to ML Ready',
                  style: GoogleFonts.alice(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: feedbackCount / minFeedbackNeeded.toDouble(),
                  backgroundColor: Colors.grey[300],
                  color: statusColor,
                  minHeight: 8,
                ),
                const SizedBox(height: 4),
                Text(
                  '$feedbackCount / $minFeedbackNeeded feedback samples',
                  style: GoogleFonts.alice(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightBar(String label, double weight, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.alice(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: weight / 100.0,
            backgroundColor: Colors.grey[200],
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

