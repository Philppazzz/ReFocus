import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';
import 'package:refocus_app/pages/home_page.dart';
import 'package:refocus_app/services/usage_service.dart';
import 'dart:convert'; 
import 'package:shared_preferences/shared_preferences.dart';

// ✅ Global manager to hold selected apps (name + package)
class SelectedAppsManager {
  static List<Map<String, String>> selectedApps = [];
}

class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key});

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  int stage = 1;
  List<String> selectedApps = [];
  static const platform = MethodChannel('com.example.socialapps/channel');
  List<Map<String, String>> detectedApps = [];

  @override
  void initState() {
    super.initState();
    _fetchInstalledSocialApps();
  }

  /// 🔹 Fetch installed social apps using platform channel
  Future<void> _fetchInstalledSocialApps() async {
    try {
      final List<dynamic> apps = await platform.invokeMethod('getSocialApps');
      setState(() {
        detectedApps =
            apps.map((item) => Map<String, String>.from(item as Map)).toList();
      });
      print("📱 Detected apps: $detectedApps");
    } on PlatformException catch (e) {
      print("⚠️ Error fetching apps: ${e.message}");
    }
  }

  /// 🔹 Fallback function to assign known package names if missing
  String _getFallbackPackage(String? appName) {
    switch (appName?.toLowerCase()) {
      case 'facebook':
        return 'com.facebook.katana';
      case 'messenger':
        return 'com.facebook.orca';
      case 'instagram':
        return 'com.instagram.android';
      case 'tiktok':
        return 'com.zhiliaoapp.musically';
      case 'youtube':
        return 'com.google.android.youtube';
      case 'twitter':
      case 'x':
        return 'com.twitter.android';
      case 'snapchat':
        return 'com.snapchat.android';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      backgroundColor: const Color(0xFFF5F6FA),
    
      body: SafeArea(
        
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            
            children: [
               SizedBox(height: 50),
              // 🔹 Progress bar
              LinearProgressIndicator(
                value: stage == 1 ? 0.5 : 1.0,
                backgroundColor: Colors.grey[300],
                color: Colors.black,
                minHeight: 15,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 30),

              // 🔹 Title
              Text(
                stage == 1
                    ? "Select the social media apps you want to track.\nYou can add or remove apps from the list."
                    : "Selected Apps",
                textAlign: TextAlign.center,
                style: GoogleFonts.alice(
                  fontWeight: FontWeight.bold,
                  fontSize: 19.5,
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 Stage 1: Pick apps
              if (stage == 1) ...[
                SizedBox(
  height: 350, // increase height
  width: 350,  // increase width
  child: Lottie.asset('assets/smartphone.json'),
),

                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _openAppPicker,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 60, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Select Apps",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],

              // 🔹 Stage 2: Confirm selected apps
              if (stage == 2)
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: selectedApps.isEmpty
                            ? const Center(
                                child: Text(
                                  "No apps selected.",
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: selectedApps.length,
                                itemBuilder: (context, index) {
                                  final app = selectedApps[index];
                                  return Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    child: ListTile(
                                      leading: const Icon(Icons.apps,
                                          color: Colors.black),
                                      title: Text(app,
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // ✅ Confirm and Save (WITHOUT clearing data)
                      ElevatedButton.icon(
                      onPressed: () async {
                        if (selectedApps.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please select at least one app")),
                          );
                          return;
                        }

                        // ✅ Save both name + package safely
                        SelectedAppsManager.selectedApps = detectedApps
                            .where((app) => selectedApps.contains(app['name']))
                            .map((app) => {
                                  'name': app['name'] ?? '',
                                  'package': app['package'] ?? _getFallbackPackage(app['name']),
                                })
                            .toList();

                        // 🔹 Save to SharedPreferences (ONLY update selected apps list)
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'selectedApps',
                          jsonEncode(SelectedAppsManager.selectedApps),
                        );

                        print("✅ Saved apps (data preserved): ${SelectedAppsManager.selectedApps}");

                        // ✅ Request usage access permission
                        bool granted = await UsageService.requestPermission();
                        if (!granted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please grant Usage Access permission in Settings."),
                            ),
                          );
                          return;
                        }

                        // ✅ Navigate to HomePage
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const HomePage()),
                        );
                      },
                      icon: const Icon(Icons.verified, color: Colors.white),
                      label: const Text("Proceed", style: TextStyle(color: Colors.white, fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                      const SizedBox(height: 15),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔹 Bottom sheet for selecting apps
  void _openAppPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final allApps = detectedApps.isNotEmpty
            ? detectedApps.map((e) => e['name'] ?? '').toList()
            : ["Instagram", "TikTok", "YouTube", "Facebook", "Twitter"];

        TextEditingController searchController = TextEditingController();
        List<String> filteredApps = List.from(allApps);

        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterApps(String query) {
              setModalState(() {
                filteredApps = allApps
                    .where((app) =>
                        app.toLowerCase().contains(query.toLowerCase()))
                    .toList();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Back",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setModalState(() => selectedApps.clear()),
                          child: const Text(
                            "Restart",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                                fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // 🔹 Search box
                    TextField(
                      controller: searchController,
                      onChanged: filterApps,
                      decoration: InputDecoration(
                        hintText: "Search apps...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // 🔹 List of apps
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        final isSelected = selectedApps.contains(app);

                        return CheckboxListTile(
                          title: Text(app),
                          value: isSelected,
                          activeColor: Colors.black,
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true) {
                                selectedApps.add(app);
                              } else {
                                selectedApps.remove(app);
                              }
                            });
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 15),

                    // 🔹 Confirm selection button
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          stage = 2;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        "Confirm Selection",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}