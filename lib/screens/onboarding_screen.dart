import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/services/learning_mode_manager.dart';
import 'package:refocus_app/pages/intro_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding screen explaining learning mode and ML benefits
/// Shows on first launch or when user hasn't completed onboarding
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
      
      if (mounted) {
        // Navigate to intro/login page (not directly to home)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const IntroPage()),
        );
      }
    } catch (e) {
      print('⚠️ Error completing onboarding: $e');
      // Fallback: just mark as completed and let user continue
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const IntroPage()),
        );
      }
    }
  }

  Future<void> _skipToRuleBased() async {
    // Enable rule-based mode, disable learning mode
    await LearningModeManager.setRuleBasedEnabled(true);
    await LearningModeManager.setLearningModeEnabled(false);
    await _completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                },
                children: [
                  _buildWelcomePage(),
                  _buildLearningModePage(),
                  _buildMLBenefitsPage(),
                  _buildTimelinePage(),
                  _buildChoicePage(),
                ],
              ),
            ),
            _buildBottomNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 16.0 : 24.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.psychology,
                  size: isSmallScreen ? 80 : 120,
                  color: Colors.black87,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                Text(
                  'Welcome to ReFocus',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 24 : 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  'The first app that learns YOUR phone usage patterns',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 14 : 18,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isSmallScreen ? 24 : 48),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, 
                            color: Colors.black87,
                            size: isSmallScreen ? 20 : 24,
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 12),
                          Expanded(
                            child: Text(
                              'Personalized to YOUR habits',
                              style: GoogleFonts.alice(
                                fontSize: isSmallScreen ? 14 : 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      Row(
                        children: [
                          Icon(Icons.check_circle, 
                            color: Colors.black87,
                            size: isSmallScreen ? 20 : 24,
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 12),
                          Expanded(
                            child: Text(
                              'Learns what works for YOU',
                              style: GoogleFonts.alice(
                                fontSize: isSmallScreen ? 14 : 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      Row(
                        children: [
                          Icon(Icons.check_circle, 
                            color: Colors.black87,
                            size: isSmallScreen ? 20 : 24,
                          ),
                          SizedBox(width: isSmallScreen ? 8 : 12),
                          Expanded(
                            child: Text(
                              'No generic one-size-fits-all rules',
                              style: GoogleFonts.alice(
                                fontSize: isSmallScreen ? 14 : 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLearningModePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 16.0 : 24.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.school,
                  size: isSmallScreen ? 70 : 100,
                  color: Colors.black87,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                Text(
                  'Learning Mode',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  'For the first few days, ReFocus will:',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                _buildFeatureCard(
                  icon: Icons.remove_red_eye,
                  title: 'Observe Your Patterns',
                  description: 'Learn when and how you use different apps',
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                _buildFeatureCard(
                  icon: Icons.feedback,
                  title: 'Ask for Feedback',
                  description: 'Occasionally ask if your usage was appropriate',
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                _buildFeatureCard(
                  icon: Icons.lock_open,
                  title: 'No Locks Yet',
                  description: 'Won\'t lock apps while learning your habits',
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[400]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, 
                        color: Colors.black87,
                        size: isSmallScreen ? 18 : 20,
                      ),
                      SizedBox(width: isSmallScreen ? 8 : 12),
                      Expanded(
                        child: Text(
                          'Safety limits are ALWAYS enforced (6h daily max)',
                          style: GoogleFonts.alice(
                            fontSize: isSmallScreen ? 11 : 13,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMLBenefitsPage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 16.0 : 24.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: isSmallScreen ? 70 : 100,
                  color: Colors.black87,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                Text(
                  'Why ML is Better',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                _buildComparisonCard(
                  title: 'Traditional Apps',
                  icon: Icons.close,
                  color: Colors.grey[600]!,
                  features: [
                    'Same limits for everyone',
                    'Doesn\'t adapt to your schedule',
                    'Can\'t learn what works for you',
                  ],
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
                _buildComparisonCard(
                  title: 'ReFocus with ML',
                  icon: Icons.check,
                  color: Colors.black87,
                  features: [
                    'Learns YOUR specific patterns',
                    'Adapts to your lifestyle',
                    'Gets smarter over time',
                  ],
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
                Text(
                  '40% more effective at reducing screen time*',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  '*Based on thesis research',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 9 : 11,
                    color: Colors.grey[500],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelinePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 16.0 : 24.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Journey',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                _buildTimelineItem(
                  day: 'Day 1-7',
                  title: 'Pure Learning',
                  description: 'No locks, just observing your habits',
                  icon: Icons.visibility,
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                _buildTimelineItem(
                  day: 'Day 5+',
                  title: 'ML Gets Ready',
                  description: 'When you have 300+ feedback samples',
                  icon: Icons.psychology,
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                _buildTimelineItem(
                  day: 'After ML Ready',
                  title: 'Smart Locks Active',
                  description: 'Personalized limits based on YOUR patterns',
                  icon: Icons.auto_awesome,
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                Container(
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.black87, Colors.black54],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed, 
                        color: Colors.white, 
                        size: isSmallScreen ? 24 : 32,
                      ),
                      SizedBox(width: isSmallScreen ? 12 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Most users ready in 5-10 days',
                              style: GoogleFonts.alice(
                                fontSize: isSmallScreen ? 14 : 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Depends on your app usage',
                              style: GoogleFonts.alice(
                                fontSize: isSmallScreen ? 11 : 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoicePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 20.0 : 24.0,
            vertical: isSmallScreen ? 16.0 : 24.0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Choose Your Mode',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 22 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                _buildModeChoice(
                  title: 'Learning Mode',
                  subtitle: 'Recommended',
                  description: 'Let ReFocus learn your patterns for best results',
                  icon: Icons.psychology,
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                  onTap: () async {
                    await LearningModeManager.setLearningModeEnabled(true);
                    await LearningModeManager.setRuleBasedEnabled(false);
                    await _completeOnboarding();
                  },
                ),
                SizedBox(height: isSmallScreen ? 16 : 20),
                _buildModeChoice(
                  title: 'Rule-Based Mode',
                  subtitle: 'Start locking immediately',
                  description: 'Use generic limits from day 1 (no ML)',
                  icon: Icons.lock,
                  color: Colors.black87,
                  isSmallScreen: isSmallScreen,
                  onTap: _skipToRuleBased,
                ),
                SizedBox(height: isSmallScreen ? 20 : 32),
                Text(
                  'You can change this later in settings',
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 11 : 13,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isSmallScreen ? 16 : 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    bool isSmallScreen = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, 
            color: color, 
            size: isSmallScreen ? 24 : 32,
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 11 : 13,
                    color: Colors.grey[700],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> features,
    bool isSmallScreen = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, 
                color: color, 
                size: isSmallScreen ? 22 : 28,
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: isSmallScreen ? 8 : 12),
          ...features.map((feature) => Padding(
                padding: EdgeInsets.only(top: isSmallScreen ? 6 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: isSmallScreen ? 4 : 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: GoogleFonts.alice(
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String day,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    bool isSmallScreen = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isSmallScreen ? 16 : 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: isSmallScreen ? 40 : 48,
                height: isSmallScreen ? 40 : 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, 
                  color: Colors.white, 
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
              Container(
                width: 2,
                height: isSmallScreen ? 30 : 40,
                color: color.withOpacity(0.3),
              ),
            ],
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 10 : 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  title,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.alice(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChoice({
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isSmallScreen = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: isSmallScreen ? 50 : 60,
              height: isSmallScreen ? 50 : 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, 
                color: color, 
                size: isSmallScreen ? 26 : 32,
              ),
            ),
            SizedBox(width: isSmallScreen ? 12 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.alice(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.alice(
                      fontSize: isSmallScreen ? 10 : 12,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.alice(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, 
              color: color,
              size: isSmallScreen ? 20 : 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final isSmallScreen = screenHeight < 600;
        
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 16 : 24,
            vertical: isSmallScreen ? 16 : 24,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_currentPage < 4)
                TextButton(
                  onPressed: () {
                    _pageController.animateToPage(
                      4,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Text(
                    'Skip',
                    style: GoogleFonts.alice(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              else
                SizedBox(width: isSmallScreen ? 50 : 60),
              Row(
                children: List.generate(
                  5,
                  (index) => Container(
                    margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 3 : 4),
                    width: _currentPage == index ? (isSmallScreen ? 20 : 24) : (isSmallScreen ? 6 : 8),
                    height: isSmallScreen ? 6 : 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? Colors.black87
                          : Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              if (_currentPage < 4)
                TextButton(
                  onPressed: () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Text(
                    'Next',
                    style: GoogleFonts.alice(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                )
              else
                SizedBox(width: isSmallScreen ? 50 : 60),
            ],
          ),
        );
      },
    );
  }
}

