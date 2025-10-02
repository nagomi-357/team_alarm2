package nagomin.alarm1_2.team_alarm1_2

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "exact_alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                when (call.method) {
                    "canScheduleExactAlarms" -> {
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.canScheduleExactAlarms()
                        } else true
                        result.success(ok)
                    }
                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}


import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "exact_alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                when (call.method) {
                    "canScheduleExactAlarms" -> {
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.canScheduleExactAlarms()
                        } else true
                        result.success(ok)
                    }
                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
