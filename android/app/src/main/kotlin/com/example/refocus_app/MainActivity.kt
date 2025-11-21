package com.example.refocus_app

import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL_USAGE = "com.example.usage_stats/channel"
    private val CHANNEL_PERMISSION = "com.example.usage_stats/permission"
    private val CHANNEL_SOCIAL = "com.example.socialapps/channel"
    private val CHANNEL_MONITOR = "com.example.refocus/monitor"
    private val CHANNEL_CATEGORIZATION = "com.example.refocus/categorization"
    private val CHANNEL_APP_NAMES = "com.example.refocus/app_names"

    private val OVERLAY_PERMISSION_REQUEST = 1001
    private val LOCK_NOTIFICATION_CHANNEL_ID = "lock_screen_channel"
    private val LOCK_NOTIFICATION_ID = 999

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ✅ Android compatibility setup
        createNotificationChannel()
        requestRequiredPermissions()

        // ✅ Social apps detection
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SOCIAL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSocialApps") {
                    result.success(getInstalledSocialApps())
                } else result.notImplemented()
            }

        // ✅ Permission channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PERMISSION)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestPermission") {
                    val granted = checkUsagePermission()
                    if (!granted) {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                    result.success(granted)
                } else result.notImplemented()
            }

        // ✅ Usage stats channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_USAGE)
            .setMethodCallHandler { call, result ->
                if (call.method == "getUsageStats") {
                    val packages = call.argument<List<String>>("packages")
                    result.success(getUsageStats(packages))
                } else result.notImplemented()
            }

        // ✅ Categorization channel for app categorization
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CATEGORIZATION)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAllInstalledApps" -> {
                        result.success(getAllInstalledAppsWithCategories())
                    }
                    "getAppInfo" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            result.success(getAppInfo(packageName))
                        } else {
                            result.error("INVALID_ARG", "Package name required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ✅ Monitor channel for foreground app detection
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MONITOR)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestOverlayPermission" -> {
                        requestOverlayPermission()
                        result.success(null)
                    }
                    "getForegroundApp" -> {
                        result.success(getForegroundApp())
                    }
                    "bringToForeground" -> {
                        bringToForeground()
                        result.success(null)
                    }
                    "hasOverlayPermission" -> {
                        result.success(hasOverlayPermission())
                    }
                    "checkOverlayPermission" -> {
                        // Alias for hasOverlayPermission for consistency
                        result.success(hasOverlayPermission())
                    }
                    "forceCloseApp" -> {
                        val packageName = call.argument<String>("package")
                        if (packageName != null) {
                            forceCloseApp(packageName)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARG", "Package name required", null)
                        }
                    }
                    "hasNotificationPermission" -> {
                        result.success(hasNotificationPermission())
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ✅ App Names channel for fetching real app labels
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_APP_NAMES)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppLabel" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName != null) {
                            result.success(getAppLabel(packageName))
                        } else {
                            result.error("INVALID_ARG", "Package name required", null)
                        }
                    }
                    "getAppLabels" -> {
                        val packageNames = call.argument<List<String>>("packageNames")
                        if (packageNames != null) {
                            result.success(getAppLabels(packageNames))
                        } else {
                            result.error("INVALID_ARG", "Package names required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun checkUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            "android:get_usage_stats",
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getUsageStats(packages: List<String>?): List<Map<String, Any>> {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val endTime = System.currentTimeMillis()
        val startTime = endTime - 1000L * 60 * 60 * 24 // 24 hours

        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        if (stats.isNullOrEmpty()) {
            Log.w("UsageStats", "⚠️ No data returned — permission or no activity")
            return emptyList()
        }

        val usageData = stats.filter {
            packages?.contains(it.packageName) == true
        }.map {
            val foreground =
                if (it.totalTimeInForeground > 0) it.totalTimeInForeground
                else if (Build.VERSION.SDK_INT >= 29)
                    it.totalTimeVisible.takeIf { v -> v > 0 } ?: 0
                else 0
            mapOf(
                "packageName" to it.packageName,
                "totalTimeForeground" to foreground
            )
        }

        Log.i("UsageStats", "✅ Filtered usage data: $usageData")
        return usageData
    }

    private fun getInstalledSocialApps(): List<Map<String, String>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val knownSocialApps = mapOf(
            "com.facebook.katana" to "Facebook",
            "com.facebook.lite" to "Facebook Lite",
            "com.facebook.orca" to "Messenger",
            "com.instagram.android" to "Instagram",
            "com.twitter.android" to "X (Twitter)",
            "com.snapchat.android" to "Snapchat",
            "com.tiktok.android" to "TikTok",
            "com.zhiliaoapp.musically" to "TikTok",
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "org.telegram.messenger" to "Telegram",
            "com.discord" to "Discord",
            "com.reddit.frontpage" to "Reddit",
            "com.viber.voip" to "Viber",
            "com.google.android.youtube" to "YouTube",
            "com.google.android.apps.youtube.music" to "YouTube Music",
            "com.linkedin.android" to "LinkedIn",
            "com.bereal.ft" to "BeReal",
            "com.pinterest" to "Pinterest",
            "com.tumblr" to "Tumblr",
            "com.clubhouse.app" to "Clubhouse",
            "com.instagram.barcelona" to "Threads"
        )

        val detected = apps.mapNotNull { app ->
            knownSocialApps[app.packageName]?.let { name ->
                mapOf("name" to name, "package" to app.packageName)
            }
        }
        Log.d("SocialDetector", "✅ Detected apps: $detected")
        return detected
    }

    /**
     * ✅ Get current foreground app - ANDROID 11+ COMPATIBLE
     * Uses queryUsageStats with INTERVAL_BEST to find the most recently used app
     * This works even when the app is actively being used (no new events)
     */
    private fun getForegroundApp(): String? {
        try {
            if (!checkUsagePermission()) {
                Log.w("Monitor", "⚠️ Usage permission not granted")
                return null
            }

            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 * 3 // Last 3 seconds (very recent)

            // Method 1: Try UsageEvents first (for app switches)
            val events = usageStatsManager.queryEvents(startTime, endTime)
            var lastForegroundApp: String? = null
            var lastEventTimestamp: Long = 0

            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                
                // Event type 1 = MOVE_TO_FOREGROUND
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    if (event.timeStamp > lastEventTimestamp) {
                        lastForegroundApp = event.packageName
                        lastEventTimestamp = event.timeStamp
                    }
                }
            }

            // Method 2: Use queryUsageStats to find the app with most recent lastTimeUsed
            // This is MORE RELIABLE for detecting the CURRENTLY ACTIVE app (even without new events)
            if (lastForegroundApp == null || lastEventTimestamp < endTime - 2000) {
                // No recent events OR event is old - check which app is actually being used NOW
                val stats = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    usageStatsManager.queryUsageStats(
                        UsageStatsManager.INTERVAL_BEST,
                        endTime - 1000 * 60, // Last 1 minute
                        endTime
                    )
                } else {
                    usageStatsManager.queryUsageStats(
                        UsageStatsManager.INTERVAL_DAILY,
                        endTime - 1000 * 60,
                        endTime
                    )
                }

                var mostRecentApp: String? = null
                var mostRecentTime: Long = 0

                stats?.forEach { usageStat ->
                    val lastUsed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        usageStat.lastTimeUsed
                    } else {
                        usageStat.lastTimeStamp
                    }
                    
                    if (lastUsed > mostRecentTime) {
                        mostRecentTime = lastUsed
                        mostRecentApp = usageStat.packageName
                    }
                }

                // Use the most recently used app if it's more recent than the event
                if (mostRecentApp != null && mostRecentTime > lastEventTimestamp) {
                    lastForegroundApp = mostRecentApp
                    Log.d("Monitor", "🔍 Using queryUsageStats method (lastTimeUsed: ${System.currentTimeMillis() - mostRecentTime}ms ago)")
                }
            } else {
                Log.d("Monitor", "🔍 Using UsageEvents method (event: ${System.currentTimeMillis() - lastEventTimestamp}ms ago)")
            }

            // Method 3: Fallback to ActivityManager (least reliable but better than nothing)
            if (lastForegroundApp == null) {
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val tasks = activityManager.appTasks
                    if (tasks.isNotEmpty()) {
                        val topTask = tasks[0]
                        lastForegroundApp = topTask.taskInfo?.baseIntent?.component?.packageName
                        Log.d("Monitor", "🔍 Using AppTasks fallback")
                    }
                }
            }

            Log.d("Monitor", "🔍 Foreground app: $lastForegroundApp")
            return lastForegroundApp

        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error getting foreground app: ${e.message}")
            e.printStackTrace()
            return null
        }
    }

    /**
     * ✅ Request overlay permission (to draw over other apps)
     */
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
                Log.d("Monitor", "📋 Requesting overlay permission")
            } else {
                Log.d("Monitor", "✅ Overlay permission already granted")
            }
        }
    }

    /**
     * ✅ Check if overlay permission is granted
     */
    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    /**
     * Check if notification permission is granted (Android 13+)
     */
    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Permission not required on older Android versions
        }
    }

    /**
     * Request notification permission (Android 13+)
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33) {
            if (!hasNotificationPermission()) {
                requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    1002
                )
                Log.d("Monitor", "📋 Requesting POST_NOTIFICATIONS permission (Android 13+)")
            } else {
                Log.d("Monitor", "✅ POST_NOTIFICATIONS permission already granted")
            }
        }
    }

    /**
     * Open app settings
     */
    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Log.d("Monitor", "📋 Opening app settings")
        } catch (e: Exception) {
            Log.w("Monitor", "⚠️ Error opening app settings: ${e.message}")
        }
    }

    /**
     * Create notification channel for full-screen intents (Android 8.0+)
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Lock Screen Notifications"
            val descriptionText = "Shows lock screen when usage limits are exceeded"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(LOCK_NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableLights(true)
                lightColor = Color.RED
                enableVibration(true)
                setBypassDnd(true)
            }
            
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("Monitor", "✅ Notification channel created for full-screen intents")
        }
    }

    /**
     * ✅ Bring app to foreground - ANDROID 11+ COMPATIBLE
     * Uses overlay activity for Android 11+ (API 30+) - the ONLY reliable method
     * Falls back to direct intent for older versions
     */
    private fun bringToForeground() {
        try {
            Log.d("Monitor", "🔼🔼🔼 BRINGING APP TO FOREGROUND (Android ${Build.VERSION.SDK_INT})")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Android 11+ (API 30+): Use overlay activity that shows on top of all apps
                // This is the MOST RELIABLE way to show lock screen on Android 11+
                
                // Check if we have overlay permission
                if (!hasOverlayPermission()) {
                    Log.w("Monitor", "⚠️ Overlay permission not granted - requesting now...")
                    requestOverlayPermission()
                    // Also try notification fallback
                    showFullScreenNotification()
                    return
                }
                
                // Launch overlay activity - this will show ON TOP of Facebook/any app
                val overlayIntent = Intent(this, LockScreenOverlayActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
                }
                startActivity(overlayIntent)
                Log.d("Monitor", "🔒 Overlay activity launched (Android 11+ method) - should show ON TOP of current app")
                
            } else {
                // Android 10 and below: Use direct intent (still works)
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                startActivity(intent)
                Log.d("Monitor", "🔼 Direct intent used (Android < 11)")
                
                // Also try moveTaskToFront on Android 10 and below
                try {
                    val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    activityManager.moveTaskToFront(taskId, ActivityManager.MOVE_TASK_WITH_HOME)
                    Log.d("Monitor", "🔼 MoveTaskToFront called")
                } catch (e: Exception) {
                    Log.w("Monitor", "⚠️ moveTaskToFront failed: ${e.message}")
                }
            }
            
        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error bringing to foreground: ${e.message}")
            // Final fallback: show notification
            try {
                showFullScreenNotification()
            } catch (e2: Exception) {
                Log.e("Monitor", "⚠️ Notification fallback also failed: ${e2.message}")
            }
        }
    }
    
    /**
     * Show full-screen intent notification (works on Android 11+)
     * This launches the app as a full-screen "alarm" style notification
     */
    private fun showFullScreenNotification() {
        try {
            // Check if we have full-screen intent permission (Android 12+)
            if (Build.VERSION.SDK_INT >= 34) { // API 34 = Android 14
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (!notificationManager.canUseFullScreenIntent()) {
                    Log.w("Monitor", "⚠️ Full-screen intent permission not granted - requesting...")
                    // Request permission
                    val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    intent.data = Uri.parse("package:$packageName")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    return
                }
            }
            
            // Create intent for the lock screen
            val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY)
                addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                putExtra("show_lock_screen", true) // Signal to show lock screen
            }
            
            val fullScreenPendingIntent = PendingIntent.getActivity(
                this,
                0,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Build notification with full-screen intent - VERY AGGRESSIVE
            val notificationBuilder = NotificationCompat.Builder(this, LOCK_NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setContentTitle("🔒 LOCKED - Limit Reached")
                .setContentText("Tap to return to ReFocus")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false) // Don't auto-cancel
                .setOngoing(true) // Make it persistent
                .setFullScreenIntent(fullScreenPendingIntent, true) // KEY: This shows full-screen on Android 11+
                .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
                .setSound(android.provider.Settings.System.DEFAULT_NOTIFICATION_URI)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setContentIntent(fullScreenPendingIntent) // Also set as content intent
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Cancel any existing notification first
            notificationManager.cancel(LOCK_NOTIFICATION_ID)
            
            // Post new notification
            notificationManager.notify(LOCK_NOTIFICATION_ID, notificationBuilder.build())
            
            Log.d("Monitor", "🔔 Full-screen notification posted (Android 11+ method)")
            
            // ADDITIONAL: Try to directly start the activity as a fallback
            try {
                fullScreenIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(fullScreenIntent)
                Log.d("Monitor", "🚀 Also started activity directly as fallback")
            } catch (e2: Exception) {
                Log.w("Monitor", "⚠️ Could not start activity directly: ${e2.message}")
            }
            
        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error showing full-screen notification: ${e.message}")
        }
    }

    /**
     * ✅ Force close/kill an app (for aggressive blocking)
     * Uses ActivityManager to kill the app's tasks
     */
    private fun forceCloseApp(packageName: String) {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            
            // Method 1: Kill all tasks for this package
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                activityManager.appTasks.forEach { task ->
                    task.taskInfo?.let { taskInfo ->
                        if (taskInfo.baseIntent.component?.packageName == packageName) {
                            task.finishAndRemoveTask()
                            Log.d("Monitor", "💀 Killed task for $packageName")
                        }
                    }
                }
            }
            
            // Method 2: Try to kill background processes (more aggressive)
            try {
                val processes = activityManager.runningAppProcesses
                processes?.forEach { processInfo ->
                    if (processInfo.pkgList.contains(packageName)) {
                        android.os.Process.killProcess(processInfo.pid)
                        Log.d("Monitor", "💀 Killed process ${processInfo.pid} for $packageName")
                    }
                }
            } catch (e: Exception) {
                Log.w("Monitor", "⚠️ Could not kill process: ${e.message}")
            }
            
            // Method 3: Use killBackgroundProcesses (requires permission)
            try {
                activityManager.killBackgroundProcesses(packageName)
                Log.d("Monitor", "💀 Killed background processes for $packageName")
            } catch (e: Exception) {
                Log.w("Monitor", "⚠️ Could not kill background processes: ${e.message}")
            }
            
        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error force closing app: ${e.message}")
        }
    }

    /**
     * ✅ Get all installed apps with Play Store verification
     * Returns list of maps containing: packageName, appName, category, isSystemApp, isFromPlayStore
     * ✅ CRITICAL: Only includes apps from Play Store (verified) or system apps
     * ✅ EXCLUDES: Pirated/unverified apps (not from Play Store)
     */
    private fun getAllInstalledAppsWithCategories(): List<Map<String, Any>> {
        try {
            val pm = packageManager
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            val playStoreInstaller = "com.android.vending" // Google Play Store package name

            return apps.mapNotNull { appInfo ->
                try {
                    val packageName = appInfo.packageName
                    val appName = pm.getApplicationLabel(appInfo).toString()
                    val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    
                    // ✅ CRITICAL: Verify if app is from Play Store
                    val installerPackageName = pm.getInstallerPackageName(packageName)
                    val isFromPlayStore = installerPackageName == playStoreInstaller
                    
                    // ✅ EXCLUDE: Non-Play Store apps (pirated/unverified) - but keep system apps
                    if (!isFromPlayStore && !isSystemApp) {
                        // Skip this app - it's not from Play Store and not a system app
                        return@mapNotNull null
                    }

                    // Get Play Store category (API 26+)
                    val category = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        when (appInfo.category) {
                            android.content.pm.ApplicationInfo.CATEGORY_GAME -> "GAME"
                            android.content.pm.ApplicationInfo.CATEGORY_AUDIO -> "MUSIC_AND_AUDIO"
                            android.content.pm.ApplicationInfo.CATEGORY_VIDEO -> "VIDEO_PLAYERS"
                            android.content.pm.ApplicationInfo.CATEGORY_IMAGE -> "PHOTOGRAPHY"
                            android.content.pm.ApplicationInfo.CATEGORY_SOCIAL -> "SOCIAL"
                            android.content.pm.ApplicationInfo.CATEGORY_NEWS -> "NEWS_AND_MAGAZINES"
                            android.content.pm.ApplicationInfo.CATEGORY_MAPS -> "MAPS_AND_NAVIGATION"
                            android.content.pm.ApplicationInfo.CATEGORY_PRODUCTIVITY -> "PRODUCTIVITY"
                            else -> "UNDEFINED"
                        }
                    } else {
                        "UNDEFINED"
                    }

                    mapOf(
                        "packageName" to packageName,
                        "appName" to appName,
                        "category" to category,
                        "isSystemApp" to isSystemApp,
                        "isFromPlayStore" to isFromPlayStore  // ✅ New field
                    )
                } catch (e: Exception) {
                    Log.w("Categorization", "⚠️ Error processing app ${appInfo.packageName}: ${e.message}")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e("Categorization", "⚠️ Error getting installed apps: ${e.message}")
            return emptyList()
        }
    }

    /**
     * ✅ Get info for a specific app package with Play Store verification
     * Returns map containing: packageName, appName, category, isSystemApp, isFromPlayStore, or null if not found
     * ✅ CRITICAL: Returns null for non-Play Store apps (unless it's a system app)
     */
    private fun getAppInfo(packageName: String): Map<String, Any>? {
        try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            val appName = pm.getApplicationLabel(appInfo).toString()
            val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
            
            // ✅ CRITICAL: Verify if app is from Play Store
            val installerPackageName = pm.getInstallerPackageName(packageName)
            val playStoreInstaller = "com.android.vending"
            val isFromPlayStore = installerPackageName == playStoreInstaller
            
            // ✅ EXCLUDE: Non-Play Store apps (but keep system apps)
            if (!isFromPlayStore && !isSystemApp) {
                return null  // Skip non-Play Store apps
            }

            // Get Play Store category (API 26+)
            val category = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                when (appInfo.category) {
                    android.content.pm.ApplicationInfo.CATEGORY_GAME -> "GAME"
                    android.content.pm.ApplicationInfo.CATEGORY_AUDIO -> "MUSIC_AND_AUDIO"
                    android.content.pm.ApplicationInfo.CATEGORY_VIDEO -> "VIDEO_PLAYERS"
                    android.content.pm.ApplicationInfo.CATEGORY_IMAGE -> "PHOTOGRAPHY"
                    android.content.pm.ApplicationInfo.CATEGORY_SOCIAL -> "SOCIAL"
                    android.content.pm.ApplicationInfo.CATEGORY_NEWS -> "NEWS_AND_MAGAZINES"
                    android.content.pm.ApplicationInfo.CATEGORY_MAPS -> "MAPS_AND_NAVIGATION"
                    android.content.pm.ApplicationInfo.CATEGORY_PRODUCTIVITY -> "PRODUCTIVITY"
                    else -> "UNDEFINED"
                }
            } else {
                "UNDEFINED"
            }

            return mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "category" to category,
                "isSystemApp" to isSystemApp,
                "isFromPlayStore" to isFromPlayStore  // ✅ New field
            )
        } catch (e: Exception) {
            Log.e("Categorization", "⚠️ Error getting app info for $packageName: ${e.message}")
            return null
        }
    }

    /**
     * ✅ Request required runtime permissions for different Android versions
     * - Android 13+ (API 33): POST_NOTIFICATIONS
     * - Android 14+ (API 34): USE_FULL_SCREEN_INTENT
     */
    private fun requestRequiredPermissions() {
        try {
            // Android 13+ (API 33): Request POST_NOTIFICATIONS permission
            if (Build.VERSION.SDK_INT >= 33) {
                if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) 
                    != PackageManager.PERMISSION_GRANTED) {
                    Log.d("Monitor", "📋 Requesting POST_NOTIFICATIONS permission (Android 13+)")
                    requestPermissions(
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                        1002
                    )
                } else {
                    Log.d("Monitor", "✅ POST_NOTIFICATIONS permission already granted")
                }
            }
            
            // Android 14+ (API 34): Check and request full-screen intent permission
            if (Build.VERSION.SDK_INT >= 34) {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (!notificationManager.canUseFullScreenIntent()) {
                    Log.d("Monitor", "📋 Full-screen intent permission needed (Android 14+)")
                    // Note: This requires user to manually grant permission in settings
                    // The actual request is done in showFullScreenNotification() when needed
                } else {
                    Log.d("Monitor", "✅ Full-screen intent permission already granted")
                }
            }
            
        } catch (e: Exception) {
            Log.w("Monitor", "⚠️ Error requesting permissions: ${e.message}")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            1002 -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d("Monitor", "✅ POST_NOTIFICATIONS permission granted")
                } else {
                    Log.w("Monitor", "⚠️ POST_NOTIFICATIONS permission denied")
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == OVERLAY_PERMISSION_REQUEST) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (Settings.canDrawOverlays(this)) {
                    Log.d("Monitor", "✅ Overlay permission granted")
                } else {
                    Log.w("Monitor", "⚠️ Overlay permission denied")
                }
            }
        }
    }

    /**
     * ✅ Get real app label (human-readable name) for a package
     * Returns the app name shown to users, not the package name
     * Example: com.facebook.katana → "Facebook"
     */
    private fun getAppLabel(packageName: String): String? {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            Log.w("AppNames", "⚠️ Could not get label for $packageName: ${e.message}")
            null
        }
    }

    /**
     * ✅ Get real app labels for multiple packages (batch operation)
     * More efficient than calling getAppLabel multiple times
     * Returns map of packageName → appLabel
     */
    private fun getAppLabels(packageNames: List<String>): Map<String, String> {
        val results = mutableMapOf<String, String>()
        val pm = packageManager

        for (packageName in packageNames) {
            try {
                val appInfo = pm.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                val appLabel = pm.getApplicationLabel(appInfo).toString()
                results[packageName] = appLabel
            } catch (e: Exception) {
                Log.w("AppNames", "⚠️ Could not get label for $packageName: ${e.message}")
                // Don't include in results - Flutter side will use package name as fallback
            }
        }

        Log.d("AppNames", "✅ Fetched ${results.size} app labels out of ${packageNames.size} requests")
        return results
    }
}