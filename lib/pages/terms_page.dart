import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/pages/signup.dart';



class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6FA),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 0, right: 16, bottom: 16),
              child: Text(
                "Terms & Conditions",
                style: GoogleFonts.alice(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),

            // Scrollable text Card
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  color: const Color.fromARGB(255, 230, 233, 238),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Text(
                        "Here are the terms of service. Please read carefully...\n\n"
                        "1. You agree to use this app responsibly.\n\n"
                        "2. You understand that overusing your phone may affect your focus.\n\n"
                        "3. The app may monitor your screen time to help you self-regulate.\n\n"
                        "4. Continued use means you accept these terms.\n\n"
                        "5. ...",
                        style: GoogleFonts.alice(
                          fontSize: 16,
                          color: const Color.fromARGB(255, 20, 20, 20),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // button at bottom
            Padding(
    padding: const EdgeInsets.fromLTRB(16, 25, 16, 40),
    child: SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        
          
              onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SignupPage()),
        );
      },

    
        icon: const Icon(Icons.verified, color: Colors.white),
        label: const Text("Proceed"),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(255, 20, 20, 20),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    ),
)

            








            
          ],
        ),
      ),
    );
  }
}
