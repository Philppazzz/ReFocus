import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../utils/category_mapper.dart';

/// Service for automatic app categorization using Play Store metadata
class AppCategorizationService {
  static const platform = MethodChannel('com.example.refocus/categorization');

  /// Sync all installed apps and categorize them
  /// Returns statistics about the categorization process
  static Future<Map<String, dynamic>> syncInstalledApps() async {
    try {
      // Get all installed apps from Android
      final List<dynamic> installedApps =
          await platform.invokeMethod('getAllInstalledApps');

      final db = DatabaseHelper.instance;
      final appsToInsert = <Map<String, dynamic>>[];
      final stats = {
        'total': installedApps.length,
        'social': 0,
        'games': 0,
        'entertainment': 0,
        'others': 0,
        'system_apps': 0,  // System apps categorized as Others
        'non_playstore_filtered': 0,  // Pirated/unverified apps excluded
      };

      for (var app in installedApps) {
        final packageName = app['packageName'] as String;
        final appName = app['appName'] as String;
        final playStoreCategory = app['category'] as String?;
        final isSystemApp = app['isSystemApp'] as bool? ?? false;
        final isFromPlayStore = app['isFromPlayStore'] as bool? ?? false;  // ✅ New field

        // ✅ CRITICAL: Filter out non-Play Store apps (pirated/unverified)
        // BUT: Keep system apps (they'll be categorized as "Others")
        if (!isFromPlayStore && !isSystemApp) {
          stats['non_playstore_filtered'] = (stats['non_playstore_filtered'] as int) + 1;
          continue;  // Skip this app - not from Play Store
        }

        // ✅ System apps always go to "Others" category
        String category;
        if (isSystemApp) {
          category = CategoryMapper.categoryOthers;
          stats['system_apps'] = (stats['system_apps'] as int) + 1;
        } else {
          // ✅ CRITICAL: Messaging apps ALWAYS go to "Others" category (never tracked)
          if (CategoryMapper.isMessagingApp(packageName)) {
            category = CategoryMapper.categoryOthers;
          } else {
            // ✅ Play Store apps: Use Play Store category
            category = CategoryMapper.mapPlayStoreCategory(playStoreCategory);

            // ✅ If category is Others or UNDEFINED, try hardcoded package mapping
            if (category == CategoryMapper.categoryOthers ||
                playStoreCategory == 'UNDEFINED') {
              final hardcodedCategory =
                  CategoryMapper.mapPackageToCategory(packageName);
              if (hardcodedCategory != null) {
                category = hardcodedCategory;
              }
            }
          }
        }

        // Update statistics
        switch (category) {
          case CategoryMapper.categorySocial:
            stats['social'] = (stats['social'] as int) + 1;
            break;
          case CategoryMapper.categoryGames:
            stats['games'] = (stats['games'] as int) + 1;
            break;
          case CategoryMapper.categoryEntertainment:
            stats['entertainment'] = (stats['entertainment'] as int) + 1;
            break;
          case CategoryMapper.categoryOthers:
            stats['others'] = (stats['others'] as int) + 1;
            break;
        }

        appsToInsert.add({
          'package_name': packageName,
          'app_name': appName,
          'category': category,
          'play_store_category': playStoreCategory ?? 'UNDEFINED',
          'is_monitored':
              CategoryMapper.shouldMonitorCategory(category) ? 1 : 0,
          'last_updated': DateTime.now().millisecondsSinceEpoch,
          'is_system_app': isSystemApp ? 1 : 0,
          'is_from_playstore': isFromPlayStore ? 1 : 0,  // ✅ Store verification status
        });
      }

      // Bulk insert into database
      if (appsToInsert.isNotEmpty) {
        await db.bulkInsertAppsCatalog(appsToInsert);
      }

      stats['categorized'] = appsToInsert.length;
      return stats;
    } catch (e) {
      throw Exception('Failed to sync installed apps: $e');
    }
  }

