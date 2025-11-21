import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for secure authentication storage (PIN encryption)
class AuthService {
  // Rate limiting constants
  static const int MAX_LOGIN_ATTEMPTS = 5;
  static const int LOCKOUT_DURATION_MINUTES = 15;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Save PIN for a user (encrypted)
  static Future<void> savePIN(String email, String pin) async {
    // Hash the PIN for additional security
    final pinHash = _hashPIN(pin);
    await _storage.write(key: 'pin_$email', value: pinHash);
    print("🔐 PIN saved for $email");
  }

  /// Verify PIN for a user
  static Future<bool> verifyPIN(String email, String pin) async {
    try {
      final storedPinHash = await _storage.read(key: 'pin_$email');
      if (storedPinHash == null) return false;
      
      final inputPinHash = _hashPIN(pin);
      return storedPinHash == inputPinHash;
    } catch (e) {
      print("⚠️ Error verifying PIN: $e");
      return false;
    }
  }

  /// Check if user has a PIN set
  static Future<bool> hasPIN(String email) async {
    try {
      final pinHash = await _storage.read(key: 'pin_$email');
      return pinHash != null && pinHash.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Hash PIN using SHA-256
  static String _hashPIN(String pin) {
    final bytes = utf8.encode(pin);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Hash password using SHA-256 (for secure storage)
  /// IMPORTANT: Passwords must be hashed before storing in database
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Verify password by comparing hashes
  static bool verifyPassword(String inputPassword, String storedHash) {
    final inputHash = hashPassword(inputPassword);
    return inputHash == storedHash;
  }

  /// Check if account is locked due to too many failed attempts
  static Future<Map<String, dynamic>> checkLoginLockout(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutKey = 'login_lockout_$email';
      final attemptsKey = 'login_attempts_$email';
      
      final lockoutTime = prefs.getInt(lockoutKey);
      final attempts = prefs.getInt(attemptsKey) ?? 0;
      
      if (lockoutTime != null) {
        final lockoutEnd = DateTime.fromMillisecondsSinceEpoch(lockoutTime);
        final now = DateTime.now();
        
        if (now.isBefore(lockoutEnd)) {
          final remainingMinutes = lockoutEnd.difference(now).inMinutes + 1;
          return {
            'isLocked': true,
            'remainingMinutes': remainingMinutes,
            'attempts': attempts,
          };
        } else {
          // Lockout expired, clear it
          await prefs.remove(lockoutKey);
          await prefs.remove(attemptsKey);
          return {'isLocked': false, 'attempts': 0};
        }
      }
      
      return {'isLocked': false, 'attempts': attempts};
    } catch (e) {
      print('⚠️ Error checking login lockout: $e');
      return {'isLocked': false, 'attempts': 0};
    }
  }

  /// Record failed login attempt
  static Future<void> recordFailedLogin(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attemptsKey = 'login_attempts_$email';
      final lockoutKey = 'login_lockout_$email';
      
      final attempts = (prefs.getInt(attemptsKey) ?? 0) + 1;
      await prefs.setInt(attemptsKey, attempts);
      
      if (attempts >= MAX_LOGIN_ATTEMPTS) {
        // Lock account for 15 minutes
        final lockoutEnd = DateTime.now().add(Duration(minutes: LOCKOUT_DURATION_MINUTES));
        await prefs.setInt(lockoutKey, lockoutEnd.millisecondsSinceEpoch);
        print('🔒 Account locked for $LOCKOUT_DURATION_MINUTES minutes after $attempts failed attempts');
      } else {
        print('⚠️ Failed login attempt $attempts/$MAX_LOGIN_ATTEMPTS for $email');
      }
    } catch (e) {
      print('⚠️ Error recording failed login: $e');
    }
  }

  /// Clear login attempts on successful login
  static Future<void> clearLoginAttempts(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_attempts_$email');
      await prefs.remove('login_lockout_$email');
    } catch (e) {
      print('⚠️ Error clearing login attempts: $e');
    }
  }
}

