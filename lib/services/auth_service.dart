import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Service for secure authentication storage (PIN encryption)
class AuthService {
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
}