  /// Sync apps with progress updates (for large app lists)
  /// Processes apps in batches to avoid UI freezing
  ///
  /// [batchSize] - number of apps to process in each batch (default: 50)
  /// [onProgress] - callback with current progress (0.0 to 1.0) and status message
  /// [onBatchComplete] - callback after each batch with current stats
  static Future<Map<String, dynamic>> syncInstalledAppsWithProgress({
    int batchSize = 50,
    Function(double progress, String message)? onProgress,
    Function(Map<String, dynamic> stats)? onBatchComplete,
  }) async {
    try {
      onProgress?.call(0.0, 'Fetching installed apps...');

      // Get all installed apps from Android
      final List<dynamic> installedApps =
          await platform.invokeMethod('getAllInstalledApps');

      final db = DatabaseHelper.instance;
      final stats = {
        'total': installedApps.length,
        'social': 0,
        'games': 0,
        'entertainment': 0,
        'others': 0,
        'system_apps': 0,  // System apps categorized as Others
        'non_playstore_filtered': 0,  // Pirated/unverified apps excluded
        'categorized': 0,
      };

      final totalApps = installedApps.length;
      final batches = (totalApps / batchSize).ceil();

      onProgress?.call(0.1, 'Categorizing $totalApps apps in $batches batches...');

      for (var batchIndex = 0; batchIndex < batches; batchIndex++) {
        final startIndex = batchIndex * batchSize;
        final endIndex = (startIndex + batchSize).clamp(0, totalApps);
        final batch = installedApps.sublist(startIndex, endIndex);

        final appsToInsert = <Map<String, dynamic>>[];

        for (var app in batch) {
          final packageName = app['packageName'] as String;
          final appName = app['appName'] as String;
          final playStoreCategory = app['category'] as String?;
          final isSystemApp = app['isSystemApp'] as bool? ?? false;
          final isFromPlayStore = app['isFromPlayStore'] as bool? ?? false;  // ✅ New field

          // ✅ CRITICAL: Filter out non-Play Store apps (pirated/unverified)
          // BUT: Keep system apps (they'll be categorized as "Others")
          if (!isFromPlayStore && !isSystemApp) {
            stats['non_playstore_filtered'] = (stats['non_playstore_filtered'] as int) + 1;
            continue;  // Skip this app - not from Play Store
          }

          // ✅ System apps always go to "Others" category
          String category;
          if (isSystemApp) {
            category = CategoryMapper.categoryOthers;
            stats['system_apps'] = (stats['system_apps'] as int) + 1;
          } else {
            // ✅ CRITICAL: Messaging apps ALWAYS go to "Others" category (never tracked)
            if (CategoryMapper.isMessagingApp(packageName)) {
              category = CategoryMapper.categoryOthers;
            } else {
              // ✅ Play Store apps: Use Play Store category
              category = CategoryMapper.mapPlayStoreCategory(playStoreCategory);

              // ✅ If category is Others or UNDEFINED, try hardcoded package mapping
              if (category == CategoryMapper.categoryOthers ||
                  playStoreCategory == 'UNDEFINED') {
                final hardcodedCategory =
                    CategoryMapper.mapPackageToCategory(packageName);
                if (hardcodedCategory != null) {
                  category = hardcodedCategory;
                }
              }
            }
          }

          // Update statistics
          switch (category) {
            case CategoryMapper.categorySocial:
              stats['social'] = (stats['social'] as int) + 1;
              break;
            case CategoryMapper.categoryGames:
              stats['games'] = (stats['games'] as int) + 1;
              break;
            case CategoryMapper.categoryEntertainment:
              stats['entertainment'] = (stats['entertainment'] as int) + 1;
              break;
            case CategoryMapper.categoryOthers:
              stats['others'] = (stats['others'] as int) + 1;
              break;
          }

          appsToInsert.add({
            'package_name': packageName,
            'app_name': appName,
            'category': category,
            'play_store_category': playStoreCategory ?? 'UNDEFINED',
            'is_monitored':
                CategoryMapper.shouldMonitorCategory(category) ? 1 : 0,
            'last_updated': DateTime.now().millisecondsSinceEpoch,
            'is_system_app': isSystemApp ? 1 : 0,
            'is_from_playstore': isFromPlayStore ? 1 : 0,  // ✅ Store verification status
          });
        }

        // Insert batch into database
        if (appsToInsert.isNotEmpty) {
          await db.bulkInsertAppsCatalog(appsToInsert);
          stats['categorized'] = (stats['categorized'] as int) + appsToInsert.length;
        }

        // Update progress
        final progress = 0.1 + (0.9 * (batchIndex + 1) / batches);
        final message = 'Processed $endIndex of $totalApps apps...';
        onProgress?.call(progress, message);
        onBatchComplete?.call(Map.from(stats));

        // Small delay to allow UI to update
        await Future.delayed(const Duration(milliseconds: 50));
      }

      onProgress?.call(1.0, 'Categorization complete!');
      return stats;
    } catch (e) {
      throw Exception('Failed to sync installed apps: $e');
    }
  }

