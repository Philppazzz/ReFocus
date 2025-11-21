import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'package:refocus_app/services/monitor_service.dart';
import 'package:flutter/services.dart';

/// Permissions guide page - helps user grant all necessary permissions
class PermissionsGuidePage extends StatefulWidget {
  const PermissionsGuidePage({super.key});

  @override
  State<PermissionsGuidePage> createState() => _PermissionsGuidePageState();
}

class _PermissionsGuidePageState extends State<PermissionsGuidePage> {
  bool _usageAccessGranted = false;
  bool _overlayGranted = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Check usage access
    _usageAccessGranted = await UsageService.requestPermission();

    // Check overlay permission
    try {
      final platform = MethodChannel('com.example.refocus/monitor');
      _overlayGranted = await platform.invokeMethod('hasOverlayPermission') ?? false;
    } catch (e) {
      _overlayGranted = false;
    }

    // Notification is usually auto-granted on first install
    _notificationGranted = true;

    setState(() {});
  }

  Future<void> _requestUsageAccess() async {
    final granted = await UsageService.requestPermission();
    await _checkPermissions();

    if (granted) {
      _showSuccess('Usage Access granted!');
    } else {
      _showError('Please enable Usage Access in Settings');
    }
  }

  Future<void> _requestOverlay() async {
    try {
      await MonitorService.requestOverlayPermission();
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    } catch (e) {
      print("Error requesting overlay: $e");
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.alice(color: Colors.white)),
        backgroundColor: const Color(0xFF10B981), // ✅ Emerald green - matches app theme
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.alice(color: Colors.white)),
        backgroundColor: const Color(0xFFDC2626), // ✅ Red - matches app theme
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allGranted = _usageAccessGranted && _overlayGranted && _notificationGranted;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Setup Permissions',
          style: GoogleFonts.alice(
            fontWeight: FontWeight.bold,
            color: Colors.black87, // ✅ Match app theme
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87), // ✅ Match app theme
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Grant Required Permissions',
              style: GoogleFonts.alice(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87, // ✅ Match app theme
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'ReFocus needs these permissions to work properly:',
              style: GoogleFonts.alice(
                fontSize: 14,
                color: Colors.grey[700], // ✅ Match app theme
              ),
            ),
            const SizedBox(height: 30),

            // Permission 1: Usage Access (CRITICAL - Red indicator)
            _buildPermissionCard(
              icon: Icons.bar_chart,
              title: 'Usage Access',
              description: 'Track app usage and screen time',
              isGranted: _usageAccessGranted,
              onTap: _requestUsageAccess,
              critical: true,
              isCritical: true, // ✅ Red indicator for critical
            ),

            const SizedBox(height: 15),

            // Permission 2: Overlay Permission (CRITICAL - Red indicator)
            _buildPermissionCard(
              icon: Icons.layers,
              title: 'Display Over Other Apps',
              description: 'Show lock screen when limits reached',
              isGranted: _overlayGranted,
              onTap: _requestOverlay,
              critical: true,
              isCritical: true, // ✅ Red indicator for critical
            ),

            const SizedBox(height: 15),

            // Permission 3: Notifications (Non-critical)
            _buildPermissionCard(
              icon: Icons.notifications,
              title: 'Notifications',
              description: 'Background monitoring service',
              isGranted: _notificationGranted,
              onTap: null,
              critical: false,
              isCritical: false, // ✅ No red indicator
            ),

            const Spacer(),

            // Done button
            if (allGranted)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981), // ✅ Emerald green - matches app theme
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    'All Set! Continue',
                    style: GoogleFonts.alice(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1), // ✅ Orange - matches app theme
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withOpacity(0.3), // ✅ Orange border
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: const Color(0xFFF59E0B), // ✅ Orange - matches app theme
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Grant all permissions above to use ReFocus',
                        style: GoogleFonts.alice(
                          color: const Color(0xFFF59E0B), // ✅ Orange - matches app theme
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback? onTap,
    required bool critical,
    required bool isCritical, // ✅ For visual red indicator
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted 
              ? const Color(0xFF10B981) // ✅ Emerald green - success state
              : isCritical 
                  ? const Color(0xFFDC2626).withOpacity(0.5) // ✅ Red border for critical ungranted
                  : Colors.grey[300]!, // ✅ Grey for non-critical
          width: isGranted ? 2 : (isCritical ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isGranted 
                ? const Color(0xFF10B981).withOpacity(0.15) // ✅ Emerald green - success
                : isCritical
                    ? const Color(0xFFDC2626).withOpacity(0.1) // ✅ Red background for critical ungranted
                    : Colors.black.withOpacity(0.1), // ✅ Black opacity for non-critical
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isGranted 
                ? const Color(0xFF10B981) // ✅ Emerald green - success
                : isCritical
                    ? const Color(0xFFDC2626) // ✅ Red for critical ungranted
                    : Colors.black87, // ✅ Black87 for non-critical
            size: 28,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.alice(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87, // ✅ Match app theme
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              description,
              style: GoogleFonts.alice(
                fontSize: 12,
                color: Colors.grey[700], // ✅ Match app theme
              ),
            ),
            if (critical)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'REQUIRED',
                  style: GoogleFonts.alice(
                    fontSize: 10,
                    color: const Color(0xFFDC2626), // ✅ Red - matches app theme
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        trailing: isGranted
            ? const Icon(
                Icons.check_circle,
                color: Color(0xFF10B981), // ✅ Emerald green - matches app theme
                size: 32,
              )
            : onTap != null
                ? ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87, // ✅ Black87 - matches app theme
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Grant',
                      style: GoogleFonts.alice(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
      ),
    );
  }
}
