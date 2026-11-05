package app.lyra.lyra

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/// 桌面悬浮歌词：系统悬浮窗（TYPE_APPLICATION_OVERLAY）里两行歌词——当前句（逐句卡拉 OK 染色）+ 下一句 / 翻译。
/// Dart 只在换句 / 暂停 / 拖动进度时推一次（句子起止时间 + 当前进度），染色进度在这里按时钟自己算，不用每帧过通道。
/// 未锁定：上下拖动换位置，点一下出现工具条（锁定 / 字号 / 关闭）；锁定后点击穿透，在 App 设置里解锁。
object FloatLyric {
    /// 事件回 Dart：moved(y) / locked(bool) / closed / size(sp)
    var onEvent: ((String, Any?) -> Unit)? = null

    private var wm: WindowManager? = null
    private var root: LinearLayout? = null
    private var line: KaraokeView? = null
    private var sub: TextView? = null
    private var bar: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null

    private var fontSp = 18f
    private var played = 0xFFF4D28A.toInt()
    private var bgAlpha = 0.45f
    private var locked = false
    private var posY = -1

    fun canDraw(ctx: Context): Boolean = Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(ctx)

    /// 打开系统的「显示在其他应用上层」授权页（用户授权后回到 App 再开开关）。
    fun requestPermission(ctx: Context) {
        val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            ctx.startActivity(i)
        } catch (_: Exception) {
            ctx.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    val showing: Boolean get() = root != null

    fun style(fontSp: Double?, color: Long?, bgAlpha: Double?, locked: Boolean?, y: Int?) {
        fontSp?.let { this.fontSp = it.toFloat().coerceIn(12f, 36f) }
        color?.let { played = it.toInt() }
        bgAlpha?.let { this.bgAlpha = it.toFloat().coerceIn(0f, 1f) }
        locked?.let { this.locked = it }
        y?.let { posY = it }
        applyStyle()
    }

    fun show(ctx: Context): Boolean {
        if (root != null) return true
        if (!canDraw(ctx)) return false
        val app = ctx.applicationContext
        val w = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = app.resources.displayMetrics.density
        val box = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((16 * dp).toInt(), (10 * dp).toInt(), (16 * dp).toInt(), (10 * dp).toInt())
        }
        val k = KaraokeView(app)
        val s = TextView(app).apply {
            setTextColor(0xCCFFFFFF.toInt())
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setShadowLayer(4 * dp, 0f, dp, 0x99000000.toInt())
        }
        val tools = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(0, (8 * dp).toInt(), 0, 0)
        }
        fun tool(label: String, onTap: () -> Unit) = TextView(app).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding((14 * dp).toInt(), (6 * dp).toInt(), (14 * dp).toInt(), (6 * dp).toInt())
            background = GradientDrawable().apply { cornerRadius = 14 * dp; setColor(0x33FFFFFF) }
            setOnClickListener { onTap() }
            val lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lp.marginStart = (5 * dp).toInt(); lp.marginEnd = (5 * dp).toInt()
            layoutParams = lp
        }
        tools.addView(tool("锁定") {
            locked = true
            tools.visibility = View.GONE
            applyStyle()
            onEvent?.invoke("locked", true)
        })
        tools.addView(tool("A-") { fontSp = max(12f, fontSp - 2); applyStyle(); onEvent?.invoke("size", fontSp.toDouble()) })
        tools.addView(tool("A+") { fontSp = min(36f, fontSp + 2); applyStyle(); onEvent?.invoke("size", fontSp.toDouble()) })
        tools.addView(tool("关闭") { hide(); onEvent?.invoke("closed", null) })
        box.addView(k, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        box.addView(s, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        box.addView(tools, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = if (posY >= 0) posY else (app.resources.displayMetrics.heightPixels * 0.18).toInt()
        }
        attachTouch(box, tools, p, w)
        wm = w; root = box; line = k; sub = s; bar = tools; params = p
        applyStyle()
        return try {
            w.addView(box, p)
            true
        } catch (e: Exception) {
            root = null
            false
        }
    }

    fun hide() {
        val r = root ?: return
        try {
            wm?.removeView(r)
        } catch (_: Exception) {
        }
        root = null; line = null; sub = null; bar = null
    }

    /// 换句 / 暂停 / 拖进度时调用。时间单位：秒。
    fun update(text: String, next: String, start: Double, end: Double, pos: Double, playing: Boolean, speed: Double) {
        line?.setLine(text, start, end, pos, playing, speed)
        sub?.apply {
            this.text = next
            visibility = if (next.isEmpty()) View.GONE else View.VISIBLE
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouch(box: View, tools: View, p: WindowManager.LayoutParams, w: WindowManager) {
        val slop = ViewConfiguration.get(box.context).scaledTouchSlop
        var downY = 0f
        var startY = 0
        var moved = false
        box.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = e.rawY; startY = p.y; moved = false; true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = e.rawY - downY
                    if (abs(dy) > slop) moved = true
                    if (moved) {
                        p.y = max(0, startY + dy.toInt())
                        try { w.updateViewLayout(box, p) } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        posY = p.y
                        onEvent?.invoke("moved", p.y)
                    } else {
                        tools.visibility = if (tools.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun applyStyle() {
        val box = root ?: return
        val dp = box.resources.displayMetrics.density
        box.background = GradientDrawable().apply {
            cornerRadius = 18 * dp
            setColor(Color.argb((bgAlpha * 255).toInt(), 12, 12, 16))
        }
        line?.setStyle(fontSp, played)
        sub?.setTextSize(TypedValue.COMPLEX_UNIT_SP, fontSp * 0.72f)
        val p = params ?: return
        p.flags = if (locked) {
            p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        }
        // Android 12+：不可点的悬浮窗整体不透明度要 ≤ 0.8，触摸才会穿透到下面的应用
        p.alpha = if (locked) 0.8f else 1f
        if (locked) bar?.visibility = View.GONE
        try { wm?.updateViewLayout(box, p) } catch (_: Exception) {}
    }
}

/// 一行歌词：先画未唱部分（白），再按进度裁剪画已唱部分（主题色）。太长时先缩字号，再省略。
class KaraokeView(ctx: Context) : View(ctx) {
    private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { isFakeBoldText = true }
    private var text = ""
    private var start = 0.0
    private var end = 0.0
    private var basePos = 0.0
    private var baseAt = SystemClock.uptimeMillis()
    private var playing = false
    private var speed = 1.0
    private var sizePx = 0f
    private var played = 0xFFF4D28A.toInt()

    fun setStyle(sp: Float, color: Int) {
        sizePx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)
        played = color
        requestLayout()
        invalidate()
    }

    fun setLine(t: String, s: Double, e: Double, pos: Double, isPlaying: Boolean, rate: Double) {
        text = t; start = s; end = e; basePos = pos; playing = isPlaying; speed = rate
        baseAt = SystemClock.uptimeMillis()
        invalidate()
    }

    private fun progress(): Float {
        if (end <= start) return 1f
        val now = basePos + if (playing) (SystemClock.uptimeMillis() - baseAt) / 1000.0 * speed else 0.0
        return ((now - start) / (end - start)).coerceIn(0.0, 1.0).toFloat()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        paint.textSize = sizePx
        val h = (paint.fontMetrics.descent - paint.fontMetrics.ascent + paint.textSize * 0.3f).toInt()
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), h)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        if (w <= 0f) return
        paint.textSize = sizePx
        var shown = text
        var tw = paint.measureText(shown)
        if (tw > w) {
            paint.textSize = max(sizePx * 0.75f, sizePx * w / tw)
            tw = paint.measureText(shown)
            if (tw > w) {
                shown = TextUtils.ellipsize(shown, paint, w, TextUtils.TruncateAt.END).toString()
                tw = paint.measureText(shown)
            }
        }
        val x = (w - tw) / 2
        val fm = paint.fontMetrics
        val y = (height - fm.descent - fm.ascent) / 2
        paint.setShadowLayer(sizePx * 0.18f, 0f, sizePx * 0.06f, 0x99000000.toInt())
        paint.color = 0xF2FFFFFF.toInt()
        canvas.drawText(shown, x, y, paint)
        val p = progress()
        if (p > 0f) {
            paint.clearShadowLayer()
            paint.color = played
            canvas.save()
            canvas.clipRect(x, 0f, x + tw * p, height.toFloat())
            canvas.drawText(shown, x, y, paint)
            canvas.restore()
        }
        if (playing && p < 1f) postInvalidateOnAnimation()
    }
}
