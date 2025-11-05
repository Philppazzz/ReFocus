import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/auth_service.dart';

class PINSetupPage extends StatefulWidget {
  final String email;

  const PINSetupPage({
    super.key,
    required this.email,
  });

  @override
  State<PINSetupPage> createState() => _PINSetupPageState();
}

class _PINSetupPageState extends State<PINSetupPage> {
  final TextEditingController pinController = TextEditingController();
  final TextEditingController confirmPinController = TextEditingController();

  String? pinError;
  bool isLoading = false;

  @override
  void dispose() {
    pinController.dispose();
    confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _savePIN() async {
    setState(() {
      pinError = null;
    });

    final pin = pinController.text.trim();
    final confirmPin = confirmPinController.text.trim();

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

    if (pin != confirmPin) {
      setState(() => pinError = "PINs do not match");
      return;
    }

    setState(() => isLoading = true);

    await AuthService.savePIN(widget.email, pin);

    setState(() => isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("PIN saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
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
                  Icons.pin,
                  size: 40,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Title
              Text(
                "Set Up PIN",
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
                "Create a 4-digit PIN for password recovery",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 40),

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
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Confirm PIN Input
              TextField(
                controller: confirmPinController,
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
              
              // Save PIN Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _savePIN,
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
                          "Save PIN",
                          style: GoogleFonts.alice(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Back Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Skip",
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

