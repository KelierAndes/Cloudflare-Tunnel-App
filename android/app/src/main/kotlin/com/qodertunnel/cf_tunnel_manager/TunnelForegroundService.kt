package com.qodertunnel.cf_tunnel_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 只要有一条隧道在跑就保持前台服务，避免 Android 在应用切到后台后回收 cloudflared。
 */
class TunnelForegroundService : Service() {
    companion object {
        const val ACTION_START = "com.qodertunnel.cf_tunnel_manager.action.START_TUNNEL"
        const val ACTION_STOP = "com.qodertunnel.cf_tunnel_manager.action.STOP_TUNNEL"
        private const val CHANNEL_ID = "cf_tunnel_runtime"
        private const val NOTIFICATION_ID = 4711
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "隧道连接",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持 Cloudflare Tunnel 后台连接"
                setShowBadge(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Cloudflare Tunnel")
            .setContentText("隧道正在保持连接")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
    }
}
