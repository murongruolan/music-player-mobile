package app.lyra.lyra

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 继承 AudioServiceActivity：让 MediaSession 在 Activity 生命周期外继续存活（后台播放 / 通知栏控制）
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeBridge.attach(applicationContext, flutterEngine)
    }
}

/// Dart ↔ 原生：桌面悬浮歌词、桌面图标（通道 lyra/native）。
/// 只用 applicationContext：Activity 被回收后（后台播放时常见）引擎还在，悬浮歌词照样能更新。
object NativeBridge {
    private var channel: MethodChannel? = null
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
