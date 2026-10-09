package com.niooo.m.flutter_live_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.niooo.m/player"
    private val DOWNLOAD_CHANNEL_ID = "niooo_m_downloads_channel"

    companion object {
        init {
            try {
                System.loadLibrary("niooom_native_engine")
            } catch (_: Throwable) {
            }
        }
    }

    private external fun initNativeCppEngine(): String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            initNativeCppEngine()
        } catch (_: Throwable) {
        }
        createDownloadNotificationChannel()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                window.attributes.preferredDisplayModeId = 0
            } catch (_: Throwable) {
            }
        }
    }

    private fun createDownloadNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                DOWNLOAD_CHANNEL_ID,
                "Niooo M Offline Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Real-time movie download progress and offline completion notifications"
                setShowBadge(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun showSystemDownloadNotification(
        notificationId: Int,
        title: String,
        body: String,
        progress: Int,
        isOngoing: Boolean
    ) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, notificationId, intent, pendingFlags)

            val iconRes = if (isOngoing) {
                android.R.drawable.stat_sys_download
            } else {
                android.R.drawable.stat_sys_download_done
            }

            val builder = NotificationCompat.Builder(this, DOWNLOAD_CHANNEL_ID)
                .setSmallIcon(iconRes)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(pendingIntent)
                .setOnlyAlertOnce(true)
                .setOngoing(isOngoing)
                .setAutoCancel(!isOngoing)
                .setPriority(NotificationCompat.PRIORITY_LOW)

            if (isOngoing) {
                builder.setProgress(100, progress.coerceIn(0, 100), false)
            } else {
                builder.setProgress(0, 0, false)
            }

            manager.notify(notificationId, builder.build())
        } catch (_: Throwable) {
        }
    }

    private fun cancelSystemDownloadNotification(notificationId: Int) {
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId)
        } catch (_: Throwable) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterFullscreen" -> {
                        runOnUiThread {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                            hideSystemUI()
                        }
                        result.success(true)
                    }
                    "exitFullscreen" -> {
                        runOnUiThread {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
                            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                            showSystemUI()
                        }
                        result.success(true)
                    }
                    "setKeepScreenOn" -> {
                        val enable = call.argument<Boolean>("enable") ?: true
                        runOnUiThread {
                            if (enable) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    "boostPlayback" -> {
                        try {
                            val status = initNativeCppEngine()
                            result.success(status)
                        } catch (_: Throwable) {
                            result.success("Fallback Mode")
                        }
                    }
                    "showDownloadNotification" -> {
                        val id = call.argument<Int>("id") ?: 1001
                        val title = call.argument<String>("title") ?: "Niooo M Download"
                        val body = call.argument<String>("body") ?: "Downloading..."
                        val progress = call.argument<Int>("progress") ?: 0
                        val ongoing = call.argument<Boolean>("ongoing") ?: true
                        runOnUiThread {
                            showSystemDownloadNotification(id, title, body, progress, ongoing)
                        }
                        result.success(true)
                    }
                    "cancelDownloadNotification" -> {
                        val id = call.argument<Int>("id") ?: 1001
                        runOnUiThread {
                            cancelSystemDownloadNotification(id)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
            )
        }
    }

    private fun showSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.show(
                WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars()
            )
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}
