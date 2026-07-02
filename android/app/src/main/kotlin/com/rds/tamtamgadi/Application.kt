package com.rds.tamtamgadi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import io.flutter.app.FlutterApplication

class Application : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannels()
        }
    }

    private fun createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ── Ride-request channel — custom request_sound.mp3 ─────────────────
        val rideSound: Uri = Uri.parse(
            "android.resource://$packageName/raw/request_sound"
        )
        val rideAudioAttrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val rideChannel = NotificationChannel(
            "chalchalgaadi_ride_v2",
            "Ride Requests",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts for new ride requests with custom sound"
            enableVibration(true)
            setSound(rideSound, rideAudioAttrs)
        }
        nm.createNotificationChannel(rideChannel)

        // ── General channel — system default sound ───────────────────────────
        val defaultChannel = NotificationChannel(
            "chalchalgaadi_high",
            "General Alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "General app notifications"
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
        nm.createNotificationChannel(defaultChannel)
    }
}
