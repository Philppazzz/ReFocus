import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/proactive_feedback_service.dart';

/// Non-blocking dialog for proactive feedback (learning mode)
/// Asks "Would a break be helpful now?" without locking the app
class ProactiveFeedbackDialog extends StatelessWidget {
  final String appName;
  final String appCategory;
  final int dailyUsage;
  final int sessionUsage;
  final int usageLevel;

  const ProactiveFeedbackDialog({
    super.key,
    required this.appName,
    required this.appCategory,
    required this.dailyUsage,
    required this.sessionUsage,
    required this.usageLevel,
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology,
                    color: Colors.blue[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Learning Your Patterns',
                        style: GoogleFonts.alice(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Help us learn when breaks are helpful',
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
            const SizedBox(height: 20),

            // Usage info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\'ve used $appName for $usageLevel minutes',
                      style: GoogleFonts.alice(
                        fontSize: 14,
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
              'Would a break be helpful now?',
              style: GoogleFonts.alice(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps create personalized limits',
              style: GoogleFonts.alice(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _buildFeedbackButton(
                    context: context,
                    label: 'Yes, I need a break',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    wouldBeHelpful: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFeedbackButton(
                    context: context,
                    label: 'No, I\'m fine',
                    icon: Icons.arrow_forward,
                    color: Colors.blue,
                    wouldBeHelpful: false,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              'Note: App is not locked. You can continue using.',
              style: GoogleFonts.alice(
                fontSize: 11,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
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
    required bool wouldBeHelpful,
  }) {
    return ElevatedButton.icon(
      onPressed: () => _submitFeedback(context, wouldBeHelpful: wouldBeHelpful),
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
    required bool wouldBeHelpful,
  }) async {
    // Log proactive feedback
    await ProactiveFeedbackService.logProactiveFeedback(
      appName: appName,
      category: appCategory,
      sessionUsageMinutes: sessionUsage,
      dailyUsageMinutes: dailyUsage,
      wouldBeHelpful: wouldBeHelpful,
    );

    // Close dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    // Show confirmation
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wouldBeHelpful
                ? 'Thanks! We\'ll learn from this. 🙏'
                : 'Got it! Continue using freely.',
          ),
          backgroundColor: wouldBeHelpful ? Colors.green : Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

