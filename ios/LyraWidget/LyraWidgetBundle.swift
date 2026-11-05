import SwiftUI
import WidgetKit

/// 小组件扩展入口：目前只有灵动岛 / 锁屏的实时活动（歌词）。
@main
struct LyraWidgetBundle: WidgetBundle {
  var body: some Widget {
    LyraLiveActivity()
  }
}
