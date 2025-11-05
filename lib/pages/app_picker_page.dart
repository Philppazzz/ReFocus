import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter/services.dart';
import 'package:refocus_app/pages/home_page.dart';
import 'package:refocus_app/services/usage_service.dart';
 
import 'package:refocus_app/services/selected_apps.dart';

// ✅ Global manager moved to services/selected_apps.dart

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
        child: stage == 1
            ? SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
                  mainAxisSize: MainAxisSize.min,
            children: [
                    const SizedBox(height: 20),
              // 🔹 Progress bar
              LinearProgressIndicator(
                      value: 0.5,
                backgroundColor: Colors.grey[300],
                color: Colors.black,
                minHeight: 15,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 30),

              // 🔹 Title
              Text(
                      "Select the social media apps you want to track.\nYou can add or remove apps from the list.",
                textAlign: TextAlign.center,
                style: GoogleFonts.alice(
                  fontWeight: FontWeight.bold,
                  fontSize: 19.5,
                ),
              ),
              const SizedBox(height: 20),

              // 🔹 Stage 1: Pick apps
                SizedBox(
                      height: 350,
                      width: 350,
  child: Lottie.asset('assets/smartphone.json'),
),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _openAppPicker,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Select Apps",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                    const SizedBox(height: 20),
              ],
                ),
              )
            : Column(
                children: [
              // 🔹 Stage 2: Confirm selected apps
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 20),
                        // 🔹 Progress bar
                        LinearProgressIndicator(
                          value: 1.0,
                          backgroundColor: Colors.grey[300],
                          color: Colors.black,
                          minHeight: 15,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(height: 30),

                        // 🔹 Title
                        Text(
                          "Selected Apps",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.alice(
                            fontWeight: FontWeight.bold,
                            fontSize: 19.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      // Show selected count
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              selectedApps.isEmpty 
                                ? "No apps selected"
                                : "${selectedApps.length} app(s) selected",
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        child: selectedApps.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.apps, size: 64, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                  "No apps selected.",
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.grey),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      "Tap 'Select Apps' to choose apps to monitor.",
                                      style: TextStyle(
                                          fontSize: 14, color: Colors.grey),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
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
                                      trailing: const Icon(Icons.check_circle, 
                                          color: Colors.green),
                                    ),
                                  );
                                },
                              ),
                      ),

                        // ✅ Confirm and Save button
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: ElevatedButton.icon(
                      onPressed: () async {
                        if (selectedApps.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Please select at least one app"),
                                    backgroundColor: Colors.orange,
                                  ),
                          );
                          return;
                        }

                              // Show saving indicator
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("💾 Saving ${selectedApps.length} app(s)..."),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: Colors.blue,
                                ),
                              );

                        // ✅ Save both name + package safely
                        SelectedAppsManager.selectedApps = detectedApps
                            .where((app) => selectedApps.contains(app['name']))
                            .map((app) => {
                                  'name': app['name'] ?? '',
                                  'package': app['package'] ?? _getFallbackPackage(app['name']),
                                })
                            .toList();

                        // 🔹 Save to SharedPreferences (ONLY update selected apps list)
                        await SelectedAppsManager.saveToPrefs();

                        print("✅ Saved apps (data preserved): ${SelectedAppsManager.selectedApps}");
                              
                              // Show confirmation
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "✅ ${selectedApps.length} app(s) saved successfully!\n${selectedApps.join(', ')}",
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 3),
                                ),
                              );

                        // ✅ Request usage access permission
                        bool granted = await UsageService.requestPermission();
                        if (!granted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please grant Usage Access permission in Settings."),
                                    backgroundColor: Colors.orange,
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
                              minimumSize: const Size(double.infinity, 50),
                      ),
                  ),
                ),
            ],
          ),
                  ),
                ],
        ),
      ),
    );
  }

  // 🔹 Bottom sheet for selecting apps
  void _openAppPicker() {
    // Start with currently selected apps (if any) for the modal
    List<String> modalSelectedApps = List.from(selectedApps);
    
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
                              setModalState(() => modalSelectedApps.clear()),
                          child: const Text(
                            "Clear All",
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
                        final isSelected = modalSelectedApps.contains(app);

                        return CheckboxListTile(
                          title: Text(app),
                          value: isSelected,
                          activeColor: Colors.black,
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true) {
                                if (!modalSelectedApps.contains(app)) {
                                  modalSelectedApps.add(app);
                                }
                              } else {
                                modalSelectedApps.remove(app);
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
                        // CRITICAL: Save selected apps from modal to parent state
                        // Close modal first, then update state
                        Navigator.pop(context);
                        
                        // Update parent state after modal closes
                        setState(() {
                          selectedApps = List.from(modalSelectedApps);
                          stage = 2;
                        });
                        
                        // Show confirmation after state update
                        Future.delayed(const Duration(milliseconds: 300), () {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  modalSelectedApps.isEmpty 
                                    ? "No apps selected"
                                    : "✅ ${modalSelectedApps.length} app(s) selected: ${modalSelectedApps.join(', ')}",
                                ),
                                backgroundColor: modalSelectedApps.isEmpty ? Colors.orange : Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        });
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