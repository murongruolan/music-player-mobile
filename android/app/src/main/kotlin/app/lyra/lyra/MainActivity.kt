package app.lyra.lyra

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity

// 继承 AudioServiceActivity：让 MediaSession 在 Activity 生命周期外继续存活（后台播放 / 通知栏控制）
class MainActivity : AudioServiceActivity()
