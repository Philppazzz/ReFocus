import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/feedback_logger.dart';
import 'package:refocus_app/services/app_lock_manager.dart';

/// Dialog shown after app lock to collect user feedback
/// This provides REAL labels for ML training
/// Note: Feedback is for ML training only - use emergency button for emergencies
class LockFeedbackDialog extends StatelessWidget {
  final String appName;
  final String appCategory;
  final int dailyUsage;
  final int sessionUsage;
  final String lockReason;
  final String predictionSource; // 'ml' or 'rule_based'
  final double? modelConfidence;

  const LockFeedbackDialog({
    super.key,
    required this.appName,
    required this.appCategory,
    required this.dailyUsage,
    required this.sessionUsage,
    required this.lockReason,
    this.predictionSource = 'rule_based',
    this.modelConfidence,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_clock,
                    color: Colors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Locked',
                        style: GoogleFonts.alice(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        appName,
                        style: GoogleFonts.alice(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Lock reason
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lockReason,
                      style: GoogleFonts.alice(
                        fontSize: 13,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Question
            Text(
              'Was this lock helpful?',
              style: GoogleFonts.alice(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps improve the AI predictions',
              style: GoogleFonts.alice(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons (feedback only - no unlock)
            Row(
              children: [
                Expanded(
                  child: _buildFeedbackButton(
                    context: context,
                    label: 'Yes, I needed a break',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    wasHelpful: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFeedbackButton(
                    context: context,
                    label: 'No, it wasn\'t helpful',
                    icon: Icons.cancel,
                    color: Colors.orange,
                    wasHelpful: false,
                  ),
                ),
              ],
            ),
            
            // Info message
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your feedback helps improve AI predictions. Use emergency button for emergencies.',
                      style: GoogleFonts.alice(
                        fontSize: 11,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ML indicator
            if (predictionSource == 'ml' && modelConfidence != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.psychology, color: Colors.purple[700], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'AI Prediction (${(modelConfidence! * 100).toStringAsFixed(0)}% confidence)',
                      style: GoogleFonts.alice(
                        fontSize: 11,
                        color: Colors.purple[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    required bool wasHelpful,
  }) {
    return ElevatedButton.icon(
      onPressed: () => _submitFeedback(
        context,
        wasHelpful: wasHelpful,
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.alice(fontSize: 12),
        textAlign: TextAlign.center,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _submitFeedback(
    BuildContext context, {
    required bool wasHelpful,
  }) async {
    try {
      // ✅ CRITICAL: Ensure all required data is valid before logging
      if (appName.isEmpty || appCategory.isEmpty) {
        print('⚠️ Invalid feedback data: appName=$appName, appCategory=$appCategory');
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Invalid app data'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // ✅ SAFEGUARD 1: Usage-based validation - check if feedback contradicts usage patterns
      final validationResult = await _validateFeedbackAgainstUsage(wasHelpful);
      if (validationResult['shouldWarn'] == true) {
        // Show warning dialog and ask for confirmation
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
                const SizedBox(width: 12),
                const Text('Confirm Feedback'),
              ],
            ),
            content: Text(validationResult['warningMessage'] as String),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.orange[700]),
                child: const Text('Yes, Continue'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) {
          // User cancelled - don't log feedback
          return;
        }
      }
      
      // ✅ SAFEGUARD 2: Confirmation dialog before logging
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                wasHelpful ? Icons.check_circle : Icons.cancel,
                color: wasHelpful ? Colors.green : Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text('Confirm Feedback'),
            ],
          ),
          content: Text(
            wasHelpful
                ? 'You marked this lock as "Helpful". This means you needed a break at this usage level.\n\nContinue?'
                : 'You marked this lock as "Not Helpful". This means you didn\'t need a break at this usage level.\n\nContinue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: wasHelpful ? Colors.green : Colors.orange,
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) {
        // User cancelled - don't log feedback
        return;
      }
      
      // ✅ VALIDATION: Ensure usage values are reasonable
      if (dailyUsage < 0 || dailyUsage > 1440 || sessionUsage < 0 || sessionUsage > 1440) {
        print('⚠️ Invalid usage values: daily=$dailyUsage, session=$sessionUsage');
        // Still log but with clamped values
        final clampedDaily = dailyUsage.clamp(0, 1440);
        final clampedSession = sessionUsage.clamp(0, 1440);
        
        await FeedbackLogger.logLockFeedback(
          appName: appName,
          appCategory: appCategory,
          dailyUsageMinutes: clampedDaily,
          sessionUsageMinutes: clampedSession,
          wasHelpful: wasHelpful,
          lockReason: lockReason,
          predictionSource: predictionSource,
          modelConfidence: modelConfidence,
          packageName: appName, // Use appName as package name (it's usually the package)
        );
      } else {
        // Log feedback (for ML training only - no unlock)
        await FeedbackLogger.logLockFeedback(
          appName: appName,
          appCategory: appCategory,
          dailyUsageMinutes: dailyUsage,
          sessionUsageMinutes: sessionUsage,
          wasHelpful: wasHelpful,
          lockReason: lockReason,
          predictionSource: predictionSource,
          modelConfidence: modelConfidence,
          packageName: appName, // Use appName as package name (it's usually the package)
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error logging feedback: $e');
      print('Stack trace: $stackTrace');
      // ✅ SAFE FALLBACK: Show error but don't crash
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving feedback: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return; // Don't close dialog if logging failed
    }

    // Close dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // ✅ SAFEGUARD 3: Show undo option for 30 seconds
    if (context.mounted) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final undoKey = GlobalKey();
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          key: undoKey,
          content: Text(
            wasHelpful
                ? 'Feedback saved: "Helpful" ✓'
                : 'Feedback saved: "Not Helpful" ✓',
          ),
          backgroundColor: wasHelpful ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 30),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: Colors.white,
            onPressed: () async {
              // ✅ UNDO: Delete the last feedback entry
              try {
                await FeedbackLogger.undoLastFeedback();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Feedback undone ✓'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                print('⚠️ Error undoing feedback: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not undo feedback'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
        ),
      );
    }
  }

  /// ✅ SAFEGUARD 1: Validate feedback against usage patterns
  /// Warns user if feedback contradicts usage (e.g., "Not helpful" at 95% usage)
  Future<Map<String, dynamic>> _validateFeedbackAgainstUsage(bool wasHelpful) async {
    try {
      // Get thresholds for this category
      final thresholds = await AppLockManager.getThresholds(appCategory);
      final dailyLimit = thresholds['daily'] ?? 360;
      final sessionLimit = thresholds['session'] ?? 120;
      
      // Calculate usage percentages
      final dailyPercentage = (dailyUsage / dailyLimit) * 100;
      final sessionPercentage = (sessionUsage / sessionLimit) * 100;
      final maxPercentage = dailyPercentage > sessionPercentage ? dailyPercentage : sessionPercentage;
      
      // ✅ VALIDATION RULES:
      // 1. If usage is very high (>90%) and user says "Not helpful" → warn
      // 2. If usage is very low (<20%) and user says "Helpful" → warn
      
      if (!wasHelpful && maxPercentage >= 90) {
        // High usage but user says "Not helpful" - might be accidental
        return {
          'shouldWarn': true,
          'warningMessage': 'You\'ve used ${maxPercentage.toStringAsFixed(0)}% of your limit (${_formatUsage()}).\n\n'
              'Are you sure this lock wasn\'t helpful? This seems like a high usage level.',
        };
      }
      
      if (wasHelpful && maxPercentage < 20) {
        // Low usage but user says "Helpful" - might be accidental
        return {
          'shouldWarn': true,
          'warningMessage': 'You\'ve only used ${maxPercentage.toStringAsFixed(0)}% of your limit (${_formatUsage()}).\n\n'
              'Are you sure you needed a break at this low usage level?',
        };
      }
      
      // No warning needed
      return {'shouldWarn': false};
    } catch (e) {
      print('⚠️ Error validating feedback: $e');
      // If validation fails, don't block feedback - just return no warning
      return {'shouldWarn': false};
    }
  }

  String _formatUsage() {
    if (dailyUsage >= 60) {
      return '${(dailyUsage / 60).toStringAsFixed(1)}h daily';
    } else {
      return '${dailyUsage}m daily';
    }
  }
}

