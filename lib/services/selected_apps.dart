import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SelectedAppsManager {
  static List<Map<String, String>> selectedApps = [];

  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('selectedApps');
    if (jsonString != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        selectedApps = decodedList
            .map<Map<String, String>>(
                (item) => Map<String, String>.from(item as Map))
            .toList();
      } catch (_) {
        selectedApps = [];
      }
    }
  }

  static Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedApps', jsonEncode(selectedApps));
  }
}


