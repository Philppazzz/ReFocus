import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/lock_state_manager.dart';

class EmergencyUnlockService {
  static final LocalAuthentication _auth = LocalAuthentication();
  
  // Rate limiting: 1 per 24 hours
  static const int _rateLimitHours = 24;

  /// Check if emergency unlock is available (rate limit check)
  static Future<bool> isEmergencyUnlockAvailable() async {
    final count = await DatabaseHelper.instance.getEmergencyUnlockCountLast24Hours();
    return count < 1; // Max 1 per 24 hours
  }

  /// Get remaining time until next emergency unlock is available
  static Future<Duration?> getRemainingCooldown() async {
    final lastUnlock = await DatabaseHelper.instance.getLastEmergencyUnlockTimestamp();
    if (lastUnlock == null) return null;
    
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - lastUnlock;
    final cooldownMs = _rateLimitHours * 60 * 60 * 1000;
    final remaining = cooldownMs - elapsed;
    
    if (remaining <= 0) return null;
    return Duration(milliseconds: remaining.toInt());
  }

  /// Get safeguard settings
  /// Default: Only biometric required (optional), others disabled for emergency urgency
  static Future<Map<String, bool>> getSafeguardSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'biometricRequired': prefs.getBool('emergency_biometric_required') ?? false, // Default: OFF for urgency
      'trustedContactRequired': prefs.getBool('emergency_trusted_contact_required') ?? false,
      'geofenceRequired': prefs.getBool('emergency_geofence_required') ?? false,
      'abusePenaltyEnabled': prefs.getBool('emergency_abuse_penalty_enabled') ?? true,
    };
  }

  /// Set safeguard settings
  static Future<void> setSafeguardSettings({
    bool? biometricRequired,
    bool? trustedContactRequired,
    bool? geofenceRequired,
    bool? abusePenaltyEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (biometricRequired != null) {
      await prefs.setBool('emergency_biometric_required', biometricRequired);
    }
    if (trustedContactRequired != null) {
      await prefs.setBool('emergency_trusted_contact_required', trustedContactRequired);
    }
    if (geofenceRequired != null) {
      await prefs.setBool('emergency_geofence_required', geofenceRequired);
    }
    if (abusePenaltyEnabled != null) {
      await prefs.setBool('emergency_abuse_penalty_enabled', abusePenaltyEnabled);
    }
  }

  /// Check if biometric authentication is available
  static Future<bool> isBiometricAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (e) {
      print("⚠️ Biometric check error: $e");
      return false;
    }
  }

  /// Authenticate with biometric
  static Future<bool> authenticateWithBiometric() async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        print("⚠️ Biometric not available");
        return false;
      }

      return await _auth.authenticate(
        localizedReason: 'Emergency unlock requires biometric confirmation',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      print("⚠️ Biometric authentication error: $e");
      return false;
    }
  }

  /// Check if location is near emergency facility (geofence)
  static Future<bool> checkGeofence() async {
    try {
      // Check if location permission is granted
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print("⚠️ Location services disabled");
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print("⚠️ Location permission denied");
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print("⚠️ Location permission permanently denied");
        return false;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get emergency facility coordinates (hospital, police station, etc.)
      final prefs = await SharedPreferences.getInstance();
      final facilityLat = prefs.getDouble('emergency_facility_latitude');
      final facilityLng = prefs.getDouble('emergency_facility_longitude');
      final radiusMeters = prefs.getDouble('emergency_geofence_radius') ?? 500.0;

      if (facilityLat == null || facilityLng == null) {
        print("⚠️ Emergency facility location not configured");
        return false;
      }

      // Calculate distance
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        facilityLat,
        facilityLng,
      );

      return distance <= radiusMeters;
    } catch (e) {
      print("⚠️ Geofence check error: $e");
      return false;
    }
  }

  /// Set emergency facility location
  static Future<void> setEmergencyFacilityLocation({
    required double latitude,
    required double longitude,
    double radiusMeters = 500.0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('emergency_facility_latitude', latitude);
    await prefs.setDouble('emergency_facility_longitude', longitude);
    await prefs.setDouble('emergency_geofence_radius', radiusMeters);
    print("📍 Emergency facility location set: ($latitude, $longitude), radius: ${radiusMeters}m");
  }

  /// Check if trusted contact approval is required and get status
  static Future<bool> checkTrustedContactApproval() async {
    // This would integrate with a contact system
    // For now, we'll use a simple SharedPreferences flag
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('emergency_trusted_contact_approved') ?? false;
  }

  /// Set trusted contact approval
  static Future<void> setTrustedContactApproval(bool approved) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emergency_trusted_contact_approved', approved);
  }

  /// Check if this is abuse (multiple uses in short time)
  static Future<bool> isAbuse() async {
    final unlocks = await DatabaseHelper.instance.getAllEmergencyUnlocks();
    if (unlocks.length < 2) return false;

    // Check if user has used emergency unlock 3+ times in last 7 days
    final now = DateTime.now().millisecondsSinceEpoch;
    final weekAgo = now - (7 * 24 * 60 * 60 * 1000);
    
    int recentCount = 0;
    for (var unlock in unlocks) {
      final timestamp = unlock['timestamp'] as int?;
      if (timestamp != null && timestamp >= weekAgo) {
        recentCount++;
      }
    }

    return recentCount >= 3; // 3+ uses in 7 days = abuse
  }

  /// Apply abuse penalty (increases cooldown times)
  static Future<void> applyAbusePenalty() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    // Increase violation counts for session and unlock limits
    final sessionViolations = prefs.getInt('session_violations_$today') ?? 0;
    final unlockViolations = prefs.getInt('unlock_violations_$today') ?? 0;
    
    // Add penalty violations
    await prefs.setInt('session_violations_$today', sessionViolations + 2);
    await prefs.setInt('unlock_violations_$today', unlockViolations + 2);
    
    print("🚨 Abuse penalty applied: +2 violations to session and unlock limits");
  }

  /// Perform emergency unlock with all safeguards
  /// For true emergencies, safeguards are optional by default
  static Future<Map<String, dynamic>> performEmergencyUnlock({
    String? reason, // Made optional - can be empty for urgency
    bool skipSafeguards = false, // For testing only
  }) async {
    final result = {
      'success': false,
      'message': '',
      'method': 'unknown',
      'latitude': null as double?,
      'longitude': null as double?,
      'trustedContactApproved': false,
    };

    // Check rate limit
    if (!skipSafeguards) {
      final isAvailable = await isEmergencyUnlockAvailable();
      if (!isAvailable) {
        final remaining = await getRemainingCooldown();
        if (remaining != null) {
          final hours = remaining.inHours;
          final minutes = remaining.inMinutes % 60;
          result['message'] = 'Emergency unlock rate limited. Available in $hours hours and $minutes minutes.';
          return result;
        }
      }
    }

    // Get safeguard settings
    final settings = await getSafeguardSettings();
    final safeguards = <String>[];

    // 1. Biometric authentication (optional - only if enabled)
    if (settings['biometricRequired'] == true && !skipSafeguards) {
      safeguards.add('biometric');
      final biometricSuccess = await authenticateWithBiometric();
      if (!biometricSuccess) {
        // In emergency, allow unlock even if biometric fails (optional safeguard)
        // Just log it but don't block
        print("⚠️ Biometric failed but continuing for emergency");
        result['method'] = 'biometric_attempted';
      } else {
        result['method'] = 'biometric';
      }
    } else {
      // No biometric required - faster emergency unlock
      result['method'] = 'quick_unlock';
    }

    // 2. Trusted contact approval (optional - skip if not required for emergency urgency)
    bool trustedContactApproved = false;
    if (settings['trustedContactRequired'] == true && !skipSafeguards) {
      safeguards.add('trusted_contact');
      trustedContactApproved = await checkTrustedContactApproval();
      // In emergency, allow unlock even without trusted contact (optional safeguard)
      if (!trustedContactApproved) {
        print("⚠️ Trusted contact not approved but continuing for emergency");
      }
    }

    // 3. Geofence check (optional - skip if not required for emergency urgency)
    double? latitude;
    double? longitude;
    if (settings['geofenceRequired'] == true && !skipSafeguards) {
      safeguards.add('geofence');
      final geofenceSuccess = await checkGeofence();
      // In emergency, allow unlock even if not at facility (optional safeguard)
      if (!geofenceSuccess) {
        print("⚠️ Not near emergency facility but continuing for emergency");
      }
    }
    
    // Try to get location for logging (non-blocking)
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Lower accuracy for faster response
        timeLimit: const Duration(seconds: 2), // Timeout after 2 seconds
      );
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (e) {
      print("⚠️ Could not get location (non-blocking): $e");
    }

    // All safeguards passed - perform unlock
    await LockStateManager.clearCooldown();
    // Clear daily lock (it's stored in SharedPreferences, not in cooldown)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('daily_locked');

    // Check for abuse and apply penalty
    bool abusePenaltyApplied = false;
    if (settings['abusePenaltyEnabled'] == true) {
      final isAbuseCase = await isAbuse();
      if (isAbuseCase) {
        await applyAbusePenalty();
        abusePenaltyApplied = true;
      }
    }

    // Log the emergency unlock
    final method = safeguards.isEmpty ? 'quick_unlock' : safeguards.join('+');
    await DatabaseHelper.instance.logEmergencyUnlock(
      method: method,
      reason: reason ?? 'Emergency unlock', // Default reason if not provided
      latitude: latitude,
      longitude: longitude,
      trustedContactApproved: trustedContactApproved,
      abusePenaltyApplied: abusePenaltyApplied,
    );

    result['success'] = true;
    result['message'] = 'Emergency unlock successful';
    result['method'] = method;
    result['latitude'] = latitude;
    result['longitude'] = longitude;
    result['trustedContactApproved'] = trustedContactApproved;

    print("🚨 Emergency unlock performed: $method, reason: $reason");
    if (abusePenaltyApplied) {
      print("⚠️ Abuse penalty applied due to frequent use");
    }

    return result;
  }
}

