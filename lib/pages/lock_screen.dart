import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:refocus_app/services/lock_state_manager.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:refocus_app/pages/home_page.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/selected_apps.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/emergency_service.dart';

class LockScreen extends StatefulWidget {
  final String reason;
  final String appName;
  final int cooldownSeconds;

  const LockScreen({
    super.key,
    required this.reason,
    required this.appName,
    required this.cooldownSeconds,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  Timer? _timer; // Make nullable to prevent crash for daily locks
  late int _remainingSeconds;
  bool _isDailyLock = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.cooldownSeconds;
    _isDailyLock = widget.reason == 'daily_limit';
    
    print("🔒 LockScreen initialized: reason=${widget.reason}, cooldown=${widget.cooldownSeconds}s, isDaily=$_isDailyLock");
    
    // Only create timer for session/unlock locks, NOT for daily locks
    if (!_isDailyLock) {
      // ✅ Use a fresh timer that updates every second
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
      return;
    }
        if (_remainingSeconds > 0) {
          setState(() {
            _remainingSeconds--;
          });
          print("⏱️ Timer: ${_remainingSeconds}s remaining");
      } else {
        timer.cancel();
          print("⏰ Timer expired - handling expiration");
          _handleExpired();
      }
    });
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); // Safe cancel - only if timer exists
    super.dispose();
  }

  Future<void> _handleExpired() async {
    // Timer expired - cooldown is over, user can use apps again
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    print("⏰⏰⏰ TIMER EXPIRED - VIOLATION-SPECIFIC RESET: ${widget.reason}");
    
    // ✅ STEP 1: Clear cooldown and lock state FIRST (common for all)
    await LockStateManager.clearCooldown();
    MonitorService.clearLockState();
    MonitorService.clearStatsCache();
    print("   ✓ Cooldown cleared");
    
    // ✅ STEP 2: Violation-specific reset
    if (widget.reason == 'session_limit') {
      // MAX SESSION: Only reset session tracking
      print("   📱 Max Session violation - resetting SESSION only");
      await prefs.remove('session_start_$today');
      await prefs.remove('last_activity_$today');
      await prefs.remove('last_break_end_$today');
      print("   ✓ Session cleared → 0m");
      
      // Clear UsageService's active session cache (but keep usage data)
      await prefs.remove('active_app_$today');
      await prefs.remove('active_start_$today');
      await prefs.remove('active_recorded_$today');
      print("   ✓ Active session cache cleared");
      
    } else if (widget.reason == 'unlock_limit') {
      // MOST UNLOCK: Only reset unlock counter
      print("   🔓 Most Unlock violation - resetting UNLOCK COUNTER only");
      await SelectedAppsManager.loadFromPrefs();
      final stats = await UsageService.getUsageStatsWithEvents(
        SelectedAppsManager.selectedApps,
        updateSessionTracking: false, // Don't update session while resetting
      );
      final currentUnlocks = (stats['most_unlock_count'] as num?)?.toInt() ?? 0;
      await prefs.setInt('unlock_base_$today', currentUnlocks);
      print("   ✓ Unlock base → $currentUnlocks (unlock counter reset)");
      
      // Also clear the unlock cache (but keep usage and session data)
      await prefs.remove('per_app_unlocks_$today');
      print("   ✓ Unlock cache cleared");
      
    } else if (widget.reason == 'daily_limit') {
      // DAILY LIMIT: Don't reset anything (only resets at midnight)
      print("   🌅 Daily Limit violation - NO RESET (only resets tomorrow)");
      print("   ⚠️ All apps remain locked until midnight");
    }
    
    // ✅ STEP 3: Reset usage cache timestamp to prevent stale data (common for all)
    await prefs.setInt('last_check_$today', DateTime.now().millisecondsSinceEpoch);
    print("   ✓ Cache timestamp reset");
    
    // ✅ STEP 4: Force clear all cooldown-related keys (common for all)
    await prefs.remove('cooldown_end');
    await prefs.remove('cooldown_reason');
    await prefs.remove('cooldown_app_name');
    print("   ✓ Cooldown keys cleared");
    
    // ✅ STEP 5: Set grace period to prevent immediate re-lock (CRITICAL!)
    // This prevents monitoring from immediately detecting old session and re-locking
    final gracePeriodEnd = DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch;
    await prefs.setInt('grace_period_end', gracePeriodEnd);
    print("   ✓ Grace period: 10 seconds (no re-lock)");
    
    print("✅✅✅ TIMER EXPIRED - ${widget.reason.toUpperCase()} RESET COMPLETE");
    print("   🛡️ 10-second grace period active - won't re-lock immediately!");
    
    // Wait LONGER for monitoring service to process the changes
    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomePage()),
        (route) => false,
      );
    }
  }

  String _formatTime(int seconds) {
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Get violation-specific UI elements
  Map<String, dynamic> _getViolationUI() {
    switch (widget.reason) {
      case 'daily_limit':
        return {
          'icon': Icons.block_rounded,
          'color': Colors.red,
          'title': 'Daily Limit',
          'subtitle': 'Screen time limit reached',
        };
      case 'session_limit':
        return {
          'icon': Icons.timer_off_rounded,
          'color': Colors.orange,
          'title': 'Max Session',
          'subtitle': 'Continuous usage limit',
        };
      default: // unlock_limit
        return {
          'icon': Icons.touch_app_rounded,
          'color': Colors.amber,
          'title': 'Most Unlocks',
          'subtitle': 'Too many unlocks',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = _getViolationUI();
    
    return PopScope(
      canPop: true, // ✅ Allow dismissing lock screen (home button, back button)
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          // User dismissed lock screen - monitoring service will re-show if they try to open selected apps
          print("🏠 User dismissed lock screen - can use phone, but selected apps will re-lock");
          MonitorService.clearLockState(); // Clear the visible flag so lock can show again
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top: Back Button & Icon & Title
                Column(
              children: [
                    // ✅ Back Button - Navigate to home page to view stats
                    Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // ✅ Navigate to home page instead of just popping
                            // This ensures user can view stats even when locked
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const HomePage()),
                              (route) => false,
                            );
                            MonitorService.clearLockState();
                            print("🏠 Back button pressed - navigating to home page");
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back, color: Colors.white, size: 24),
                                SizedBox(width: 8),
                                Text(
                                  'Back to Home',
                                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                Container(
                      padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [ui['color'].withOpacity(0.3), ui['color'].withOpacity(0.1)],
                        ),
                  ),
                      child: Icon(ui['icon'], size: 64, color: ui['color']),
                ),
                    const SizedBox(height: 24),
                Text(
                      ui['title'],
                      style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                    const SizedBox(height: 8),
                Text(
                      ui['subtitle'],
                      style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
                  ),
                  ],
                ),

                // Middle: Timer
                  Container(
                  padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1), width: 2),
                    ),
                    child: Column(
                      children: [
                      Text(
                        _isDailyLock ? 'Unlocks Tomorrow' : 'Time Remaining',
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
                        ),
                      const SizedBox(height: 16),
                        Text(
                        _isDailyLock ? '🌅 Next Day' : _formatTime(_remainingSeconds),
                        style: GoogleFonts.orbitron(fontSize: 48, fontWeight: FontWeight.bold, color: ui['color']),
                        ),
                      ],
                    ),
                  ),

                // Bottom: Buttons
                Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                          child: _buildButton('⚠️ RESET ALL ⚠️', Icons.refresh, Colors.red, () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('⚠️ Reset All Data?'),
                                content: const Text(
                                  'You have 50+ violations! This will:\n\n'
                                  '✅ Clear ALL violations (50 → 0)\n'
                                  '✅ Reset punishment to 5 seconds\n'
                                  '✅ Clear all usage data\n'
                                  '✅ Clear session tracking\n\n'
                                  'Next violation will be 5 seconds!'
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('YES - RESET ALL'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm != true) return;
                            
                            // ⚠️ CRITICAL: Stop monitoring FIRST to prevent interference
                            MonitorService.stopMonitoring();
                            await Future.delayed(const Duration(milliseconds: 500));
                            
                            // COMPREHENSIVE RESET - clears everything
                            MonitorService.clearLockState();
                            MonitorService.clearStatsCache();
                            await LockStateManager.clearCooldown();
                            
                            final prefs = await SharedPreferences.getInstance();
                            final today = DateTime.now().toIso8601String().substring(0, 10);
                            
                            // Clear all lock states
                            await prefs.remove('daily_locked');
                            
                            // ✅ CRITICAL: Clear violation counts (reset punishment to 5 seconds)
                            await prefs.remove('session_violations_$today');
                            await prefs.remove('unlock_violations_$today');
                            await prefs.remove('last_session_violation_$today');
                            await prefs.remove('last_unlock_violation_$today');
                            print("🔄 Violation counts RESET - next violation will be 5 seconds");
                            
                            // ✅ Set grace period to prevent immediate re-lock after reset
                            final gracePeriodEnd = DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch;
                            await prefs.setInt('grace_period_end', gracePeriodEnd);
                            print("🛡️ 10-second grace period set - won't re-lock immediately!");
                            
                            // Clear all tracking
                            await prefs.remove('session_start_$today');
                            await prefs.remove('last_activity_$today');
                            await prefs.remove('unlock_base_$today'); // Reset to 0 (start fresh)
                            
                            // ✅ CRITICAL: Reset ALL UsageService cached aggregates!
                            await prefs.remove('per_app_usage_$today');
                            await prefs.remove('per_app_unlocks_$today');
                            await prefs.remove('per_app_longest_$today');
                            await prefs.remove('processed_$today');
                            await prefs.remove('active_app_$today');
                            await prefs.remove('active_start_$today');
                            await prefs.remove('active_recorded_$today');
                            print("   ✓ UsageService cache cleared");
                            
                            // Reset all usage data
                            await UsageService.resetTodayAggregates();
                            
                            // Clear usage cache timestamp to force fresh data
                            await prefs.setInt('last_check_$today', DateTime.now().millisecondsSinceEpoch);
                            await prefs.remove('last_break_end_$today');
                            await prefs.remove('cooldown_end');
                            await prefs.remove('cooldown_reason');
                            await prefs.remove('cooldown_app_name');
                            
                            // Clear database
                            final db = await DatabaseHelper.instance.database;
                            await db.delete('usage_stats', where: 'date = ?', whereArgs: [today]);
                            await db.delete('app_details', where: 'date = ?', whereArgs: [today]);
                            
                            print("✅✅✅ COMPREHENSIVE RESET COMPLETE!");
                            print("   Violations: 50 → 0 (CLEARED)");
                            print("   Usage: CLEARED → 0m");
                            print("   Session: CLEARED → 0m");
                            print("   Unlocks: CLEARED → 0");
                            print("   Next violation: 5 SECONDS (not 60!)");
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ 50 violations cleared! Next lock: 5 seconds'),
                                  duration: Duration(seconds: 4),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              
                              // Wait LONGER for all state to settle
                              await Future.delayed(const Duration(milliseconds: 2000));
                              
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (context) => const HomePage()),
                                (route) => false,
                              );
                            }
                          }),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    _EmergencyUnlockButton(),
                    ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: 2),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}

