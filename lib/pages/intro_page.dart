import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/pages/app_picker_page.dart';
import 'package:refocus_app/pages/signup.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/pages/home_page.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String? emailError;
  String? passwordError;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // Check if user is already logged in
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      // User is already logged in, navigate to AppPickerPage
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const  HomePage()),
      );
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w\.-]+@gmail\.com$').hasMatch(email);
  }

  Future<void> _loginUser() async {
    setState(() {
      emailError = null;
      passwordError = null;
    });

    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    if (email.isEmpty) {
      setState(() => emailError = "Email is required");
      return;
    } else if (!_isValidEmail(email)) {
      setState(() => emailError = "Please enter a valid Gmail address");
      return;
    }

    if (password.isEmpty) {
      setState(() => passwordError = "Password is required");
      return;
    } else if (password.length < 8) {
      setState(() => passwordError = "Password must be at least 8 characters");
      return;
    }

    setState(() => isLoading = true);

    final db = DatabaseHelper.instance;
    final userExists = await db.userExists(email);

    if (!userExists) {
      setState(() {
        isLoading = false;
        emailError = "Email not registered";
      });
      return;
    }

    final user = await db.getUser(email, password);
    setState(() => isLoading = false);

    if (user == null) {
      setState(() => passwordError = "Incorrect password");
      return;
    }

    // ✅ Successful login: Save login status
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true); // save login status
    await prefs.setString('userEmail', email); // optional: save email

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AppPickerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 55),
              Center(
                child: Image.asset(
                  'lib/img/Logo.png',
                  height: 170,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "ReFocus",
                style: GoogleFonts.alice(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Less scrolling, more living.",
                style: GoogleFonts.alice(
                  fontSize: 19,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 40),

              // --- Email field ---
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "Email address",
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: emailError,
                ),
              ),

              const SizedBox(height: 16),

              // --- Password field ---
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: "Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: passwordError,
                ),
              ),

              const SizedBox(height: 32),

              // --- Login button ---
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _loginUser,
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
                          "Login",
                          style: GoogleFonts.alice(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 40),

              // --- Haven't any account? Sign up ---
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                  children: [
                    const TextSpan(text: "Haven't any account? "),
                    TextSpan(
                      text: "Sign up",
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignupPage(),
                            ),
                          );
                        },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