  /// Categorize a single newly installed app
  /// Used by background receiver when new apps are installed
  static Future<Map<String, dynamic>?> categorizeSingleApp(
      String packageName) async {
    try {
      final Map<dynamic, dynamic>? appInfo = await platform.invokeMethod(
        'getAppInfo',
        {'packageName': packageName},
      );

      if (appInfo == null) {
        return null;
      }

      final appName = appInfo['appName'] as String;
      final playStoreCategory = appInfo['category'] as String?;
      final isSystemApp = appInfo['isSystemApp'] as bool? ?? false;
      final isFromPlayStore = appInfo['isFromPlayStore'] as bool? ?? false;  // ✅ New field

      // ✅ CRITICAL: Filter out non-Play Store apps (but keep system apps)
      if (!isFromPlayStore && !isSystemApp) {
        return null;  // Skip non-Play Store apps
      }

      // ✅ System apps always go to "Others" category
      String category;
      if (isSystemApp) {
        category = CategoryMapper.categoryOthers;
      } else {
        // ✅ CRITICAL: Messaging apps ALWAYS go to "Others" category (never tracked)
        if (CategoryMapper.isMessagingApp(packageName)) {
          category = CategoryMapper.categoryOthers;
        } else {
          // ✅ Play Store apps: Use Play Store category
          category = CategoryMapper.mapPlayStoreCategory(playStoreCategory);

          // ✅ If category is Others or UNDEFINED, try hardcoded package mapping
          if (category == CategoryMapper.categoryOthers ||
              playStoreCategory == 'UNDEFINED') {
            final hardcodedCategory =
                CategoryMapper.mapPackageToCategory(packageName);
            if (hardcodedCategory != null) {
              category = hardcodedCategory;
            }
          }
        }
      }

      final appData = {
        'package_name': packageName,
        'app_name': appName,
        'category': category,
        'play_store_category': playStoreCategory ?? 'UNDEFINED',
        'is_monitored':
            CategoryMapper.shouldMonitorCategory(category) ? 1 : 0,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
        'is_system_app': isSystemApp ? 1 : 0,
        'is_from_playstore': isFromPlayStore ? 1 : 0,  // ✅ Store verification status
      };

      // Insert into database
      final db = DatabaseHelper.instance;
      await db.insertAppCatalog(appData);

      return appData;
    } catch (e) {
      return null;
    }
  }

