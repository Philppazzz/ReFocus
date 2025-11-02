package com.example.refocus_app

import android.app.Activity
import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL_USAGE = "com.example.usage_stats/channel"
    private val CHANNEL_PERMISSION = "com.example.usage_stats/permission"
    private val CHANNEL_SOCIAL = "com.example.socialapps/channel"
    private val CHANNEL_MONITOR = "com.example.refocus/monitor"
    
    private val OVERLAY_PERMISSION_REQUEST = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
     * ✅ Get current foreground app using UsageEvents
     * This is more accurate than queryUsageStats for real-time detection
     */
    private fun getForegroundApp(): String? {
        try {
            if (!checkUsagePermission()) {
                Log.w("Monitor", "⚠️ Usage permission not granted")
                return null
            }

            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val endTime = System.currentTimeMillis()
            val startTime = endTime - 1000 * 10 // Last 10 seconds

            val events = usageStatsManager.queryEvents(startTime, endTime)
            var lastForegroundApp: String? = null
            var lastTimestamp: Long = 0

            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                
                // Event type 1 = MOVE_TO_FOREGROUND
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    if (event.timeStamp > lastTimestamp) {
                        lastForegroundApp = event.packageName
                        lastTimestamp = event.timeStamp
                    }
                }
            }

            // Fallback to ActivityManager for very recent apps
            if (lastForegroundApp == null) {
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val tasks = activityManager.runningAppProcesses
                if (tasks.isNotEmpty()) {
                    lastForegroundApp = tasks[0].processName
                }
            }

            Log.d("Monitor", "🔍 Foreground app: $lastForegroundApp")
            return lastForegroundApp

        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error getting foreground app: ${e.message}")
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
     * ✅ Bring app to foreground
     */
    private fun bringToForeground() {
        try {
            val intent = Intent(this, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(intent)
            Log.d("Monitor", "🔼 Bringing app to foreground")
        } catch (e: Exception) {
            Log.e("Monitor", "⚠️ Error bringing to foreground: ${e.message}")
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
}