package com.tripcal.app

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** A single quiet ongoing notification; no foreground service or exact alarm. */
class DdayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { update(context) }
    companion object {
        private const val CHANNEL = "departure_countdown"
        private const val ID = 1801
        fun update(context: Context) {
            val prefs = context.getSharedPreferences("dday", Context.MODE_PRIVATE)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pending = PendingIntent.getBroadcast(context, ID, Intent(context, DdayReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarm.cancel(pending)
            if (!prefs.getBoolean("enabled", false)) { manager.cancel(ID); return }
            val today = LocalDate.now()
            val selected = prefs.getInt("selected", 0)
            val json = try { JSONArray(prefs.getString("trips", "[]")) } catch (_: Exception) { JSONArray() }
            var best: JSONObject? = null
            var bestDate: LocalDate? = null
            for (i in 0 until json.length()) {
                val trip = json.optJSONObject(i) ?: continue
                if (selected != 0 && trip.optInt("id") != selected) continue
                val date = try { LocalDate.parse(trip.optString("departure").take(10)) } catch (_: Exception) { continue }
                if (date.isBefore(today)) continue
                if (bestDate == null || date.isBefore(bestDate)) { best = trip; bestDate = date }
            }
            if (best == null || bestDate == null) { manager.cancel(ID); return }
            // Keep the next date update scheduled even when permission has been revoked.
            val tomorrow = today.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, tomorrow, pending)
            if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) { manager.cancel(ID); return }
            if (Build.VERSION.SDK_INT >= 26) {
                val channel = NotificationChannel(CHANNEL, "여행 출발일", NotificationManager.IMPORTANCE_LOW)
                channel.description = "선택한 여행의 D-day와 남은 준비물"
                channel.setSound(null, null)
                manager.createNotificationChannel(channel)
            }
            val days = ChronoUnit.DAYS.between(today, bestDate)
            val dday = if (days == 0L) "D-Day" else "D-$days"
            val open = Intent(context, MainActivity::class.java).putExtra("tripId", best.getInt("id")).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val content = PendingIntent.getActivity(context, ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val remaining = if (prefs.getBoolean("showRemaining", true)) " · 준비물 ${best.optInt("remaining")}개 남음" else ""
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("${best.optString("flag")} ${best.optString("name")} $dday")
                .setContentText("${bestDate.monthValue}월 ${bestDate.dayOfMonth}일 출발$remaining")
                .setContentIntent(content)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .build()
            manager.notify(ID, notification)
        }
    }
}
