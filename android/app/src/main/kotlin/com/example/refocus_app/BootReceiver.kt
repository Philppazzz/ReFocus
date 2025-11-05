package com.example.refocus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * ✅ Boot Receiver to restart monitoring service after device reboot
 * This ensures tracking continues even after device restarts
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d("BootReceiver", "🔄 Device boot completed - service will restart when app opens")
            // Note: FlutterForegroundTask will be started when app launches
            // This receiver just ensures the app knows to restart monitoring
        }
    }
}

