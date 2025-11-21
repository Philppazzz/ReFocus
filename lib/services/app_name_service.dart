import 'package:flutter/services.dart';

/// Service for fetching real human-readable app names
/// Uses Android PackageManager to convert package names to app labels
class AppNameService {
  static const platform = MethodChannel('com.example.refocus/app_names');

  // Cache app names to avoid repeated Android calls
  static final Map<String, String> _nameCache = {};

  /// Get real app name for a package
  /// Returns app label (e.g., "Facebook") instead of package name
  /// Caches results for performance
  static Future<String> getAppName(String packageName) async {
    // Check cache first
    if (_nameCache.containsKey(packageName)) {
      return _nameCache[packageName]!;
    }

    try {
      // Query Android PackageManager
      final String? appName = await platform.invokeMethod<String>(
        'getAppLabel',
        {'packageName': packageName},
      );

      if (appName != null && appName.isNotEmpty) {
        _nameCache[packageName] = appName;
        return appName;
      }

      // Fallback: return package name if app name not found
      return packageName;
    } catch (e) {
      print('⚠️ Error getting app name for $packageName: $e');
      return packageName; // Fallback to package name
    }
  }

  /// Get multiple app names at once (batch operation)
  /// More efficient than calling getAppName multiple times
  static Future<Map<String, String>> getAppNames(List<String> packageNames) async {
    final Map<String, String> results = {};

    try {
      // Get names that are already cached
      for (final packageName in packageNames) {
        if (_nameCache.containsKey(packageName)) {
          results[packageName] = _nameCache[packageName]!;
        }
      }

      // Get uncached names from Android
      final uncached = packageNames.where((pkg) => !_nameCache.containsKey(pkg)).toList();

      if (uncached.isNotEmpty) {
        final Map<dynamic, dynamic>? androidResults = await platform.invokeMethod<Map<dynamic, dynamic>>(
          'getAppLabels',
          {'packageNames': uncached},
        );

        if (androidResults != null) {
          androidResults.forEach((packageName, appName) {
            final String pkg = packageName as String;
            final String name = appName as String;
            _nameCache[pkg] = name;
            results[pkg] = name;
          });
        }
      }

      // Fill in any missing with package name as fallback
      for (final packageName in packageNames) {
        if (!results.containsKey(packageName)) {
          results[packageName] = packageName;
        }
      }

      return results;
    } catch (e) {
      print('⚠️ Error getting batch app names: $e');
      // Fallback: use package names
      for (final packageName in packageNames) {
        results[packageName] = packageName;
      }
      return results;
    }
  }

  /// Clear the name cache (useful for testing or after app updates)
  static void clearCache() {
    _nameCache.clear();
    print('🗑️ App name cache cleared');
  }

  /// Get cache size
  static int getCacheSize() {
    return _nameCache.length;
  }
}
