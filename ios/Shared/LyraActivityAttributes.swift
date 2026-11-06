import ActivityKit
import Foundation

/// 灵动岛 / 锁屏实时活动的数据。App（Runner）和小组件扩展（LyraWidget）都编译这个文件，
/// 两边类型名和字段必须一致，系统靠它把 App 推的状态交给扩展画出来。
/// ContentState 整体编码后不能超过 4KB（封面缩略图控制在 2KB 内）。
@available(iOS 16.1, *)
struct LyraActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var title: String
    var artist: String
    /// 当前这句歌词；没有歌词时为空（只显示歌名）。
    var line: String
    /// 下一句或翻译。
    var next: String
    var playing: Bool
    /// 播放中：进度为 0 的时刻（now - 已播秒数 / 倍速），系统按它自己走进度条，不用每秒推送。
    var anchor: Date
    /// 已播秒数（暂停时显示用）。
    var position: Double
    /// 歌曲时长（秒，按当前倍速换算后的实际时长），0 = 未知，不显示进度条。
    var duration: Double
    /// 强调色 0xRRGGBB。
    var tint: Int
    /// 封面缩略图（JPEG，约 48px）。
    var art: Data?
  }

  /// 固定字段（启动后不能改）。只放个名字，内容全在 ContentState 里。
  var app: String = "Lyra"
}