  /// Get category for a specific package
  /// First checks database, then queries Android if not found
  static Future<String> getCategoryForPackage(String packageName) async {
    final db = DatabaseHelper.instance;

    // Check database first
    final category = await db.getAppCategory(packageName);
    if (category != null) {
      return category;
    }

    // Not in database - query Android
    try {
      final Map<dynamic, dynamic>? appInfo = await platform.invokeMethod(
        'getAppInfo',
        {'packageName': packageName},
      );

      if (appInfo != null) {
        final playStoreCategory = appInfo['category'] as String?;
        final isSystemApp = appInfo['isSystemApp'] as bool? ?? false;
        final isFromPlayStore = appInfo['isFromPlayStore'] as bool? ?? false;  // ✅ New field

        // ✅ CRITICAL: Filter out non-Play Store apps (but keep system apps)
        if (!isFromPlayStore && !isSystemApp) {
          return CategoryMapper.categoryOthers;  // Return Others for non-Play Store apps
        }

        // ✅ System apps always go to "Others" category
        String mappedCategory;
        if (isSystemApp) {
          mappedCategory = CategoryMapper.categoryOthers;
        } else {
          // ✅ CRITICAL: Messaging apps ALWAYS go to "Others" category (never tracked)
          if (CategoryMapper.isMessagingApp(packageName)) {
            mappedCategory = CategoryMapper.categoryOthers;
          } else {
            // ✅ Play Store apps: Use Play Store category
            mappedCategory = CategoryMapper.mapPlayStoreCategory(playStoreCategory);

            // ✅ Try hardcoded mapping if category is Others
            if (mappedCategory == CategoryMapper.categoryOthers ||
                playStoreCategory == 'UNDEFINED') {
              final hardcodedCategory =
                  CategoryMapper.mapPackageToCategory(packageName);
              if (hardcodedCategory != null) {
                mappedCategory = hardcodedCategory;
              }
            }
          }
        }

        // Insert into database for future queries
        await db.insertAppCatalog({
          'package_name': packageName,
          'app_name': appInfo['appName'] as String,
          'category': mappedCategory,
          'play_store_category': playStoreCategory ?? 'UNDEFINED',
          'is_monitored':
              CategoryMapper.shouldMonitorCategory(mappedCategory) ? 1 : 0,
          'last_updated': DateTime.now().millisecondsSinceEpoch,
          'is_system_app': isSystemApp ? 1 : 0,
          'is_from_playstore': isFromPlayStore ? 1 : 0,  // ✅ Store verification status
        });

        return mappedCategory;
      }

      // App not found - return Others
      return CategoryMapper.categoryOthers;
    } catch (e) {
      // Error querying Android - return Others as fallback
      return CategoryMapper.categoryOthers;
    }
  }

  /// Recategorize a specific app (useful for manual overrides)
  static Future<void> recategorizeApp(
      String packageName, String newCategory) async {
    if (!CategoryMapper.isValidCategory(newCategory)) {
      throw ArgumentError('Invalid category: $newCategory');
    }

    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    await dbConnection.update(
      'apps_catalog',
      {
        'category': newCategory,
        'is_monitored':
            CategoryMapper.shouldMonitorCategory(newCategory) ? 1 : 0,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'package_name = ?',
      whereArgs: [packageName],
    );
  }

  /// Get categorization statistics
  static Future<Map<String, int>> getCategoryStatistics() async {
    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    final result = await dbConnection.rawQuery('''
      SELECT category, COUNT(*) as count
      FROM apps_catalog
      WHERE is_monitored = 1
      GROUP BY category
    ''');

    final stats = <String, int>{};
    for (var row in result) {
      stats[row['category'] as String] = row['count'] as int;
    }

    return stats;
  }

  /// Get all apps in a specific category
  static Future<List<Map<String, dynamic>>> getAppsByCategory(
      String category) async {
    if (!CategoryMapper.isValidCategory(category)) {
      throw ArgumentError('Invalid category: $category');
    }

    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    return await dbConnection.query(
      'apps_catalog',
      where: 'category = ? AND is_monitored = 1',
      whereArgs: [category],
      orderBy: 'app_name ASC',
    );
  }

  /// Check if categorization data exists (first-time setup check)
  static Future<bool> isCatalogInitialized() async {
    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    final result = await dbConnection.rawQuery('''
      SELECT COUNT(*) as count FROM apps_catalog
    ''');

    final count = result.first['count'] as int;
    return count > 0;
  }

  /// Clear all categorization data
  static Future<void> clearCatalog() async {
    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    await dbConnection.delete('apps_catalog');
  }

  /// Export categorization data
  static Future<List<Map<String, dynamic>>> exportCatalog() async {
    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    return await dbConnection.query(
      'apps_catalog',
      orderBy: 'category ASC, app_name ASC',
    );
  }

  /// Update monitoring status for a category
  static Future<void> setCategoryMonitoring(
      String category, bool monitored) async {
    if (!CategoryMapper.isValidCategory(category)) {
      throw ArgumentError('Invalid category: $category');
    }

    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    await dbConnection.update(
      'apps_catalog',
      {
        'is_monitored': monitored ? 1 : 0,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  /// Get list of monitored apps (all apps that are being tracked)
  static Future<List<String>> getMonitoredPackages() async {
    final db = DatabaseHelper.instance;
    final dbConnection = await db.database;

    final result = await dbConnection.query(
      'apps_catalog',
      columns: ['package_name'],
      where: 'is_monitored = 1',
    );

    return result.map((row) => row['package_name'] as String).toList();
  }
}
