import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:refocus_app/services/auth_service.dart';
import 'package:refocus_app/utils/category_mapper.dart';
import 'package:refocus_app/services/app_categorization_service.dart';

/// Cleaned up database helper - only essential tables and methods
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('refocus.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // ✅ PRODUCTION-SAFE: Only delete on version upgrade or corruption
    // Check if database file exists
    bool shouldDelete = false;
    try {
      // Try to open existing database to check version
      final existingDb = await openDatabase(
        path,
        version: 3,
        readOnly: true,
        onOpen: (db) async {
          // Database opened successfully
        },
      );
      
      try {
        final version = await existingDb.getVersion();
        await existingDb.close();
        
        // Only delete if version mismatch (upgrade scenario)
        if (version < 3) {
          print("🔄 Database version mismatch ($version < 3) - upgrading...");
          shouldDelete = true;
        } else {
          print("✅ Database exists with correct version ($version)");
        }
      } catch (e) {
        await existingDb.close();
        // Version check failed - might be corrupted
        print("⚠️ Error checking database version: $e - will recreate");
        shouldDelete = true;
      }
    } catch (e) {
      // Database doesn't exist or is corrupted - create new one
      print("ℹ️ Database doesn't exist or can't be opened: $e");
      shouldDelete = true;
    }

    if (shouldDelete) {
      print("🗑️ Deleting old/corrupted database...");
      try {
        await deleteDatabase(path);
        print("✅ Database deleted successfully");
      } catch (e) {
        print("ℹ️ No database to delete: $e");
      }
    } else {
      print("✅ Using existing database (version 3)");
    }

    // Open database with migration support
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        print("🔄 Upgrading database from version $oldVersion to $newVersion");
        // For now, recreate tables (can be optimized later)
        await _createDB(db, newVersion);
      },
    );
  }

  Future _createDB(Database db, int version) async {
    // ============ USER AUTHENTICATION ============
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fullName TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL
      )
    ''');

    // ============ CATEGORY-BASED SYSTEM ============

    // Apps catalog - maps packages to categories
    await db.execute('''
      CREATE TABLE apps_catalog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL UNIQUE,
        app_name TEXT,
        category TEXT NOT NULL,
        play_store_category TEXT,
        is_monitored INTEGER DEFAULT 1,
        last_updated INTEGER NOT NULL,
        is_system_app INTEGER DEFAULT 0,
        is_from_playstore INTEGER DEFAULT 0
      )
    ''');

    // Lock history - track category lock events
    await db.execute('''
      CREATE TABLE lock_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        category TEXT NOT NULL,
        lock_duration_seconds INTEGER NOT NULL,
        reason TEXT NOT NULL,
        violation_type TEXT
      )
    ''');

    // Decision tree data - for ML training
    await db.execute('''
      CREATE TABLE decision_tree_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        category TEXT NOT NULL,
        daily_usage_seconds INTEGER,
        current_session_seconds INTEGER,
        session_count INTEGER,
        time_of_day TEXT,
        day_of_week TEXT,
        should_lock INTEGER NOT NULL
      )
    ''');

    // Emergency unlocks - security feature
    await db.execute('''
      CREATE TABLE emergency_unlocks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        method TEXT NOT NULL,
        reason TEXT,
        location_latitude REAL,
        location_longitude REAL,
        trusted_contact_approved INTEGER DEFAULT 0,
        abuse_penalty_applied INTEGER DEFAULT 0
      )
    ''');

    // Session logs - track app sessions
    await db.execute('''
      CREATE TABLE session_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL,
        category TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration_seconds INTEGER,
        was_locked INTEGER DEFAULT 0
      )
    ''');

    // Usage stats - lightweight daily summary
    await db.execute('''
      CREATE TABLE usage_stats (
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        total_usage_seconds INTEGER NOT NULL,
        session_count INTEGER DEFAULT 0,
        PRIMARY KEY (date, category)
      ) WITHOUT ROWID
    ''');

    // App details - per-app usage tracking
    await db.execute('''
      CREATE TABLE app_details (
        date TEXT NOT NULL,
        package_name TEXT NOT NULL,
        app_name TEXT,
        category TEXT NOT NULL,
        usage_seconds INTEGER NOT NULL,
        unlock_count INTEGER DEFAULT 0,
        PRIMARY KEY (date, package_name)
      ) WITHOUT ROWID
    ''');

    // User feedback - for REAL ML training (not threshold-based)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_feedback (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        app_name TEXT NOT NULL,
        app_category TEXT NOT NULL,
        package_name TEXT,
        daily_usage_minutes INTEGER NOT NULL,
        session_usage_minutes INTEGER NOT NULL,
        time_of_day INTEGER NOT NULL,
        day_of_week INTEGER NOT NULL,
        was_helpful INTEGER NOT NULL,
        user_override INTEGER NOT NULL,
        lock_reason TEXT,
        prediction_source TEXT,
        model_confidence REAL,
        is_test_data INTEGER DEFAULT 0
      )
    ''');
    
    // ✅ SAFE TESTING: Add is_test_data column if it doesn't exist (for existing databases)
    try {
      await db.execute('ALTER TABLE user_feedback ADD COLUMN is_test_data INTEGER DEFAULT 0');
    } catch (e) {
      // Column already exists, ignore error
    }

    // ✅ PROFESSIONAL METRICS: Training history for model analytics
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ml_training_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        training_samples INTEGER NOT NULL,
        test_samples INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        precision REAL NOT NULL,
        recall REAL NOT NULL,
        f1_score REAL NOT NULL,
        train_accuracy REAL,
        overfitting_detected INTEGER DEFAULT 0
      )
    ''');

    // Create indexes for performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_apps_catalog_category ON apps_catalog(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lock_history_timestamp ON lock_history(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_decision_tree_timestamp ON decision_tree_data(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_session_logs_start ON session_logs(start_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_usage_stats_date ON usage_stats(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_details_date ON app_details(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_feedback_timestamp ON user_feedback(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_feedback_category ON user_feedback(app_category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_training_history_timestamp ON ml_training_history(timestamp)');
    
    // ✅ CRITICAL: Add indexes for frequently queried columns
    // These improve performance for getCategoryUsageForDate and similar queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_details_date_category ON app_details(date, category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_details_category ON app_details(category)');
  }

  // ============ USER METHODS ============

  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await instance.database;
    return await db.insert('users', user);
  }

  Future<Map<String, dynamic>?> getUser(String email, String password) async {
    final db = await instance.database;

    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (result.isEmpty) return null;

    final user = result.first;
    final storedPasswordHash = user['password'] as String?;

    if (storedPasswordHash == null) return null;

    final isValid = AuthService.verifyPassword(password, storedPasswordHash);

    return isValid ? user : null;
  }

  Future<bool> userExists(String email) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    return result.isNotEmpty;
  }

  Future<bool> updateUserPassword(String email, String newPassword) async {
    try {
      final db = await instance.database;
      final hashedPassword = AuthService.hashPassword(newPassword);
      final result = await db.update(
        'users',
        {'password': hashedPassword},
        where: 'email = ?',
        whereArgs: [email],
      );
      return result > 0;
    } catch (e) {
      print("⚠️ Error updating password: $e");
      return false;
    }
  }

  // ============ APP CATALOG METHODS ============

  /// Insert a single app into the catalog
  Future<int> insertAppCatalog(Map<String, dynamic> app) async {
    final db = await instance.database;
    return await db.insert(
      'apps_catalog',
      app,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bulk insert apps into catalog (for initial sync)
  Future<void> bulkInsertAppsCatalog(List<Map<String, dynamic>> apps) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var app in apps) {
      batch.insert(
        'apps_catalog',
        app,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get category for a specific package
  Future<String?> getAppCategory(String packageName) async {
    final db = await instance.database;
    final result = await db.query(
      'apps_catalog',
      columns: ['category'],
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );

    return result.isNotEmpty ? result.first['category'] as String? : null;
  }

  /// Get all apps in catalog
  Future<List<Map<String, dynamic>>> getAllAppsCatalog() async {
    final db = await instance.database;
    return await db.query('apps_catalog', orderBy: 'app_name ASC');
  }

  /// Get monitored apps only
  Future<List<Map<String, dynamic>>> getMonitoredApps() async {
    final db = await instance.database;
    return await db.query(
      'apps_catalog',
      where: 'is_monitored = 1',
      orderBy: 'app_name ASC',
    );
  }

  // ============ LOCK HISTORY METHODS ============

  /// Insert lock history entry
  Future<int> insertLockHistory(Map<String, dynamic> lock) async {
    final db = await instance.database;
    return await db.insert('lock_history', lock);
  }

  /// Get lock history for a date range
  Future<List<Map<String, dynamic>>> getLockHistory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await instance.database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (startDate != null && endDate != null) {
      whereClause = 'timestamp >= ? AND timestamp <= ?';
      whereArgs = [
        startDate.millisecondsSinceEpoch,
        endDate.millisecondsSinceEpoch,
      ];
    }

    return await db.query(
      'lock_history',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );
  }

  /// Get today's total locks
  Future<int> getTodayLockCount() async {
    final db = await instance.database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM lock_history WHERE timestamp >= ?',
      [startTimestamp],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get violation-free streak (consecutive days without lock events)
  Future<int> getViolationFreeStreak() async {
    final db = await instance.database;

    try {
      final lockResult = await db.rawQuery('''
        SELECT MAX(timestamp) as last_lock
        FROM lock_history
      ''');

      if (lockResult.isEmpty || lockResult.first['last_lock'] == null) {
        // No locks ever - return high streak
        return 30; // Default streak if no violations
      }

      final lastLockTimestamp = lockResult.first['last_lock'] as int;
      final lastLock = DateTime.fromMillisecondsSinceEpoch(lastLockTimestamp);
      final daysSinceLock = DateTime.now().difference(lastLock).inDays;

      return daysSinceLock;
    } catch (e) {
      print('Error getting violation-free streak: $e');
      return 0;
    }
  }

  // ============ DECISION TREE DATA METHODS ============

  /// Insert decision tree training data
  Future<int> insertDecisionTreeData(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('decision_tree_data', data);
  }

  /// Get decision tree training data
  Future<List<Map<String, dynamic>>> getDecisionTreeData({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final db = await instance.database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (startDate != null && endDate != null) {
      whereClause = 'timestamp >= ? AND timestamp <= ?';
      whereArgs = [
        startDate.millisecondsSinceEpoch,
        endDate.millisecondsSinceEpoch,
      ];
    }

    return await db.query(
      'decision_tree_data',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Get total training data count
  Future<int> getDecisionTreeDataCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM decision_tree_data');
    return (result.first['count'] as int?) ?? 0;
  }

  // ============ EMERGENCY UNLOCK METHODS ============

  /// Log an emergency unlock attempt
  Future<int> logEmergencyUnlock({
    required String method,
    String? reason,
    double? latitude,
    double? longitude,
    bool trustedContactApproved = false,
    bool abusePenaltyApplied = false,
  }) async {
    final db = await instance.database;
    return await db.insert(
      'emergency_unlocks',
      {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'method': method,
        'reason': reason,
        'location_latitude': latitude,
        'location_longitude': longitude,
        'trusted_contact_approved': trustedContactApproved ? 1 : 0,
        'abuse_penalty_applied': abusePenaltyApplied ? 1 : 0,
      },
    );
  }

  /// Get last emergency unlock timestamp
  Future<int?> getLastEmergencyUnlockTimestamp() async {
    final db = await instance.database;
    final result = await db.query(
      'emergency_unlocks',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['timestamp'] as int?;
  }

  /// Get emergency unlock count in last 24 hours
  Future<int> getEmergencyUnlockCountLast24Hours() async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dayAgo = now - (24 * 60 * 60 * 1000);

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM emergency_unlocks WHERE timestamp >= ?',
      [dayAgo],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get all emergency unlocks
  Future<List<Map<String, dynamic>>> getAllEmergencyUnlocks() async {
    final db = await instance.database;
    return await db.query(
      'emergency_unlocks',
      orderBy: 'timestamp DESC',
    );
  }

  // ============ SESSION LOGGING METHODS ============

  /// Log session start
  Future<int> logSessionStart() async {
    final db = await instance.database;
    return await db.insert('session_logs', {
      'package_name': 'unknown',
      'category': 'unknown',
      'start_time': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Log session end
  Future<void> logSessionEnd({
    required int sessionStart,
    String? reason,
    List<String>? appsUsed,
  }) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = ((now - sessionStart) / 1000).round();

    await db.insert('session_logs', {
      'package_name': appsUsed?.join(',') ?? 'unknown',
      'category': reason ?? 'unknown',
      'start_time': sessionStart,
      'end_time': now,
      'duration_seconds': duration,
      'was_locked': 0,
    });
  }

  // ============ USAGE STATS METHODS ============

  /// Save daily usage stats (accepts Map for compatibility)
  Future<void> saveUsageStats(Map<String, dynamic> stats) async {
    final db = await instance.database;

    // Extract data from map
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Save aggregate stats (simplified)
    await db.insert(
      'usage_stats',
      {
        'date': today,
        'category': 'all',
        'total_usage_seconds': ((stats['daily_usage_hours'] as num? ?? 0) * 3600).round(),
        'session_count': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save detailed app usage
  Future<void> saveDetailedAppUsage({
    required String date,
    required Map<String, double> appUsage,
    required Map<String, int> appUnlocks,
    required Map<String, double> appLongestSessions,
  }) async {
    final db = await instance.database;
    final batch = db.batch();

    // ✅ CRITICAL FIX: Get categories for all packages, ensuring proper categorization
    // This ensures messaging apps, system apps, and uncategorized apps go to "Others"
    final categoryMap = await _getCategoriesForPackages(appUsage.keys.toSet());

    for (var entry in appUsage.entries) {
      final packageName = entry.key;
      final usageSeconds = entry.value.round();
      final unlockCount = appUnlocks[packageName] ?? 0;
      
      // ✅ CRITICAL FIX: Ensure proper categorization
      // If app is not in catalog, try to get category from AppCategorizationService
      String category = categoryMap[packageName] ?? CategoryMapper.categoryOthers;
      
      // ✅ If category is "Others" or not found, verify it's actually "Others"
      // This ensures messaging apps, system apps, and uncategorized apps are properly tracked
      if (category == CategoryMapper.categoryOthers || !categoryMap.containsKey(packageName)) {
        try {
          // Try to get category from AppCategorizationService (handles messaging apps, system apps)
          final verifiedCategory = await AppCategorizationService.getCategoryForPackage(packageName);
          category = verifiedCategory;
          print("   ✅ Categorized $packageName as $category (was missing from catalog)");
        } catch (e) {
          // If categorization fails, default to "Others"
          category = CategoryMapper.categoryOthers;
          print("   ⚠️ Failed to categorize $packageName, defaulting to Others: $e");
        }
      }

      batch.insert(
        'app_details',
        {
          'date': date,
          'package_name': packageName,
          'app_name': packageName.split('.').last,
          'category': category,
          'usage_seconds': usageSeconds,
          'unlock_count': unlockCount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    print("✅ Saved ${appUsage.length} apps to database with proper categorization");
  }

  Future<Map<String, String>> _getCategoriesForPackages(
    Set<String> packages,
  ) async {
    final Map<String, String> categoryMap = {};
    if (packages.isEmpty) return categoryMap;

    final db = await instance.database;
    final placeholders = List.filled(packages.length, '?').join(',');
    final packageList = packages.toList();

    final rows = await db.rawQuery(
      'SELECT package_name, category FROM apps_catalog '
      'WHERE package_name IN ($placeholders)',
      packageList,
    );

    for (final row in rows) {
      final packageName = row['package_name'] as String?;
      final category = row['category'] as String?;
      if (packageName != null && category != null) {
        categoryMap[packageName] = category;
      }
    }

    // Fallback for packages not found in catalog
    for (final package in packages) {
      if (categoryMap.containsKey(package)) continue;
      final fallback = CategoryMapper.mapPackageToCategory(package) ??
          CategoryMapper.categoryOthers;
      categoryMap[package] = fallback;
    }

    return categoryMap;
  }

  /// Get total usage minutes per category for a specific date
  Future<Map<String, double>> getCategoryUsageForDate(DateTime date) async {
    final db = await instance.database;
    final dateKey = _dateKey(date);
    
    // Get all app details for the date
    final allApps = await db.query(
      'app_details',
      where: 'date = ?',
      whereArgs: [dateKey],
    );

    final usage = <String, double>{
      CategoryMapper.categorySocial: 0.0,
      CategoryMapper.categoryGames: 0.0,
      CategoryMapper.categoryEntertainment: 0.0,
      CategoryMapper.categoryOthers: 0.0,
    };

    // Group by category, including messaging apps in "Others" category
    for (final row in allApps) {
      final category = row['category'] as String? ?? CategoryMapper.categoryOthers;
      final seconds = (row['usage_seconds'] as num?)?.toDouble() ?? 0.0;
      
      // ✅ Messaging apps are now included in "Others" category usage
      // They are tracked and shown in the dashboard
      
      usage[category] = (usage[category] ?? 0.0) + (seconds / 60.0);
    }

    return usage;
  }

  /// Get top 3 most unlocked apps for the week
  Future<List<Map<String, dynamic>>> getTopUnlockedAppsWeek() async {
    final db = await instance.database;
    final today = DateTime.now();
    final weekAgo = today.subtract(const Duration(days: 7));
    
    final result = await db.rawQuery('''
      SELECT 
        package_name,
        SUM(unlock_count) as total_unlocks
      FROM app_details
      WHERE date >= ? AND date <= ?
      GROUP BY package_name
      HAVING total_unlocks > 0
      ORDER BY total_unlocks DESC
      LIMIT 3
    ''', [_dateKey(weekAgo), _dateKey(today)]);
    
    return result;
  }

  /// Get top 3 longest used apps for today
  Future<List<Map<String, dynamic>>> getTopLongestUsedAppsToday() async {
    final db = await instance.database;
    final today = DateTime.now();
    
    final result = await db.rawQuery('''
      SELECT 
        package_name,
        usage_seconds
      FROM app_details
      WHERE date = ?
      ORDER BY usage_seconds DESC
      LIMIT 3
    ''', [_dateKey(today)]);
    
    return result;
  }

  /// Get top 3 longest used apps for the week
  Future<List<Map<String, dynamic>>> getTopLongestUsedAppsWeek() async {
    final db = await instance.database;
    final today = DateTime.now();
    final weekAgo = today.subtract(const Duration(days: 7));
    
    final result = await db.rawQuery('''
      SELECT 
        package_name,
        SUM(usage_seconds) as total_seconds
      FROM app_details
      WHERE date >= ? AND date <= ?
      GROUP BY package_name
      HAVING total_seconds > 0
      ORDER BY total_seconds DESC
      LIMIT 3
    ''', [_dateKey(weekAgo), _dateKey(today)]);
    
    return result;
  }

  /// Get total usage minutes for each date starting from [startDate]
  Future<Map<String, double>> getUsageTotalsSince(DateTime startDate) async {
    final db = await instance.database;
    final startKey = _dateKey(startDate);

    final result = await db.rawQuery(
      '''
      SELECT date, SUM(usage_seconds) AS total_seconds
      FROM app_details
      WHERE date >= ?
      GROUP BY date
      ORDER BY date ASC
      ''',
      [startKey],
    );

    final totals = <String, double>{};
    for (final row in result) {
      final date = row['date'] as String? ?? '';
      final seconds = (row['total_seconds'] as num?)?.toDouble() ?? 0.0;
      totals[date] = seconds / 60.0;
    }

    return totals;
  }

  /// Get top apps by unlock count
  Future<List<Map<String, dynamic>>> getTopApps({
    String? startDate,
    String? endDate,
    int limit = 10,
  }) async {
    final db = await instance.database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (startDate != null && endDate != null) {
      whereClause = 'date >= ? AND date <= ?';
      whereArgs = [startDate, endDate];
    } else if (startDate != null) {
      whereClause = 'date = ?';
      whereArgs = [startDate];
    }

    return await db.query(
      'app_details',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'unlock_count DESC',
      limit: limit,
    );
  }

  /// Get weekly most unlocked apps (aggregated by package name)
  Future<List<Map<String, dynamic>>> getWeeklyMostUnlockedApps({
    int limit = 3,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartKey = _dateKey(weekStart);
    final weekEndKey = _dateKey(now);

    final result = await db.rawQuery('''
      SELECT 
        package_name,
        app_name,
        SUM(unlock_count) as total_unlocks,
        MAX(app_name) as display_name
      FROM app_details
      WHERE date >= ? AND date <= ?
      AND unlock_count > 0
      GROUP BY package_name
      ORDER BY total_unlocks DESC
      LIMIT ?
    ''', [weekStartKey, weekEndKey, limit]);

    return result.map((row) => {
      'packageName': row['package_name'] as String,
      'appName': row['display_name'] as String? ?? row['package_name'] as String,
      'unlockCount': (row['total_unlocks'] as num?)?.toInt() ?? 0,
    }).toList();
  }

  /// Get top longest used apps for today (by usage_seconds)
  Future<List<Map<String, dynamic>>> getTodayLongestUsedApps({
    int limit = 3,
  }) async {
    final db = await instance.database;
    final todayKey = _dateKey(DateTime.now());

    final result = await db.rawQuery('''
      SELECT 
        package_name,
        app_name,
        usage_seconds
      FROM app_details
      WHERE date = ?
      AND usage_seconds > 0
      ORDER BY usage_seconds DESC
      LIMIT ?
    ''', [todayKey, limit]);

    return result.map((row) => {
      'packageName': row['package_name'] as String,
      'appName': row['app_name'] as String? ?? row['package_name'] as String,
      'usageMinutes': ((row['usage_seconds'] as num?)?.toDouble() ?? 0.0) / 60.0,
    }).toList();
  }

  /// Get top longest used apps for the week (aggregated by package name)
  Future<List<Map<String, dynamic>>> getWeeklyLongestUsedApps({
    int limit = 3,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartKey = _dateKey(weekStart);
    final weekEndKey = _dateKey(now);

    final result = await db.rawQuery('''
      SELECT 
        package_name,
        app_name,
        SUM(usage_seconds) as total_usage_seconds,
        MAX(app_name) as display_name
      FROM app_details
      WHERE date >= ? AND date <= ?
      AND usage_seconds > 0
      GROUP BY package_name
      ORDER BY total_usage_seconds DESC
      LIMIT ?
    ''', [weekStartKey, weekEndKey, limit]);

    return result.map((row) => {
      'packageName': row['package_name'] as String,
      'appName': row['display_name'] as String? ?? row['package_name'] as String,
      'usageMinutes': ((row['total_usage_seconds'] as num?)?.toDouble() ?? 0.0) / 60.0,
    }).toList();
  }

  /// Get peak usage hours (returns String for compatibility)
  Future<String> getPeakUsageHours() async {
    final db = await instance.database;

    try {
      final sessions = await db.query(
        'session_logs',
        where: 'end_time IS NOT NULL',
        orderBy: 'start_time DESC',
        limit: 100,
      );

      if (sessions.isEmpty) {
        return 'Not enough data';
      }

      // Group by hour
      Map<int, int> hourlyUsage = {};

      for (var session in sessions) {
        final startTime = session['start_time'] as int;
        final hour = DateTime.fromMillisecondsSinceEpoch(startTime).hour;
        final duration = (session['duration_seconds'] as int?) ?? 0;

        hourlyUsage[hour] = (hourlyUsage[hour] ?? 0) + duration;
      }

      // Find top 3 peak hours
      var sortedHours = hourlyUsage.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sortedHours.isEmpty) {
        return 'Not enough data';
      }

      // Format as readable string
      final topHours = sortedHours.take(3).map((e) {
        final hour = e.key;
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour$period';
      }).join(', ');

      return topHours;
    } catch (e) {
      print('Error getting peak usage hours: $e');
      return 'Not enough data';
    }
  }

  /// Log violation (compatibility method)
  Future<void> logViolation({
    String? violationType,
    String? appName,
    String? appPackage,
    double? dailyHours,
    double? sessionMinutes,
    int? unlockCount,
    int? cooldownSeconds,
  }) async {
    final category = appName ?? appPackage ?? 'unknown';
    final reason = violationType ?? 'limit_exceeded';
    final lockDuration = cooldownSeconds ?? (sessionMinutes != null ? (sessionMinutes * 60).round() : 0);

    await insertLockHistory({
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'category': category,
      'lock_duration_seconds': lockDuration,
      'reason': reason,
      'violation_type': violationType,
    });
  }

  // ============ UTILITY METHODS ============

  /// Clean old data (keep last 90 days)
  Future<void> cleanOldData() async {
    final db = await instance.database;
    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
    final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;
    final cutoffDateStr = '${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}';

    // Clean old lock history
    await db.delete(
      'lock_history',
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );

    // Clean old emergency unlocks
    await db.delete(
      'emergency_unlocks',
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );

    // Clean old session logs
    await db.delete(
      'session_logs',
      where: 'start_time < ?',
      whereArgs: [cutoffTimestamp],
    );

    // Clean old usage stats
    await db.delete(
      'usage_stats',
      where: 'date < ?',
      whereArgs: [cutoffDateStr],
    );

    // Clean old app details
    await db.delete(
      'app_details',
      where: 'date < ?',
      whereArgs: [cutoffDateStr],
    );

    // Keep only last 50 training history entries
    final historyCountResult = await db.rawQuery('SELECT COUNT(*) as count FROM ml_training_history');
    final historyCount = (historyCountResult.first['count'] as int?) ?? 0;

    if (historyCount > 50) {
      // Delete oldest entries, keeping newest 50
      await db.rawQuery('''
        DELETE FROM ml_training_history
        WHERE id NOT IN (
          SELECT id FROM ml_training_history
          ORDER BY timestamp DESC
          LIMIT 50
        )
      ''');
    }

    // Keep only last 1000 decision tree training data points
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM decision_tree_data');
    final count = (countResult.first['count'] as int?) ?? 0;

    if (count > 1000) {
      // Delete oldest entries, keeping newest 1000
      await db.rawQuery('''
        DELETE FROM decision_tree_data
        WHERE id NOT IN (
          SELECT id FROM decision_tree_data
          ORDER BY timestamp DESC
          LIMIT 1000
        )
      ''');
    }

    print("🗑️ Cleaned old data (kept last 90 days)");
  }

  // ============ ML TRAINING HISTORY METHODS ============

  /// Save training history for analytics
  Future<int> saveTrainingHistory({
    required int timestamp,
    required int trainingSamples,
    required int testSamples,
    required double accuracy,
    required double precision,
    required double recall,
    required double f1Score,
    double? trainAccuracy,
    bool overfittingDetected = false,
  }) async {
    final db = await instance.database;
    return await db.insert(
      'ml_training_history',
      {
        'timestamp': timestamp,
        'training_samples': trainingSamples,
        'test_samples': testSamples,
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1_score': f1Score,
        'train_accuracy': trainAccuracy,
        'overfitting_detected': overfittingDetected ? 1 : 0,
      },
    );
  }

  /// Get training history (most recent first)
  Future<List<Map<String, dynamic>>> getTrainingHistory({int limit = 50}) async {
    final db = await instance.database;
    return await db.query(
      'ml_training_history',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// Get latest training metrics
  Future<Map<String, dynamic>?> getLatestTrainingMetrics() async {
    final db = await instance.database;
    final results = await db.query(
      'ml_training_history',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  Future close() async {
    final db = _database;
    if (db != null) await db.close();
  }
}
