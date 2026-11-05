package app.lyra.lyra

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 继承 AudioServiceActivity：让 MediaSession 在 Activity 生命周期外继续存活（后台播放 / 通知栏控制）
class MainActivity : AudioServiceActivity() {
    // lyra/power：电池优化豁免（后台播放保活）。锁屏/后台被杀的 OEM 管控没有统一 API，
    // 标准做法是请求 Doze 白名单（QQ/网易同款），剩下的由各 ROM 设置页引导。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lyra/power").setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryIgnored" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryIgnore" -> {
                    try {
                        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false) // 无该设置页的 ROM：走通用引导
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
