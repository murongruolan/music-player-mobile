package app.lyra.lyra

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 继承 AudioServiceActivity：让 MediaSession 在 Activity 生命周期外继续存活（后台播放 / 通知栏控制）
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeBridge.attach(applicationContext, flutterEngine)
        // lyra/power：电池优化豁免（后台播放保活）。锁屏 / 后台被杀的 OEM 管控没有统一 API，
        // 标准做法是请求 Doze 白名单，剩下的由各 ROM 设置页引导。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lyra/power").setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryIgnored" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryIgnore" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false) // 没有这个设置页的 ROM
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

/// Dart ↔ 原生：桌面悬浮歌词、桌面图标（通道 lyra/native）。
/// 只用 applicationContext：Activity 被回收后（后台播放时常见）引擎还在，悬浮歌词照样能更新。
object NativeBridge {
    private var channel: MethodChannel? = null
    private var mcLock: android.net.wifi.WifiManager.MulticastLock? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(ctx: Context, engine: FlutterEngine) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "lyra/native")
        channel = ch
        FloatLyric.onEvent = { name, arg -> main.post { channel?.invokeMethod("float.$name", arg) } }
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "float.canDraw" -> result.success(FloatLyric.canDraw(ctx))
                    "float.request" -> {
                        FloatLyric.requestPermission(ctx)
                        result.success(null)
                    }
                    "float.style" -> {
                        FloatLyric.style(
                            call.argument<Double>("size"),
                            call.argument<Number>("color")?.toLong(),
                            call.argument<Double>("bg"),
                            call.argument<Boolean>("locked"),
                            call.argument<Int>("y"),
                        )
                        result.success(null)
                    }
                    "float.show" -> result.success(FloatLyric.show(ctx))
                    "float.hide" -> {
                        FloatLyric.hide()
                        result.success(null)
                    }
                    "float.update" -> {
                        FloatLyric.update(
                            call.argument<String>("text") ?: "",
                            call.argument<String>("next") ?: "",
                            call.argument<Double>("start") ?: 0.0,
                            call.argument<Double>("end") ?: 0.0,
                            call.argument<Double>("pos") ?: 0.0,
                            call.argument<Boolean>("playing") ?: false,
                            call.argument<Double>("speed") ?: 1.0,
                        )
                        result.success(null)
                    }
                    "net.multicast" -> {
                        // DLNA 发现（SSDP 组播）期间持有组播锁
                        val wifi = ctx.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                        if (call.arguments == true) {
                            if (mcLock == null) mcLock = wifi.createMulticastLock("lyra-dlna").apply { setReferenceCounted(false) }
                            mcLock?.acquire()
                        } else {
                            mcLock?.release()
                        }
                        result.success(null)
                    }
                    "icon.current" -> result.success(AppIcons.current(ctx))
                    "icon.set" -> result.success(AppIcons.set(ctx, call.argument<String>("id") ?: ""))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }
}
