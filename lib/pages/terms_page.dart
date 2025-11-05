import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // Modern App Bar with gradient
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'Terms & Conditions',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern Header Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last Updated',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Sections with modern design
                  _buildSection(
                    number: '01',
                    icon: Icons.info_outline_rounded,
                    title: 'Introduction',
                    content: 'Welcome to ReFocus. By accessing or using our mobile application, you agree to be bound by these Terms & Conditions. '
                        'If you disagree with any part of these terms, you may not use our service.\n\n'
                        'ReFocus is a productivity application designed to help users manage their screen time and build healthier digital habits. '
                        'Our service provides tracking, limiting, and analytics features to support your focus and well-being.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '02',
                    icon: Icons.policy_rounded,
                    title: 'Usage Policy',
                    content: 'You agree to use ReFocus in a lawful manner and in accordance with these Terms. You agree not to:\n\n'
                        '• Attempt to circumvent or bypass the app\'s built-in limits and restrictions\n'
                        '• Use the app for any illegal or unauthorized purpose\n'
                        '• Modify, reverse engineer, or attempt to extract the source code of the application\n'
                        '• Interfere with or disrupt the app\'s functionality or security features\n'
                        '• Use the Emergency Unlock feature inappropriately or for non-emergency situations\n\n'
                        'Violation of these policies may result in termination of your access to the service.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '03',
                    icon: Icons.lock_outline_rounded,
                    title: 'Data Privacy',
                    content: 'Your privacy is important to us. ReFocus collects and stores usage data locally on your device to provide tracking and analytics features.\n\n'
                        '• All usage statistics, app selections, and preferences are stored locally on your device\n'
                        '• We do not transmit your personal usage data to external servers\n'
                        '• Your account information (email, password) is stored securely using encryption\n'
                        '• Emergency unlock events are logged locally for abuse prevention purposes\n\n'
                        'We do not sell, trade, or share your personal information with third parties. For more details, please refer to our Privacy Policy.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '04',
                    icon: Icons.person_outline_rounded,
                    title: 'User Responsibility',
                    content: 'You are responsible for:\n\n'
                        '• Maintaining the security of your account credentials\n'
                        '• Using the app in a manner that complies with all applicable laws\n'
                        '• Understanding that ReFocus is a tool to assist you, not a guarantee of behavioral change\n'
                        '• Making informed decisions about your digital habits\n'
                        '• Ensuring you have the necessary permissions (Usage Access, Notifications) for the app to function properly\n\n'
                        'ReFocus is provided "as is" and we cannot guarantee specific outcomes or results from using the application.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '05',
                    icon: Icons.cloud_outlined,
                    title: 'Service Availability',
                    content: 'We strive to maintain high availability of our service, but we do not guarantee uninterrupted access. '
                        'The app may be temporarily unavailable due to:\n\n'
                        '• System maintenance or updates\n'
                        '• Technical issues or bugs\n'
                        '• Device-specific limitations or restrictions\n'
                        '• Changes in operating system requirements\n\n'
                        'We reserve the right to modify, suspend, or discontinue any part of the service at any time.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '06',
                    icon: Icons.edit_outlined,
                    title: 'Changes to Terms',
                    content: 'We reserve the right to modify these Terms & Conditions at any time. '
                        'We will notify users of any material changes through:\n\n'
                        '• In-app notifications\n'
                        '• Updates to this Terms & Conditions page\n'
                        '• Email notifications (if applicable)\n\n'
                        'Your continued use of ReFocus after changes are posted constitutes your acceptance of the modified terms. '
                        'If you do not agree to the changes, you should discontinue use of the service.',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '07',
                    icon: Icons.shield_outlined,
                    title: 'Limitation of Liability',
                    content: 'ReFocus is provided for informational and self-improvement purposes. '
                        'We are not liable for:\n\n'
                        '• Any decisions made based on the app\'s data or recommendations\n'
                        '• Loss of data or functionality due to device issues or app updates\n'
                        '• Indirect, incidental, or consequential damages arising from use of the app\n'
                        '• Inaccuracies in usage tracking due to system limitations or permissions\n\n'
                        'Our total liability shall not exceed the amount you paid for the app (if any).',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  _buildSection(
                    number: '08',
                    icon: Icons.email_outlined,
                    title: 'Contact Information',
                    content: 'If you have any questions about these Terms & Conditions, please contact us at:\n\n'
                        'Email: support@refocus.app\n\n'
                        'We will make every effort to respond to your inquiries in a timely manner.',
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Modern Agreement Statement
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withOpacity(0.1),
                          const Color(0xFF8B5CF6).withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF6366F1),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'By using ReFocus, you acknowledge that you have read, understood, and agree to be bound by these Terms & Conditions.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              height: 1.6,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String number,
    required IconData icon,
    required String title,
    required String content,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with number and icon
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6366F1).withOpacity(0.1),
                  const Color(0xFF8B5CF6).withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  icon,
                  color: const Color(0xFF6366F1),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              content,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.8,
                color: Colors.black87,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
