import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Individual category usage card showing daily usage only
/// ✅ DISPLAY ONLY: Shows individual daily usage per category for visibility
/// Lock decisions still use combined values (Social + Games + Entertainment)
class CategoryUsageCard extends StatelessWidget {
  final String category; // "Social" | "Games" | "Entertainment" | "Others"
  final int dailyUsage; // minutes used today (per-category) - individual for display
  final int sessionUsage; // Not used anymore (removed from display)
  final bool isMonitored; // true for Social/Games/Entertainment
  final int dailyLimitMinutes; // Shared limit for all monitored categories
  final int sessionLimitMinutes; // Not used anymore (removed from display)
  final int? combinedDailyUsage; // Not used (removed from display)
  final int? combinedSessionUsage; // Not used (removed from display)

  const CategoryUsageCard({
    super.key,
    required this.category,
    required this.dailyUsage,
    required this.sessionUsage, // Kept for backward compatibility but not displayed
    required this.isMonitored,
    required this.dailyLimitMinutes,
    required this.sessionLimitMinutes, // Kept for backward compatibility but not displayed
    this.combinedDailyUsage,
    this.combinedSessionUsage,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ For "Others" category (not monitored), don't show limits or progress
    if (!isMonitored) {
      return _buildUnmonitoredCard();
    }
    
    // ✅ Individual category usage only (no combined, no progress bars)
    // Each category shows its own usage separately

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              getCategoryColor(category).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category icon & name
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: getCategoryColor(category).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      getCategoryIcon(category),
                      size: 28,
                      color: getCategoryColor(category),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: GoogleFonts.alice(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          isMonitored ? 'Monitored' : 'Not monitored',
                          style: GoogleFonts.alice(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge removed - showing individual usage only
                ],
              ),

              const SizedBox(height: 20),

              // Usage section - show individual category usage
              Text(
                'Usage',
                style: GoogleFonts.alice(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),

              // ✅ ACCURATE: Shows individual daily usage for this category (from database)
              // This is just for visibility on dashboard - to see which category is using more
              // Lock decisions still use combined values (Social + Games + Entertainment)
              // Database is updated by UsageService and read after sync, ensuring accuracy
              // Each category (Social, Games, Entertainment) shows its own separate usage
              Text(
                _formatMinutes(dailyUsage),
                style: GoogleFonts.alice(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  /// Build card for unmonitored category (Others) - no limits, just usage display
  Widget _buildUnmonitoredCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              getCategoryColor(category).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category icon & name
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: getCategoryColor(category).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      getCategoryIcon(category),
                      size: 28,
                      color: getCategoryColor(category),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: GoogleFonts.alice(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Not monitored',
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
              
              // Daily usage (no limit, just display)
              Text(
                'Usage',
                style: GoogleFonts.alice(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              
              // Just show usage without progress bar
              Text(
                _formatMinutes(dailyUsage),
                style: GoogleFonts.alice(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours h';
    }
    return '$hours h $mins min';
  }


  Color getCategoryColor(String category) {
    // ✅ Distinct colors for category differentiation (no green)
    switch (category) {
      case 'Social':
        return const Color(0xFF3B82F6); // Blue
      case 'Games':
        return const Color(0xFFF59E0B); // Amber/orange
      case 'Entertainment':
        return const Color(0xFF8B5CF6); // Purple
      case 'Others':
      default:
        return Colors.grey[600]!; // Neutral grey
    }
  }

  IconData getCategoryIcon(String category) {
    switch (category) {
      case 'Social':
        return Icons.people;
      case 'Games':
        return Icons.sports_esports;
      case 'Entertainment':
        return Icons.movie;
      case 'Others':
      default:
        return Icons.apps;
    }
  }
}
