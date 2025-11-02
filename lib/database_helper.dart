import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('refocus_unified.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          // Drop old tables and recreate
          await db.execute('DROP TABLE IF EXISTS usage_stats');
          await db.execute('DROP TABLE IF EXISTS app_details');
          
          await db.execute('''
            CREATE TABLE usage_stats (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL UNIQUE,
              daily_usage_hours REAL,
              max_session REAL,
              longest_session_app TEXT,
              most_unlock_app TEXT,
              most_unlock_count INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE app_details (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              date TEXT NOT NULL,
              package_name TEXT NOT NULL,
              usage_seconds REAL,
              unlock_count INTEGER,
              longest_session_seconds REAL,
              UNIQUE(date, package_name)
            )
          ''');
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fullName TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL
      )
    ''');

    // ✅ Main daily summary (what user sees - selected apps only)
    await db.execute('''
      CREATE TABLE usage_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        daily_usage_hours REAL,
        max_session REAL,
        longest_session_app TEXT,
        most_unlock_app TEXT,
        most_unlock_count INTEGER
      )
    ''');

    // ✅ Detailed per-app tracking (ALL apps)
    await db.execute('''
      CREATE TABLE app_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        package_name TEXT NOT NULL,
        usage_seconds REAL,
        unlock_count INTEGER,
        longest_session_seconds REAL,
        UNIQUE(date, package_name)
      )
    ''');
  }

  // ---------------- USER METHODS ----------------
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await instance.database;
    return await db.insert('users', user);
  }

  Future<Map<String, dynamic>?> getUser(String email, String password) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'email = ? AND password = ?',
      whereArgs: [email, password],
    );
    return result.isNotEmpty ? result.first : null;
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

  // ---------------- UNIFIED USAGE TRACKING ----------------
  
  /// ✅ Save daily summary (REPLACES today's entry)
  Future<void> saveUsageStats(Map<String, dynamic> stats) async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await db.insert(
      'usage_stats',
      {
        'date': today,
        'daily_usage_hours': (stats['daily_usage_hours'] as num? ?? 0).toDouble(),
        'max_session': (stats['max_session'] as num? ?? 0).toDouble(),
        'longest_session_app': stats['longest_session_app'] ?? 'None',
        'most_unlock_app': stats['most_unlock_app'] ?? 'None',
        'most_unlock_count': (stats['most_unlock_count'] as int? ?? 0),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// ✅ Save detailed per-app usage (ALL apps)
  Future<void> saveDetailedAppUsage({
    required String date,
    required Map<String, double> appUsage,
    required Map<String, int> appUnlocks,
    required Map<String, double> appLongestSessions,
  }) async {
    final db = await instance.database;

    // Delete old entries for this date
    await db.delete('app_details', where: 'date = ?', whereArgs: [date]);

    // Insert all app data
    for (var pkg in appUsage.keys) {
      await db.insert(
        'app_details',
        {
          'date': date,
          'package_name': pkg,
          'usage_seconds': appUsage[pkg] ?? 0.0,
          'unlock_count': appUnlocks[pkg] ?? 0,
          'longest_session_seconds': appLongestSessions[pkg] ?? 0.0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// ✅ Get today's summary stats
  Future<Map<String, dynamic>?> getTodayStats() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    final result = await db.query(
      'usage_stats',
      where: 'date = ?',
      whereArgs: [today],
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  /// ✅ Get today's detailed app breakdown
  Future<List<Map<String, dynamic>>> getTodayAppDetails() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    
    return await db.query(
      'app_details',
      where: 'date = ?',
      whereArgs: [today],
      orderBy: 'usage_seconds DESC',
    );
  }

  /// ✅ Get specific app's usage for a date
  Future<Map<String, dynamic>?> getAppUsageForDate(
    String packageName, 
    String date
  ) async {
    final db = await instance.database;
    
    final result = await db.query(
      'app_details',
      where: 'date = ? AND package_name = ?',
      whereArgs: [date, packageName],
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  /// ✅ Get last N days of summary stats
  Future<List<Map<String, dynamic>>> getRecentStats(int days) async {
    final db = await instance.database;
    return await db.query(
      'usage_stats',
      orderBy: 'date DESC',
      limit: days,
    );
  }

  /// ✅ Get all-time stats
  Future<List<Map<String, dynamic>>> getAllUsageStats() async {
    final db = await instance.database;
    return await db.query('usage_stats', orderBy: 'date DESC');
  }

  /// ✅ Get this week's summary stats
  Future<List<Map<String, dynamic>>> getWeekStats() async {
    final db = await instance.database;
    final today = DateTime.now();
    final weekAgo = today.subtract(const Duration(days: 7));
    final weekAgoStr = weekAgo.toIso8601String().substring(0, 10);
    
    return await db.query(
      'usage_stats',
      where: 'date >= ?',
      whereArgs: [weekAgoStr],
      orderBy: 'date ASC',
    );
  }

  /// ✅ Get week's detailed app usage
  Future<Map<String, Map<String, double>>> getWeekAppDetails() async {
    final db = await instance.database;
    final today = DateTime.now();
    final weekAgo = today.subtract(const Duration(days: 7));
    final weekAgoStr = weekAgo.toIso8601String().substring(0, 10);
    
    final results = await db.query(
      'app_details',
      where: 'date >= ?',
      whereArgs: [weekAgoStr],
      orderBy: 'date ASC',
    );

    // Group by app
    Map<String, Map<String, double>> weekData = {};
    for (var row in results) {
      String pkg = row['package_name'] as String;
      String date = row['date'] as String;
      double usage = (row['usage_seconds'] as num).toDouble() / 60; // Convert to minutes

      weekData[pkg] ??= {};
      weekData[pkg]![date] = usage;
    }

    return weekData;
  }

  /// ✅ Get top apps for a date range
  Future<List<Map<String, dynamic>>> getTopApps({
    required String startDate,
    required String endDate,
    int limit = 10,
  }) async {
    final db = await instance.database;
    
    final results = await db.rawQuery('''
      SELECT 
        package_name,
        SUM(usage_seconds) as total_usage,
        SUM(unlock_count) as total_unlocks,
        MAX(longest_session_seconds) as max_session
      FROM app_details
      WHERE date >= ? AND date <= ?
      GROUP BY package_name
      ORDER BY total_usage DESC
      LIMIT ?
    ''', [startDate, endDate, limit]);

    return results;
  }

  /// ✅ Check if new day
  Future<bool> isNewDay() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final stats = await getAllUsageStats();
    
    if (stats.isEmpty) return true;
    
    final lastDate = stats.first['date'];
    return lastDate != today;
  }

  /// ✅ Clean old data
  Future<void> cleanOldStats(int keepDays) async {
    final db = await instance.database;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: keepDays))
        .toIso8601String()
        .substring(0, 10);
    
    await db.delete(
      'usage_stats',
      where: 'date < ?',
      whereArgs: [cutoffDate],
    );

    await db.delete(
      'app_details',
      where: 'date < ?',
      whereArgs: [cutoffDate],
    );
    
    print("🗑️ Cleaned data older than $cutoffDate");
  }

  /// ✅ Get analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary(String date) async {
    final db = await instance.database;
    
    // Get daily summary
    final dailyStats = await db.query(
      'usage_stats',
      where: 'date = ?',
      whereArgs: [date],
    );

    // Get app breakdown
    final appDetails = await db.query(
      'app_details',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'usage_seconds DESC',
    );

    // Calculate totals
    double totalAllAppsSeconds = appDetails.fold(
      0.0, 
      (sum, app) => sum + ((app['usage_seconds'] as num?)?.toDouble() ?? 0)
    );

    int totalUnlocks = appDetails.fold(
      0, 
      (sum, app) => sum + ((app['unlock_count'] as int?) ?? 0)
    );

    return {
      'date': date,
      'summary': dailyStats.isNotEmpty ? dailyStats.first : null,
      'total_apps_used': appDetails.length,
      'total_all_apps_hours': totalAllAppsSeconds / 3600,
      'total_unlocks': totalUnlocks,
      'app_breakdown': appDetails.take(10).toList(),
    };
  }

  Future close() async {
    final db = _database;
    if (db != null) await db.close();
  }
}