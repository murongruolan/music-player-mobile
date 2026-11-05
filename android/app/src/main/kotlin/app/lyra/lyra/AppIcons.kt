package app.lyra.lyra

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/// 桌面图标切换：AndroidManifest 里每款图标一个 activity-alias（.Icon_<id>），启用一个、禁用其余。
object AppIcons {
    val ids = listOf("gold", "night", "aurora", "vinyl", "mono", "neon", "glass", "pixel")
    private const val DEFAULT = "gold"

    private fun component(ctx: Context, id: String) = ComponentName(ctx.packageName, "app.lyra.lyra.Icon_$id")

    /// 当前启用的图标 id。
    fun current(ctx: Context): String {
        // 清单里只有默认款 enabled="true"；其它款被显式启用过才算
        val pm = ctx.packageManager
        return ids.firstOrNull { it != DEFAULT && pm.getComponentEnabledSetting(component(ctx, it)) == PackageManager.COMPONENT_ENABLED_STATE_ENABLED } ?: DEFAULT
    }

    /// 换图标。先启用新的再禁用旧的，任何时刻桌面上都至少有一个入口；DONT_KILL_APP 不重启进程
    /// （少数桌面会在几秒后才刷新图标，个别厂商系统会关掉当前任务）。
    fun set(ctx: Context, id: String): Boolean {
        if (id !in ids) return false
        val pm = ctx.packageManager
        pm.setComponentEnabledSetting(component(ctx, id), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
        for (other in ids) {
            if (other == id) continue
            pm.setComponentEnabledSetting(component(ctx, other), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
        }
        return true
    }
}