/// Emergency Unlock Button
class _EmergencyUnlockButton extends StatefulWidget {
  @override
  State<_EmergencyUnlockButton> createState() => _EmergencyUnlockButtonState();
}

class _EmergencyUnlockButtonState extends State<_EmergencyUnlockButton> {
  bool _isLongPressing = false;
  Timer? _longPressTimer;
  static const _longPressDuration = Duration(seconds: 1);

  void _handleLongPressStart() {
    setState(() => _isLongPressing = true);
    _longPressTimer = Timer(_longPressDuration, () {
      if (mounted && _isLongPressing) {
        _handleLongPressComplete();
      }
    });
  }

  void _handleLongPressEnd() {
    _longPressTimer?.cancel();
    setState(() => _isLongPressing = false);
  }

  void _handleLongPressComplete() {
    _longPressTimer?.cancel();
    setState(() => _isLongPressing = false);
    _showEmergencyUnlockDialog();
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  Future<void> _showEmergencyUnlockDialog() async {
    // Check if already used today
    if (await EmergencyService.hasUsedEmergencyToday()) {
      final hoursUntil = await EmergencyService.getHoursUntilAvailable();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency override already used today. Available in $hoursUntil hours.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    bool isLoading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Emergency Override',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to activate emergency override?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('This will:', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              const Text('✓ Remove this lock', style: TextStyle(color: Colors.white70)),
              const Text('✓ Reset session timer', style: TextStyle(color: Colors.white70)),
              const Text('✓ Reset unlock counter', style: TextStyle(color: Colors.white70)),
              const Text('✓ Stop all tracking', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: const Text(
                  '⚠️ Can only be used ONCE per day',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() => isLoading = true);
                      final result = await EmergencyService.activateEmergency();
                      setState(() => isLoading = false);
                      if (result['success'] == true) {
                        Navigator.pop(context, true);
                        Navigator.pop(context); // Close lock screen
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(result['message'] ?? 'Failed')),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency override activated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _handleLongPressStart(),
      onLongPressEnd: (_) => _handleLongPressEnd(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _isLongPressing ? Colors.orange.withOpacity(0.2) : Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _isLongPressing ? Colors.orange : Colors.red, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: _isLongPressing ? Colors.orange : Colors.red, size: 20),
            const SizedBox(width: 8),
            Text(_isLongPressing ? 'Releasing...' : 'Hold for Emergency', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _isLongPressing ? Colors.orange : Colors.red)),
          ],
        ),
      ),
    );
  }
}
