package com.example.refocus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Broadcast receiver that listens for app install/uninstall events
 * Notifies Flutter app to update app categorization
 */
class AppInstallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AppInstallReceiver"
        private const val CHANNEL_NAME = "com.example.refocus/app_events"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_PACKAGE_ADDED -> {
                val packageName = intent.data?.schemeSpecificPart
                if (packageName != null && !intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) {
                    Log.d(TAG, "New app installed: $packageName")
                    handleAppInstalled(context, packageName)
                }
            }
            Intent.ACTION_PACKAGE_REMOVED -> {
                val packageName = intent.data?.schemeSpecificPart
                if (packageName != null && !intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) {
                    Log.d(TAG, "App uninstalled: $packageName")
                    handleAppUninstalled(context, packageName)
                }
            }
            Intent.ACTION_PACKAGE_REPLACED -> {
                val packageName = intent.data?.schemeSpecificPart
                if (packageName != null) {
                    Log.d(TAG, "App updated: $packageName")
                    handleAppUpdated(context, packageName)
                }
            }
        }
    }

    private fun handleAppInstalled(context: Context, packageName: String) {
        try {
            // Get app category immediately
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val appName = pm.getApplicationLabel(appInfo).toString()
            val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
            
            // ✅ CRITICAL: Verify if app is from Play Store
            val installerPackageName = pm.getInstallerPackageName(packageName)
            val playStoreInstaller = "com.android.vending"
            val isFromPlayStore = installerPackageName == playStoreInstaller
            
            // ✅ EXCLUDE: Non-Play Store apps (but keep system apps)
            if (!isFromPlayStore && !isSystemApp) {
                Log.d(TAG, "App installed but NOT from Play Store - skipping: $packageName")
                return  // Skip non-Play Store apps
            }

            val category = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
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

            Log.d(TAG, "App installed - Name: $appName, Category: $category, System: $isSystemApp, PlayStore: $isFromPlayStore")

            // Notify Flutter app via MethodChannel (if app is running)
            notifyFlutter(context, "appInstalled", mapOf(
                "packageName" to packageName,
                "appName" to appName,
                "category" to category,
                "isSystemApp" to isSystemApp,
                "isFromPlayStore" to isFromPlayStore  // ✅ New field
            ))

        } catch (e: Exception) {
            Log.e(TAG, "Error handling app install: ${e.message}")
        }
    }

    private fun handleAppUninstalled(context: Context, packageName: String) {
        Log.d(TAG, "App uninstalled: $packageName")

        // Notify Flutter app
        notifyFlutter(context, "appUninstalled", mapOf(
            "packageName" to packageName
        ))
    }

    private fun handleAppUpdated(context: Context, packageName: String) {
        Log.d(TAG, "App updated: $packageName")

        // Re-fetch category in case it changed
        handleAppInstalled(context, packageName)
    }

    /**
     * Notify Flutter app via MethodChannel
     * Note: This only works if the Flutter app is currently running
     */
    private fun notifyFlutter(context: Context, event: String, data: Map<String, Any>) {
        try {
            // In a production app, you might want to use a background service
            // or store the event in a database/SharedPreferences for Flutter to check later
            Log.d(TAG, "Event: $event, Data: $data")

            // For now, just log it. Flutter app will re-sync on next startup if needed
            // The actual syncing happens in AppCategorizationService.syncInstalledApps()

        } catch (e: Exception) {
            Log.e(TAG, "Error notifying Flutter: ${e.message}")
        }
    }
}
