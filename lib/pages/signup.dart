import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/auth_service.dart';
import 'package:refocus_app/pages/terms_page.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:refocus_app/pages/pin_setup_page.dart';


class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  bool acceptedTerms = false;
  bool isLoading = false;

  //For the database input field

  final _formKey = GlobalKey<FormState>();
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // --- Validation---
  bool _isValidEmail(String email) {
  return RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  ).hasMatch(email);
}

bool _isValidName(String name) {
  return RegExp(
    r"^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+([A-Z]\.)?\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)$"
  ).hasMatch(name);
}


  
  Future<void> _createAccount() async {

    // For validating  the input fields
    if (!_formKey.currentState!.validate()) return;

    // For validating the checbox to click the create button
    if (!acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You must accept the terms first")),
      );
      return;
    }
    //Make the loading 
    setState(() => isLoading = true);

    //Calling the same db and filtering
    final db = DatabaseHelper.instance;
    final name = fullNameController.text.trim();
    final email = emailController.text.trim().toLowerCase(); 
    final password = passwordController.text.trim();

    // Check if email already registered
    bool exists = await db.userExists(email);
    if (exists) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email already registered")),
      );
      return;
    }

    // Save user to database with hashed password (SECURE)
    final hashedPassword = AuthService.hashPassword(password);
    await db.insertUser({
      'fullName': name,
      'email': email,
      'password': hashedPassword, // Store hashed password, not plain text
    });

    //Make the loading stop
    setState(() => isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Account created successfully!")),
    );

    // Go to PIN setup page (optional)
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PINSetupPage(email: email),
        ),
      ).then((_) {
        // After PIN setup, go to login page
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const IntroPage()),
          );
        }
      });
    }
  }
  
  // Sign Up Part and form and buttons
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                Text(
                  "Sign Up",
                  style: GoogleFonts.alice(
                    fontSize: 35,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 40),

                // --- Full name field ---
                TextFormField(
                  controller: fullNameController,
                  decoration: InputDecoration(
                    hintText: "Full name",
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Full name is required";
                    }
                    if (!_isValidName(value.trim())) {
                      return "Please enter a valid name (e.g. John A. Doe)";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // --- Email field ---
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "Email address",
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Email is required";
                    }

                    final email = value.trim().toLowerCase();
                    if (!_isValidEmail(email)) {
                      return "Please enter a valid Gmail address";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // --- Password field ---
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Password",
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Password is required";
                    }
                    if (value.length < 8) {
                      return "Password must be at least 8 characters";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 40),

                // --- Terms Checkbox ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: acceptedTerms,
                      onChanged: (value) {
                        setState(() {
                          acceptedTerms = value!;
                        });
                      },
                      activeColor: Colors.black,
                    ),
                    Flexible(
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: "I accept the "),
                            TextSpan(
                              text: "Terms & Conditions",
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const TermsPage()),
                                  );
                                },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 5),

                // --- Create Account button ---
                SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (!acceptedTerms || isLoading) ? null : _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        acceptedTerms ? Colors.black : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text(
                          "Create Account",
                          style: GoogleFonts.alice(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                ),
              ),


                const SizedBox(height: 55),

                // --- Already have an account ---
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(text: "Already have an Account? "),
                      TextSpan(
                        text: "Sign in",
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const IntroPage()),
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
      ),
    );
  }
}
