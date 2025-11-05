import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:refocus_app/services/auth_service.dart';
import 'package:refocus_app/services/selected_apps.dart';

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
      version: 8,
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
        if (oldVersion < 5) {
          // Add emergency_unlocks table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS emergency_unlocks (
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
        }
        if (oldVersion < 6) {
          // Add violation_logs table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS violation_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              violation_type TEXT NOT NULL,
              app_name TEXT NOT NULL,
              app_package TEXT,
              daily_hours REAL,
              session_minutes REAL,
              unlock_count INTEGER,
              cooldown_seconds INTEGER
            )
          ''');
        }
        if (oldVersion < 7) {
          // Add session_logs table
          await db.execute('''
            CREATE TABLE IF NOT EXISTS session_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              session_start INTEGER NOT NULL,
              session_end INTEGER,
              duration_minutes REAL,
              ended_reason TEXT,
              apps_used TEXT
            )
          ''');
        }
        if (oldVersion < 8) {
          // Add lstm_training_snapshots table for LSTM model training data
          await db.execute('''
            CREATE TABLE IF NOT EXISTS lstm_training_snapshots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              daily_usage_hours REAL,
              most_unlock_count INTEGER,
              max_session_minutes REAL,
              current_session_minutes REAL,
              feature_vector TEXT,
              snapshot_type TEXT DEFAULT 'periodic'
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

    // ✅ Emergency unlock tracking
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

    // ✅ Violation logs for tracking limit violations
    await db.execute('''
      CREATE TABLE violation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        violation_type TEXT NOT NULL,
        app_name TEXT NOT NULL,
        app_package TEXT,
        daily_hours REAL,
        session_minutes REAL,
        unlock_count INTEGER,
        cooldown_seconds INTEGER
      )
    ''');

    // ✅ Session logs for tracking continuous usage sessions
    await db.execute('''
      CREATE TABLE session_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_start INTEGER NOT NULL,
        session_end INTEGER,
        duration_minutes REAL,
        ended_reason TEXT,
        apps_used TEXT
      )
    ''');

    // ✅ LSTM training snapshots for model training data collection
    await db.execute('''
      CREATE TABLE lstm_training_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        daily_usage_hours REAL,
        most_unlock_count INTEGER,
        max_session_minutes REAL,
        current_session_minutes REAL,
        feature_vector TEXT,
        snapshot_type TEXT DEFAULT 'periodic'
      )
    ''');
  }

  // ---------------- USER METHODS ----------------
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await instance.database;
    return await db.insert('users', user);
  }

  /// Get user by email and verify password (secure - compares hashes)
  Future<Map<String, dynamic>?> getUser(String email, String password) async {
    final db = await instance.database;
    
    // First get user by email to retrieve stored password hash
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    
    if (result.isEmpty) return null;
    
    final user = result.first;
    final storedPasswordHash = user['password'] as String?;
    
    if (storedPasswordHash == null) return null;
    
    // Verify password by comparing hashes
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

  /// Update user password (secure - stores hashed password)
  Future<bool> updateUserPassword(String email, String newPassword) async {
    try {
      final db = await instance.database;
      // Hash the new password before storing
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

  /// ✅ Save detailed per-app usage (ALL apps - selected + unselected)
  /// 
  /// This saves data for ALL apps to enable:
  /// - Week-long progress tracking
  /// - LSTM model training on complete user behavior patterns
  /// - Analytics and insights across all app usage
  /// 
  /// Note: Only selected apps count toward limits, but all apps are tracked for analysis
  Future<void> saveDetailedAppUsage({
    required String date,
    required Map<String, double> appUsage,
    required Map<String, int> appUnlocks,
    required Map<String, double> appLongestSessions,
  }) async {
    final db = await instance.database;

    // Restrict to selected apps ONLY
    await SelectedAppsManager.loadFromPrefs();
    final selectedPkgs = SelectedAppsManager.selectedApps
        .map((a) => (a['package'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toSet();

    // Delete old entries for this date
    await db.delete('app_details', where: 'date = ?', whereArgs: [date]);

    int saved = 0;
    for (var pkg in appUsage.keys) {
      if (!selectedPkgs.contains(pkg)) continue; // skip non-selected apps
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
      saved++;
    }

    print("💾 Saved ${saved} selected apps to database (non-selected apps ignored)");
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

    await SelectedAppsManager.loadFromPrefs();
    final pkgs = SelectedAppsManager.selectedApps
        .map((a) => (a['package'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toList();
    if (pkgs.isEmpty) return [];

    final placeholders = List.filled(pkgs.length, '?').join(',');
    final sql = '''
      SELECT * FROM app_details
      WHERE date = ? AND package_name IN ($placeholders)
      ORDER BY usage_seconds DESC
    ''';
    return await db.rawQuery(sql, [today, ...pkgs]);
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

    await SelectedAppsManager.loadFromPrefs();
    final pkgs = SelectedAppsManager.selectedApps
        .map((a) => (a['package'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toList();
    if (pkgs.isEmpty) return [];

    final placeholders = List.filled(pkgs.length, '?').join(',');
    final sql = '''
      SELECT 
        package_name,
        SUM(usage_seconds) as total_usage,
        SUM(unlock_count) as total_unlocks,
        MAX(longest_session_seconds) as max_session
      FROM app_details
      WHERE date >= ? AND date <= ? AND package_name IN ($placeholders)
      GROUP BY package_name
      ORDER BY total_usage DESC
      LIMIT ?
    ''';

    final results = await db.rawQuery(sql, [startDate, endDate, ...pkgs, limit]);
    return results;
  }

  /// ✅ Get top apps by unlock count for a date range
  Future<List<Map<String, dynamic>>> getTopAppsByUnlocks({
    required String startDate,
    required String endDate,
    int limit = 10,
  }) async {
    final db = await instance.database;

    await SelectedAppsManager.loadFromPrefs();
    final pkgs = SelectedAppsManager.selectedApps
        .map((a) => (a['package'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toList();
    if (pkgs.isEmpty) return [];

    final placeholders = List.filled(pkgs.length, '?').join(',');
    final sql = '''
      SELECT 
        package_name,
        SUM(usage_seconds) as total_usage,
        SUM(unlock_count) as total_unlocks,
        MAX(longest_session_seconds) as max_session
      FROM app_details
      WHERE date >= ? AND date <= ? AND package_name IN ($placeholders)
      GROUP BY package_name
      ORDER BY total_unlocks DESC
      LIMIT ?
    ''';

    final results = await db.rawQuery(sql, [startDate, endDate, ...pkgs, limit]);
    return results;
  }

  /// ✅ Get total usage for today
  Future<double> getTodayTotalUsage() async {
    final stats = await getTodayStats();
    if (stats == null) return 0.0;
    return (stats['daily_usage_hours'] as num? ?? 0.0).toDouble();
  }

  /// ✅ Get total usage for this week
  Future<double> getWeekTotalUsage() async {
    final weekStats = await getWeekStats();
    double total = 0.0;
    for (var stat in weekStats) {
      total += (stat['daily_usage_hours'] as num? ?? 0.0).toDouble();
    }
    return total;
  }

  /// ✅ Get last week's total usage for comparison
  Future<double> getLastWeekTotalUsage() async {
    final db = await instance.database;
    final today = DateTime.now();
    final lastWeekStart = today.subtract(const Duration(days: 14));
    final lastWeekEnd = today.subtract(const Duration(days: 8));
    final startStr = lastWeekStart.toIso8601String().substring(0, 10);
    final endStr = lastWeekEnd.toIso8601String().substring(0, 10);
    
    final results = await db.query(
      'usage_stats',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
    );
    
    double total = 0.0;
    for (var stat in results) {
      total += (stat['daily_usage_hours'] as num? ?? 0.0).toDouble();
    }
    return total;
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
    await SelectedAppsManager.loadFromPrefs();
    final pkgs = SelectedAppsManager.selectedApps
        .map((a) => (a['package'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toList();

    List<Map<String, dynamic>> appDetails = [];
    if (pkgs.isNotEmpty) {
      final placeholders = List.filled(pkgs.length, '?').join(',');
      final sql = '''
        SELECT * FROM app_details
        WHERE date = ? AND package_name IN ($placeholders)
        ORDER BY usage_seconds DESC
      ''';
      appDetails = await db.rawQuery(sql, [date, ...pkgs]);
    }

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

  // ---------------- EMERGENCY UNLOCK METHODS ----------------
  
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

  /// Get all emergency unlocks (for admin/viewing)
  Future<List<Map<String, dynamic>>> getAllEmergencyUnlocks() async {
    final db = await instance.database;
    return await db.query(
      'emergency_unlocks',
      orderBy: 'timestamp DESC',
    );
  }

  /// Get emergency unlocks with abuse penalties
  Future<List<Map<String, dynamic>>> getAbuseEmergencyUnlocks() async {
    final db = await instance.database;
    return await db.query(
      'emergency_unlocks',
      where: 'abuse_penalty_applied = ?',
      whereArgs: [1],
      orderBy: 'timestamp DESC',
    );
  }

  // ---------------- VIOLATION LOGGING METHODS ----------------
  
  /// Log a violation event
  Future<int> logViolation({
    required String violationType,
    required String appName,
    String? appPackage,
    double? dailyHours,
    double? sessionMinutes,
    int? unlockCount,
    int? cooldownSeconds,
  }) async {
    final db = await instance.database;
    return await db.insert(
      'violation_logs',
      {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'violation_type': violationType,
        'app_name': appName,
        'app_package': appPackage,
        'daily_hours': dailyHours,
        'session_minutes': sessionMinutes,
        'unlock_count': unlockCount,
        'cooldown_seconds': cooldownSeconds,
      },
    );
  }

  /// Get all violations for a date range
  Future<List<Map<String, dynamic>>> getViolations({
    String? startDate,
    String? endDate,
  }) async {
    final db = await instance.database;
    
    if (startDate != null && endDate != null) {
      // Convert date strings to timestamps
      final startTimestamp = DateTime.parse('${startDate}T00:00:00').millisecondsSinceEpoch;
      final endTimestamp = DateTime.parse('${endDate}T23:59:59').millisecondsSinceEpoch;
      
      return await db.query(
        'violation_logs',
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [startTimestamp, endTimestamp],
        orderBy: 'timestamp DESC',
      );
    }
    
    return await db.query(
      'violation_logs',
      orderBy: 'timestamp DESC',
    );
  }

  /// Get today's violations
  Future<List<Map<String, dynamic>>> getTodayViolations() async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
    
    return await getViolations(
      startDate: startOfDay.toIso8601String().substring(0, 10),
      endDate: endOfDay.toIso8601String().substring(0, 10),
    );
  }

  /// Get violations by type
  Future<List<Map<String, dynamic>>> getViolationsByType(String violationType) async {
    final db = await instance.database;
    return await db.query(
      'violation_logs',
      where: 'violation_type = ?',
      whereArgs: [violationType],
      orderBy: 'timestamp DESC',
    );
  }

  // ---------------- SESSION LOGGING METHODS ----------------
  
  /// Log a session start (when new session begins)
  Future<int> logSessionStart() async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert(
      'session_logs',
      {
        'session_start': now,
        'session_end': null,
        'duration_minutes': null,
        'ended_reason': null,
        'apps_used': null,
      },
    );
  }

  /// Log a session end (when session ends due to inactivity or violation)
  Future<void> logSessionEnd({
    required int sessionStart,
    required String reason, // 'inactivity', 'violation', 'cooldown', 'midnight'
    String? appsUsed,
  }) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final durationMinutes = (now - sessionStart) / 1000 / 60;

    // Find the session log entry with this start time and no end time
    final existingSessions = await db.query(
      'session_logs',
      where: 'session_start = ? AND session_end IS NULL',
      whereArgs: [sessionStart],
      limit: 1,
    );

    if (existingSessions.isNotEmpty) {
      // Update existing session
      await db.update(
        'session_logs',
        {
          'session_end': now,
          'duration_minutes': durationMinutes,
          'ended_reason': reason,
          'apps_used': appsUsed,
        },
        where: 'session_start = ?',
        whereArgs: [sessionStart],
      );
    } else {
      // Create new entry if somehow missing
      await db.insert(
        'session_logs',
        {
          'session_start': sessionStart,
          'session_end': now,
          'duration_minutes': durationMinutes,
          'ended_reason': reason,
          'apps_used': appsUsed,
        },
      );
    }
  }

  /// Get all session logs
  Future<List<Map<String, dynamic>>> getAllSessionLogs() async {
    final db = await instance.database;
    return await db.query(
      'session_logs',
      orderBy: 'session_start DESC',
    );
  }

  /// Save LSTM training snapshot
  Future<int> saveLSTMTrainingSnapshot({
    required double dailyUsageHours,
    required int mostUnlockCount,
    required double maxSessionMinutes,
    required double currentSessionMinutes,
    String? featureVector,
    String snapshotType = 'periodic',
  }) async {
    final db = await instance.database;
    return await db.insert(
      'lstm_training_snapshots',
      {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'daily_usage_hours': dailyUsageHours,
        'most_unlock_count': mostUnlockCount,
        'max_session_minutes': maxSessionMinutes,
        'current_session_minutes': currentSessionMinutes,
        'feature_vector': featureVector,
        'snapshot_type': snapshotType,
      },
    );
  }

  /// Get LSTM training snapshots for a date range
  Future<List<Map<String, dynamic>>> getLSTMTrainingSnapshots({
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
      'lstm_training_snapshots',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  /// Get today's session logs
  Future<List<Map<String, dynamic>>> getTodaySessionLogs() async {
    final db = await instance.database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final startTimestamp = startOfDay.millisecondsSinceEpoch;
    final endTimestamp = endOfDay.millisecondsSinceEpoch;
    
    return await db.query(
      'session_logs',
      where: 'session_start >= ? AND session_start < ?',
      whereArgs: [startTimestamp, endTimestamp],
      orderBy: 'session_start DESC',
    );
  }

  Future close() async {
    final db = _database;
    if (db != null) await db.close();
  }
}