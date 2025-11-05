import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/auth_service.dart';
import 'package:refocus_app/database_helper.dart';

class ForgotPasswordPage extends StatefulWidget {
  final String email;

  const ForgotPasswordPage({
    super.key,
    required this.email,
  });

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController pinController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  String? pinError;
  String? passwordError;
  bool isLoading = false;
  bool pinVerified = false;

  @override
  void initState() {
    super.initState();
    _checkUserExists();
  }

  Future<void> _checkUserExists() async {
    final db = DatabaseHelper.instance;
    final exists = await db.userExists(widget.email);
    if (!exists && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Email not registered"),
          backgroundColor: Colors.red,
        ),
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    pinController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _verifyPIN() async {
    setState(() {
      pinError = null;
    });

    final pin = pinController.text.trim();

    if (pin.isEmpty) {
      setState(() => pinError = "PIN is required");
      return;
    }

    if (pin.length != 4) {
      setState(() => pinError = "PIN must be 4 digits");
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => pinError = "PIN must contain only numbers");
      return;
    }

    setState(() => isLoading = true);

    // Check if user has a PIN set
    final hasPIN = await AuthService.hasPIN(widget.email);
    if (!hasPIN) {
      setState(() {
        isLoading = false;
        pinError = "No PIN found for this account. Please contact support or set up PIN in settings.";
      });
      return;
    }

    final isValid = await AuthService.verifyPIN(widget.email, pin);
    setState(() => isLoading = false);

    if (isValid) {
      setState(() => pinVerified = true);
    } else {
      setState(() => pinError = "Incorrect PIN, try again.");
      pinController.clear();
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      passwordError = null;
    });

    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (newPassword.isEmpty) {
      setState(() => passwordError = "Password is required");
      return;
    }

    if (newPassword.length < 8) {
      setState(() => passwordError = "Password must be at least 8 characters");
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => passwordError = "Passwords do not match");
      return;
    }

    setState(() => isLoading = true);

    final db = DatabaseHelper.instance;
    final success = await db.updateUserPassword(widget.email, newPassword);

    setState(() => isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password reset successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } else {
      setState(() => passwordError = "Failed to update password. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.lock_reset,
                  size: 40,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Title
              Text(
                pinVerified ? "Set New Password" : "Forgot Password?",
                style: GoogleFonts.alice(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                pinVerified
                    ? "Enter your new password below"
                    : "Enter your 4-digit PIN to reset your password",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 40),

              if (!pinVerified) ...[
                // PIN Input
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.orbitron(
                    fontSize: 32,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: "0000",
                    hintStyle: GoogleFonts.orbitron(
                      fontSize: 32,
                      letterSpacing: 8,
                      color: Colors.black26,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    errorText: pinError,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Submit PIN Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _verifyPIN,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : Text(
                            "Submit",
                            style: GoogleFonts.alice(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                // New Password Field
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "New Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Confirm Password Field
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Confirm Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    errorText: passwordError,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Reset Password Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : Text(
                            "Reset Password",
                            style: GoogleFonts.alice(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // Back Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Back to Login",
                  style: GoogleFonts.poppins(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

