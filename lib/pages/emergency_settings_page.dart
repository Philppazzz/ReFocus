import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/services/emergency_unlock_service.dart';
import 'package:geolocator/geolocator.dart';

class EmergencySettingsPage extends StatefulWidget {
  const EmergencySettingsPage({super.key});

  @override
  State<EmergencySettingsPage> createState() => _EmergencySettingsPageState();
}

class _EmergencySettingsPageState extends State<EmergencySettingsPage> {
  bool _biometricRequired = true;
  bool _trustedContactRequired = false;
  bool _geofenceRequired = false;
  bool _abusePenaltyEnabled = true;
  bool _isLoading = true;
  String _locationStatus = 'Not set';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await EmergencyUnlockService.getSafeguardSettings();
    setState(() {
      _biometricRequired = settings['biometricRequired'] ?? true;
      _trustedContactRequired = settings['trustedContactRequired'] ?? false;
      _geofenceRequired = settings['geofenceRequired'] ?? false;
      _abusePenaltyEnabled = settings['abusePenaltyEnabled'] ?? true;
      _isLoading = false;
    });
    _checkLocationStatus();
  }

  Future<void> _checkLocationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final facilityLat = prefs.getDouble('emergency_facility_latitude');
    final facilityLng = prefs.getDouble('emergency_facility_longitude');
    
    if (facilityLat != null && facilityLng != null) {
      setState(() {
        _locationStatus = 'Set: ${facilityLat.toStringAsFixed(4)}, ${facilityLng.toStringAsFixed(4)}';
      });
    } else {
      setState(() {
        _locationStatus = 'Not set';
      });
    }
  }

  Future<void> _setCurrentLocationAsEmergencyFacility() async {
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required')),
        );
        return;
      }

      // Get current location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Set as emergency facility
      await EmergencyUnlockService.setEmergencyFacilityLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: 500.0,
      );

      setState(() {
        _locationStatus = 'Set: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency facility location set to current location'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Unlock Settings'),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safeguards',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Configure which safeguards are required for emergency unlock',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Biometric Required
                  Card(
                    child: SwitchListTile(
                      title: const Text('Biometric Authentication'),
                      subtitle: const Text('Require fingerprint/face recognition'),
                      value: _biometricRequired,
                      onChanged: (value) async {
                        setState(() => _biometricRequired = value);
                        await EmergencyUnlockService.setSafeguardSettings(
                          biometricRequired: value,
                        );
                      },
                    ),
                  ),

                  // Trusted Contact Required
                  Card(
                    child: SwitchListTile(
                      title: const Text('Trusted Contact Approval'),
                      subtitle: const Text('Require approval from trusted contact'),
                      value: _trustedContactRequired,
                      onChanged: (value) async {
                        setState(() => _trustedContactRequired = value);
                        await EmergencyUnlockService.setSafeguardSettings(
                          trustedContactRequired: value,
                        );
                      },
                    ),
                  ),

                  // Geofence Required
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Geofence Check'),
                          subtitle: const Text('Require proximity to emergency facility'),
                          value: _geofenceRequired,
                          onChanged: (value) async {
                            setState(() => _geofenceRequired = value);
                            await EmergencyUnlockService.setSafeguardSettings(
                              geofenceRequired: value,
                            );
                            _checkLocationStatus();
                          },
                        ),
                        if (_geofenceRequired) ...[
                          const Divider(),
                          ListTile(
                            title: const Text('Emergency Facility Location'),
                            subtitle: Text(_locationStatus),
                            trailing: ElevatedButton(
                              onPressed: _setCurrentLocationAsEmergencyFacility,
                              child: const Text('Set Current Location'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Abuse Penalty
                  Card(
                    child: SwitchListTile(
                      title: const Text('Abuse Penalty'),
                      subtitle: const Text('Increase lock penalties for frequent use'),
                      value: _abusePenaltyEnabled,
                      onChanged: (value) async {
                        setState(() => _abusePenaltyEnabled = value);
                        await EmergencyUnlockService.setSafeguardSettings(
                          abusePenaltyEnabled: value,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Info Card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Emergency Unlock Info',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '• Rate limited to 1 use per 24 hours\n'
                            '• All attempts are logged with timestamp and reason\n'
                            '• Abuse (3+ uses in 7 days) triggers penalty\n'
                            '• Penalty increases cooldown times for session/unlock limits',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

