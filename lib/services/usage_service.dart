import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:refocus_app/database_helper.dart';
import 'dart:convert';

class UsageService {
  static Future<bool> requestPermission() async {
    bool granted = await UsageStats.checkUsagePermission() ?? false;
    if (!granted) {
      await UsageStats.grantUsagePermission();
      await Future.delayed(const Duration(seconds: 2));
      granted = await UsageStats.checkUsagePermission() ?? false;
    }
    return granted;
  }

  /// ✅ ONE DATABASE FOR ALL APPS - Only selected apps show in totals
  static Future<Map<String, dynamic>> getUsageStatsWithEvents(
    List<Map<String, String>> selectedApps,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      // Check for new day
      if (await _checkAndResetNewDay(today, prefs)) {
        print("🌅 NEW DAY - Memory reset to 0");
      }

      // Get last processed timestamp
      final lastCheck = prefs.getInt('last_check_$today') ?? 
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
              .millisecondsSinceEpoch;

      DateTime now = DateTime.now();
      DateTime lookback = DateTime.fromMillisecondsSinceEpoch(lastCheck);

      print("\n🔍 Checking NEW events since: ${lookback.toString().substring(11, 19)}");

      // Query ALL events (not filtered)
      List<dynamic> events = await UsageStats.queryEvents(lookback, now);

      // Get selected packages
      final selectedPackages = selectedApps
          .map((a) => a['package']!)
          .where((p) => p.isNotEmpty)
          .toSet();

      final packageToName = {
        for (var app in selectedApps)
          if (app['package']!.isNotEmpty) app['package']!: app['name']!
      };

      // ✅ Load UNIFIED per-app data (ALL apps share this)
      final perAppUsageJson = prefs.getString('per_app_usage_$today') ?? '{}';
      Map<String, double> perAppUsage = {};
      try {
        perAppUsage = Map<String, double>.from(
          json.decode(perAppUsageJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        );
      } catch (e) {
        print("⚠️ Error loading per_app_usage: $e");
      }
      
      final perAppUnlocksJson = prefs.getString('per_app_unlocks_$today') ?? '{}';
      Map<String, int> perAppUnlocks = {};
      try {
        perAppUnlocks = Map<String, int>.from(json.decode(perAppUnlocksJson));
      } catch (e) {
        print("⚠️ Error loading per_app_unlocks: $e");
      }
      
      final perAppLongestJson = prefs.getString('per_app_longest_$today') ?? '{}';
      Map<String, double> perAppLongest = {};
      try {
        perAppLongest = Map<String, double>.from(
          json.decode(perAppLongestJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
        );
      } catch (e) {
        print("⚠️ Error loading per_app_longest: $e");
      }

      // Load processed session IDs
      final processedJson = prefs.getString('processed_$today') ?? '[]';
      Set<String> processed = Set<String>.from(json.decode(processedJson));

      // Load active session
      final activeAppKey = prefs.getString('active_app_$today');
      final activeStartMs = prefs.getInt('active_start_$today');
      
      String? currentActiveApp = activeAppKey;
      int? currentActiveStart = activeStartMs;

      if (events.isNotEmpty) {
        print("📊 Found ${events.length} new events");

        // Sort events by timestamp
        events.sort((a, b) {
          int tsA = a.timeStamp is String ? int.parse(a.timeStamp) : a.timeStamp as int;
          int tsB = b.timeStamp is String ? int.parse(b.timeStamp) : b.timeStamp as int;
          return tsA.compareTo(tsB);
        });

        // Process ALL events (track everything in one database)
        for (var event in events) {
          String? pkg = event.packageName;
          if (pkg == null || pkg.isEmpty) continue;

          int timestamp = event.timeStamp is String
              ? int.parse(event.timeStamp)
              : event.timeStamp as int;

          int eventType = event.eventType is String
              ? int.parse(event.eventType)
              : event.eventType as int;

          String sessionId = '${pkg}_$timestamp';
          if (processed.contains(sessionId)) continue;

          // Event type 1 = MOVE_TO_FOREGROUND
          if (eventType == 1) {
            // Close previous session if exists
            if (currentActiveApp != null && currentActiveStart != null) {
              double duration = (timestamp - currentActiveStart) / 1000.0;
              if (duration > 0 && duration < 7200) {
                perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + duration;
                
                if (duration > (perAppLongest[currentActiveApp] ?? 0)) {
                  perAppLongest[currentActiveApp] = duration;
                }

                processed.add('${currentActiveApp}_$currentActiveStart');
                
                // Only print if it's a selected app
                if (selectedPackages.contains(currentActiveApp)) {
                  print("   ➕ ${packageToName[currentActiveApp] ?? currentActiveApp}: +${(duration/60).toStringAsFixed(1)}m");
                }
              }
            }

            // Start new session
            currentActiveApp = pkg;
            currentActiveStart = timestamp;
            perAppUnlocks[pkg] = (perAppUnlocks[pkg] ?? 0) + 1;

            if (selectedPackages.contains(pkg)) {
              print("   🔓 ${packageToName[pkg] ?? pkg} opened (${perAppUnlocks[pkg]}x)");
            }
          }
          // Event type 2 = MOVE_TO_BACKGROUND
          else if (eventType == 2 && currentActiveApp == pkg && currentActiveStart != null) {
            double duration = (timestamp - currentActiveStart) / 1000.0;
            if (duration > 0 && duration < 7200) {
              perAppUsage[pkg] = (perAppUsage[pkg] ?? 0) + duration;
              
              if (duration > (perAppLongest[pkg] ?? 0)) {
                perAppLongest[pkg] = duration;
              }

              processed.add('${pkg}_$currentActiveStart');
              
              if (selectedPackages.contains(pkg)) {
                print("   ➕ ${packageToName[pkg] ?? pkg}: +${(duration/60).toStringAsFixed(1)}m");
              }
            }

            currentActiveApp = null;
            currentActiveStart = null;
          }
        }

        // Handle still-active session
        if (currentActiveApp != null && currentActiveStart != null) {
          double duration = (now.millisecondsSinceEpoch - currentActiveStart) / 1000.0;
          if (duration > 0 && duration < 7200) {
            perAppUsage[currentActiveApp] = (perAppUsage[currentActiveApp] ?? 0) + duration;
            
            if (duration > (perAppLongest[currentActiveApp] ?? 0)) {
              perAppLongest[currentActiveApp] = duration;
            }

            if (selectedPackages.contains(currentActiveApp)) {
              print("   🔄 ${packageToName[currentActiveApp] ?? currentActiveApp} active: +${(duration/60).toStringAsFixed(1)}m");
            }
          }
        }

        // Save unified database
        await prefs.setString('per_app_usage_$today', json.encode(perAppUsage));
        await prefs.setString('per_app_unlocks_$today', json.encode(perAppUnlocks));
        await prefs.setString('per_app_longest_$today', json.encode(perAppLongest));
        await prefs.setString('processed_$today', json.encode(processed.toList()));
        await prefs.setInt('last_check_$today', now.millisecondsSinceEpoch);
        
        // Save active session state
        if (currentActiveApp != null && currentActiveStart != null) {
          await prefs.setString('active_app_$today', currentActiveApp);
          await prefs.setInt('active_start_$today', currentActiveStart);
        } else {
          await prefs.remove('active_app_$today');
          await prefs.remove('active_start_$today');
        }
      } else {
        print("⏸️ No new events");
      }

      // ✅ RECALCULATE totals from unified database for SELECTED apps only
      double totalSeconds = 0.0;
      double longestSessionMins = 0.0;
      String longestApp = 'None';
      String mostUnlocked = 'None';
      int maxUnlocks = 0;

      print("\n📊 Calculating totals for SELECTED apps...");
      for (var pkg in selectedPackages) {
        // Add usage from this app
        double usage = perAppUsage[pkg] ?? 0.0;
        totalSeconds += usage;
        
        // Check if this is longest session
        double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
        if (sessionMins > longestSessionMins) {
          longestSessionMins = sessionMins;
          longestApp = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
        }

        // Check if most unlocked
        int count = perAppUnlocks[pkg] ?? 0;
        if (count > maxUnlocks) {
          maxUnlocks = count;
          mostUnlocked = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
        }

        if (usage > 0) {
          print("   ${packageToName[pkg] ?? pkg}: ${(usage/60).toStringAsFixed(1)}m (${count}x unlocks)");
        }
      }

      double hours = totalSeconds / 3600;

      print("\n✅ FINAL TOTALS (Selected Apps Only):");
      print("   Total: ${(totalSeconds/60).toStringAsFixed(1)}m");
      print("   Longest: $longestApp (${longestSessionMins.toStringAsFixed(1)}m)");
      print("   Most Unlocked: $mostUnlocked ($maxUnlocks times)");

      // Save to database
      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': hours,
        'max_session': longestSessionMins,
        'longest_session_app': longestApp,
        'most_unlock_app': mostUnlocked,
        'most_unlock_count': maxUnlocks,
      });

      await DatabaseHelper.instance.saveDetailedAppUsage(
        date: today,
        appUsage: perAppUsage,
        appUnlocks: perAppUnlocks,
        appLongestSessions: perAppLongest,
      );

      return {
        "daily_usage_hours": hours,
        "max_session": longestSessionMins,
        "longest_session_app": longestApp,
        "most_unlock_app": mostUnlocked,
        "most_unlock_count": maxUnlocks,
      };

    } catch (e, stack) {
      print("⚠️ ERROR: $e\n$stack");
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await _loadCurrentTotals(
        today, 
        await SharedPreferences.getInstance(),
        selectedApps
      );
    }
  }

  static Future<bool> _checkAndResetNewDay(String today, SharedPreferences prefs) async {
    final lastDate = prefs.getString('tracking_date') ?? '';
    if (lastDate != today) {
      print("\n🌅 NEW DAY: $lastDate → $today");
      
      await prefs.setString('tracking_date', today);
      await prefs.setString('per_app_usage_$today', '{}');
      await prefs.setString('per_app_unlocks_$today', '{}');
      await prefs.setString('per_app_longest_$today', '{}');
      await prefs.setString('processed_$today', '[]');
      await prefs.remove('active_app_$today');
      await prefs.remove('active_start_$today');
      await prefs.setInt('last_check_$today',
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .millisecondsSinceEpoch
      );

      await DatabaseHelper.instance.saveUsageStats({
        'daily_usage_hours': 0.0,
        'max_session': 0.0,
        'longest_session_app': 'None',
        'most_unlock_app': 'None',
        'most_unlock_count': 0,
      });

      return true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> _loadCurrentTotals(
    String date, 
    SharedPreferences prefs,
    List<Map<String, String>> selectedApps
  ) async {
    final packageToName = {
      for (var app in selectedApps)
        if (app['package']!.isNotEmpty) app['package']!: app['name']!
    };

    final selectedPackages = selectedApps
        .map((a) => a['package']!)
        .where((p) => p.isNotEmpty)
        .toSet();

    // Load unified database
    final perAppUsageJson = prefs.getString('per_app_usage_$date') ?? '{}';
    Map<String, double> perAppUsage = {};
    try {
      perAppUsage = Map<String, double>.from(
        json.decode(perAppUsageJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {}

    final perAppUnlocksJson = prefs.getString('per_app_unlocks_$date') ?? '{}';
    Map<String, int> perAppUnlocks = {};
    try {
      perAppUnlocks = Map<String, int>.from(json.decode(perAppUnlocksJson));
    } catch (e) {}
    
    final perAppLongestJson = prefs.getString('per_app_longest_$date') ?? '{}';
    Map<String, double> perAppLongest = {};
    try {
      perAppLongest = Map<String, double>.from(
        json.decode(perAppLongestJson).map((k, v) => MapEntry(k as String, (v as num).toDouble()))
      );
    } catch (e) {}

    // Recalculate from unified database for selected apps
    double totalSeconds = 0.0;
    double longestSessionMins = 0.0;
    String longestApp = 'None';
    String mostUnlocked = 'None';
    int maxUnlocks = 0;

    for (var pkg in selectedPackages) {
      totalSeconds += perAppUsage[pkg] ?? 0.0;
      
      double sessionMins = (perAppLongest[pkg] ?? 0) / 60;
      if (sessionMins > longestSessionMins) {
        longestSessionMins = sessionMins;
        longestApp = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
      }

      int count = perAppUnlocks[pkg] ?? 0;
      if (count > maxUnlocks) {
        maxUnlocks = count;
        mostUnlocked = packageToName[pkg] ?? _getAppNameFromPackage(pkg);
      }
    }

    return {
      "daily_usage_hours": totalSeconds / 3600,
      "max_session": longestSessionMins,
      "longest_session_app": longestApp,
      "most_unlock_app": mostUnlocked,
      "most_unlock_count": maxUnlocks,
    };
  }

  static String _getAppNameFromPackage(String packageName) {
    final knownApps = {
      'com.instagram.android': 'Instagram',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.google.android.youtube': 'YouTube',
      'com.facebook.katana': 'Facebook',
      'com.facebook.orca': 'Messenger',
      'com.twitter.android': 'Twitter',
      'com.snapchat.android': 'Snapchat',
      'com.whatsapp': 'WhatsApp',
      'com.linkedin.android': 'LinkedIn',
      'com.reddit.frontpage': 'Reddit',
    };

    return knownApps[packageName] ?? packageName.split('.').last;
  }
}