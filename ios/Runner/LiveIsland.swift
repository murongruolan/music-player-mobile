import ActivityKit
import Flutter
import Foundation
import MediaPlayer
import UIKit

/// Dart（lib/core/live_island.dart）→ 灵动岛 / 锁屏歌词（实时活动，iOS 16.1+）。
/// 界面在 LyraWidget 扩展里；这里只负责开始 / 更新 / 结束活动。
/// - 只能在 App 处于前台时开始（系统限制），开始之后切到后台照常更新；
/// - 系统「正在播放」的灵动岛照常存在，两者并存时由系统决定谁展开。
enum LiveIsland {
  static func handle(_ method: String, _ a: [String: Any], _ result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      return result(method == "island.supported" ? false : "unsupported")
    }
    switch method {
    case "island.supported":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "island.update":
      result(IslandActivity.shared.update(a))
    case "island.end":
      IslandActivity.shared.endAll(wait: false)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 启动时清掉上次留下的活动（App 被杀后活动不会自己消失）；退出时同步结束。
  static func endAll(wait: Bool) {
    guard #available(iOS 16.1, *) else { return }
    IslandActivity.shared.endAll(wait: wait)
  }
}

@available(iOS 16.1, *)
final class IslandActivity {
  static let shared = IslandActivity()
  typealias State = LyraActivityAttributes.ContentState

  private var activity: Activity<LyraActivityAttributes>?
  private var artKey = ""
  private var art: Data?

  /// 返回 "ok" / "background"（在后台，开始不了，回到前台再试）/ "disabled"（用户在系统设置里关了）/ 错误信息。
  func update(_ a: [String: Any]) -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "disabled" }
    let title = clip(a["title"] as? String ?? "", 60)
    let artist = clip(a["artist"] as? String ?? "", 60)
    let speed = max(0.25, a["speed"] as? Double ?? 1)
    let pos = max(0, a["pos"] as? Double ?? 0) / speed
    let dur = max(0, a["dur"] as? Double ?? 0) / speed
    refreshArt(title: title, artist: artist)
    let state = State(
      title: title,
      artist: artist,
      line: clip(a["line"] as? String ?? "", 80),
      next: clip(a["next"] as? String ?? "", 80),
      playing: a["playing"] as? Bool ?? false,
      anchor: Date().addingTimeInterval(-pos),
      position: pos,
      duration: dur,
      tint: (a["tint"] as? NSNumber)?.intValue ?? 0,
      art: art)

    if let act = activity, alive(act) {
      push(act, state)
      return "ok"
    }
    activity = nil
    if let act = Activity<LyraActivityAttributes>.activities.first(where: alive) {
      activity = act
      push(act, state)
      return "ok"
    }
    guard UIApplication.shared.applicationState == .active else { return "background" }
    do {
      if #available(iOS 16.2, *) {
        activity = try Activity.request(
          attributes: LyraActivityAttributes(), content: ActivityContent(state: state, staleDate: nil), pushType: nil)
      } else {
        activity = try Activity.request(attributes: LyraActivityAttributes(), contentState: state, pushType: nil)
      }
      return "ok"
    } catch {
      return "error: \(error.localizedDescription)"
    }
  }

  func endAll(wait: Bool) {
    activity = nil
    let acts = Activity<LyraActivityAttributes>.activities
    guard !acts.isEmpty else { return }
    let done = DispatchSemaphore(value: 0)
    Task.detached {
      for act in acts {
        if #available(iOS 16.2, *) {
          await act.end(nil, dismissalPolicy: .immediate)
        } else {
          await act.end(using: nil, dismissalPolicy: .immediate)
        }
      }
      done.signal()
    }
    if wait { _ = done.wait(timeout: .now() + 1.5) }
  }

  private func alive(_ act: Activity<LyraActivityAttributes>) -> Bool {
    act.activityState != .ended && act.activityState != .dismissed
  }

  private func push(_ act: Activity<LyraActivityAttributes>, _ s: State) {
    Task {
      if #available(iOS 16.2, *) {
        await act.update(ActivityContent(state: s, staleDate: nil))
      } else {
        await act.update(using: s)
      }
    }
  }

  private func clip(_ s: String, _ n: Int) -> String {
    s.count > n ? String(s.prefix(n)) + "…" : s
  }

  /// 封面：扩展不能联网，直接用系统「正在播放」里的封面（audio_service 已经设好），
  /// 缩成 48px JPEG 塞进状态（整个状态不能超过 4KB）。封面是异步下载的，没拿到就下次推送再试。
  private func refreshArt(title: String, artist: String) {
    let key = "\(title)|\(artist)"
    if key != artKey {
      artKey = key
      art = nil
    }
    guard art == nil else { return }
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    guard (info?[MPMediaItemPropertyTitle] as? String) == title,
      let artwork = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
      let img = artwork.image(at: CGSize(width: 96, height: 96))
    else { return }
    art = thumbnail(img)
  }

  private func thumbnail(_ img: UIImage) -> Data? {
    let side: CGFloat = 48
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
      let w = img.size.width, h = img.size.height
      guard w > 0, h > 0 else { return }
      let k = max(side / w, side / h)
      let dw = w * k, dh = h * k
      img.draw(in: CGRect(x: (side - dw) / 2, y: (side - dh) / 2, width: dw, height: dh))
    }
    for q in [0.7, 0.5, 0.3] as [CGFloat] {
      if let d = small.jpegData(compressionQuality: q), d.count <= 1800 { return d }
    }
    return nil
  }
}
