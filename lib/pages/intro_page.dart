import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/pages/signup.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/pages/home_page.dart';
import 'package:refocus_app/pages/forgot_password_page.dart';
import 'package:refocus_app/services/auth_service.dart';

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
      // User is already logged in, navigate to HomePage
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

    // ✅ Check for login lockout (rate limiting)
    final lockoutStatus = await AuthService.checkLoginLockout(email);
    if (lockoutStatus['isLocked'] == true) {
      final remainingMinutes = lockoutStatus['remainingMinutes'] as int;
      setState(() {
        passwordError = "Too many failed attempts. Try again in $remainingMinutes minute${remainingMinutes > 1 ? 's' : ''}";
      });
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
      // ❌ Failed login: Record attempt
      await AuthService.recordFailedLogin(email);
      final attempts = lockoutStatus['attempts'] as int;
      final remaining = AuthService.MAX_LOGIN_ATTEMPTS - attempts - 1;
      
      if (remaining > 0) {
        setState(() => passwordError = "Incorrect password ($remaining attempt${remaining > 1 ? 's' : ''} remaining)");
      } else {
        setState(() => passwordError = "Incorrect password. Account will be locked after one more failed attempt");
      }
      return;
    }

    // ✅ Successful login: Clear attempts and save login status
    await AuthService.clearLoginAttempts(email);
    print("🔐 LOGIN SUCCESS - Saving preferences...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true); // save login status
    await prefs.setString('userEmail', email); // optional: save email
    print("✅ Preferences saved");

    print("🚀 Navigating to HomePage...");
    if (!mounted) {
      print("❌ Widget not mounted!");
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) {
        print("📱 Building HomePage...");
        return const HomePage();
      }),
    );
    print("✅ Navigation called");
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    
    // Calculate responsive sizes based on screen height
    // Reduce logo size when keyboard is visible
    final logoHeight = isKeyboardVisible 
        ? screenHeight * 0.08  // Smaller when keyboard is visible
        : screenHeight * 0.15;  // Normal size
    final logoMaxHeight = 170.0;
    final logoMinHeight = isKeyboardVisible ? 80.0 : 120.0;
    final logoSize = logoHeight.clamp(logoMinHeight, logoMaxHeight);
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      resizeToAvoidBottomInset: true, // Allow content to resize when keyboard appears
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual, // Prevent keyboard from dismissing on scroll
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - keyboardHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.07, // 7% of screen width
                      vertical: screenHeight * 0.02, // 2% of screen height
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top spacing
                        SizedBox(height: screenHeight * 0.02),
                        
                        // Logo and branding section
                        Flexible(
                          flex: isKeyboardVisible ? 1 : 2,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'lib/img/Logo.png',
                                height: logoSize,
                                fit: BoxFit.contain,
                              ),
                              SizedBox(height: screenHeight * 0.012),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "ReFocus",
                                  style: GoogleFonts.alice(
                                    fontSize: isKeyboardVisible ? 24 : 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (!isKeyboardVisible) ...[
                                SizedBox(height: screenHeight * 0.004),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "Less scrolling, more living.",
                                    style: GoogleFonts.alice(
                                      fontSize: 19,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        
                        SizedBox(height: isKeyboardVisible ? screenHeight * 0.015 : screenHeight * 0.03),
                        
                        // Form section
                        Flexible(
                          flex: isKeyboardVisible ? 2 : 3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // --- Email field ---
                              TextField(
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: "Email address",
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: screenHeight * 0.018,
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorText: emailError,
                                ),
                              ),
                              
                              SizedBox(height: screenHeight * 0.015),
                              
                              // --- Password field ---
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  hintText: "Password",
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: screenHeight * 0.018,
                                    horizontal: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorText: passwordError,
                                ),
                              ),
                              
                              SizedBox(height: screenHeight * 0.01),
                              
                              // --- Forgot Password button ---
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    if (emailController.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Please enter your email first"),
                                        ),
                                      );
                                      return;
                                    }
                                    final email = emailController.text.trim().toLowerCase();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ForgotPasswordPage(email: email),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "Forgot Password?",
                                    style: GoogleFonts.alice(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              
                              SizedBox(height: screenHeight * 0.015),
                              
                              // --- Login button ---
                              SizedBox(
                                width: double.infinity,
                                height: screenHeight * 0.065,
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
                            ],
                          ),
                        ),
                        
                        // Bottom spacing and sign up - only show when keyboard is not visible
                        if (!isKeyboardVisible) ...[
                          SizedBox(height: screenHeight * 0.02),
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.alice(
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
                          SizedBox(height: screenHeight * 0.02),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
