import ActivityKit
import SwiftUI
import WidgetKit

/// 灵动岛 + 锁屏的歌词实时活动。数据由 App 在换句 / 暂停 / 换歌 / 拖进度时推送，
/// 进度条和计时由系统按 anchor 自己走（扩展不能自己刷新，也不能联网）。
struct LyraLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LyraActivityAttributes.self) { ctx in
      LockScreenView(s: ctx.state)
        .activityBackgroundTint(Color.black.opacity(0.6))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { ctx in
      let s = ctx.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          ArtView(data: s.art, size: 52, radius: 12)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Image(systemName: s.playing ? "waveform" : "pause.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(Color(rgb: s.tint))
            .frame(width: 44, height: 52)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(s.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(s.artist).font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            LyricLines(s: s, size: 17)
            ProgressRow(s: s)
          }
          .padding(.horizontal, 6)
        }
      } compactLeading: {
        ArtView(data: s.art, size: 22, radius: 6)
      } compactTrailing: {
        Text(s.line.isEmpty ? s.title : s.line)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(Color(rgb: s.tint))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(maxWidth: 120)
      } minimal: {
        ArtView(data: s.art, size: 22, radius: 11)
      }
      .keylineTint(Color(rgb: s.tint))
    }
  }
}

// MARK: - 视图

private struct LockScreenView: View {
  let s: LyraActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        ArtView(data: s.art, size: 44, radius: 10)
        VStack(alignment: .leading, spacing: 2) {
          Text(s.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
          Text(s.artist).font(.system(size: 12)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
        }
        Spacer(minLength: 0)
        Image(systemName: s.playing ? "waveform" : "pause.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(Color(rgb: s.tint))
      }
      LyricLines(s: s, size: 18)
      ProgressRow(s: s)
    }
    .foregroundColor(.white)
    .padding(16)
  }
}

private struct LyricLines: View {
  let s: LyraActivityAttributes.ContentState
  let size: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(s.line.isEmpty ? "♪" : s.line)
        .font(.system(size: size, weight: .bold))
        .foregroundColor(Color(rgb: s.tint))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      if !s.next.isEmpty {
        Text(s.next)
          .font(.system(size: size * 0.72, weight: .medium))
          .foregroundColor(.white.opacity(0.55))
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// 进度条 + 已播 / 总时长。播放中交给系统按时间区间自己走；暂停时画静态进度。
private struct ProgressRow: View {
  let s: LyraActivityAttributes.ContentState

  var body: some View {
    if s.duration > 1 {
      let end = s.anchor.addingTimeInterval(s.duration)
      HStack(spacing: 8) {
        if s.playing && end > Date() {
          Text(timerInterval: s.anchor...end, countsDown: false)
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.white.opacity(0.55))
            .frame(width: 40, alignment: .leading)
          ProgressView(timerInterval: s.anchor...end, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            .tint(Color(rgb: s.tint))
        } else {
          Text(clock(s.position))
            .font(.system(size: 11).monospacedDigit())
            .foregroundColor(.white.opacity(0.55))
            .frame(width: 40, alignment: .leading)
          ProgressView(value: min(max(s.position, 0), s.duration), total: s.duration)
            .tint(Color(rgb: s.tint))
        }
        Text(clock(s.duration))
          .font(.system(size: 11).monospacedDigit())
          .foregroundColor(.white.opacity(0.55))
      }
    }
  }

  private func clock(_ t: Double) -> String {
    let v = max(0, Int(t.rounded(.down)))
    return String(format: "%d:%02d", v / 60, v % 60)
  }
}

private struct ArtView: View {
  let data: Data?
  let size: CGFloat
  let radius: CGFloat

  var body: some View {
    Group {
      if let d = data, let img = UIImage(data: d) {
        Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
      } else {
        ZStack {
          Color.white.opacity(0.12)
          Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold)).foregroundColor(.white.opacity(0.8))
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

private extension Color {
  init(rgb: Int) {
    let v = rgb == 0 ? 0xF4D28A : rgb
    self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
  }
}
