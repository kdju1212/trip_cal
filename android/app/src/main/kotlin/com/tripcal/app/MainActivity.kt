package com.tripcal.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.tripcal.app/dday")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialTrip" -> {
                    val id = intent.getIntExtra("tripId", -1)
                    intent.removeExtra("tripId")
                    result.success(if (id >= 0) id else null)
                }
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) { result.success(false) }
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101) }
                    } else {
                        result.success(androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled())
                    }
                }
                "configure" -> {
                    val prefs = getSharedPreferences("dday", MODE_PRIVATE)
                    prefs.edit()
                        .putBoolean("enabled", call.argument<Boolean>("enabled") ?: false)
                        .putInt("selected", call.argument<Int>("selected") ?: 0)
                        .putBoolean("showRemaining", call.argument<Boolean>("showRemaining") ?: true)
                        .putBoolean("showName", call.argument<Boolean>("showName") ?: true)
                        .putBoolean("showDday", call.argument<Boolean>("showDday") ?: true)
                        .putString("customText", (call.argument<String>("customText") ?: "").take(80))
                        .putString("emoji", call.argument<String>("emoji") ?: "✈️")
                        .putString("trips", call.argument<String>("trips") ?: "[]")
                        .apply()
                    DdayReceiver.update(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val id = intent.getIntExtra("tripId", -1)
        if (id >= 0) {
            channel?.invokeMethod("openTrip", id)
            intent.removeExtra("tripId")
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}
