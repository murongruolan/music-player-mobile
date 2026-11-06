import AVFoundation
import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LyraNative") {
      NativeBridge.attach(registrar.messenger())
    }
  }
}

/// Dart ↔ 原生（通道 lyra/native）：画中画歌词（iOS 上的「悬浮歌词」）、灵动岛歌词、桌面图标。
enum NativeBridge {
  static var channel: FlutterMethodChannel?

  static func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "lyra/native", binaryMessenger: messenger)
    channel = ch
    LiveIsland.endAll(wait: false)  // 上次运行留下的实时活动
    // App 被划掉：灵动岛 / 锁屏歌词跟着收起，别留一句不动的歌词
    NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
      LiveIsland.endAll(wait: true)
    }
    LyricPiP.shared.onEvent = { name, arg in
      DispatchQueue.main.async { channel?.invokeMethod("float.\(name)", arguments: arg) }
    }
    ch.setMethodCallHandler { call, result in
      let a = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "float.canDraw":
        result(LyricPiP.shared.isSupported)
      case "float.request":
        result(nil)
      case "float.style":
        LyricPiP.shared.style(size: a["size"] as? Double, color: (a["color"] as? NSNumber)?.int64Value)
        result(nil)
      case "float.show":
        result(LyricPiP.shared.start())
      case "float.hide":
        LyricPiP.shared.stop()
        result(nil)
      case "float.update":
        LyricPiP.shared.update(
          text: a["text"] as? String ?? "",
          next: a["next"] as? String ?? "",
          start: a["start"] as? Double ?? 0,
          end: a["end"] as? Double ?? 0,
          pos: a["pos"] as? Double ?? 0,
          playing: a["playing"] as? Bool ?? false,
          speed: a["speed"] as? Double ?? 1)
        result(nil)
      case "icon.current":
        let name = UIApplication.shared.alternateIconName ?? ""
        result(name.hasPrefix("AppIcon-") ? String(name.dropFirst("AppIcon-".count)) : "gold")
      case "icon.set":
        let id = a["id"] as? String ?? "gold"
        guard UIApplication.shared.supportsAlternateIcons else { return result(false) }
        UIApplication.shared.setAlternateIconName(id == "gold" ? nil : "AppIcon-\(id)") { error in
          result(error == nil)
        }
      default:
        if call.method.hasPrefix("island.") {
          LiveIsland.handle(call.method, a, result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// 画中画歌词：iOS 不允许应用在别的 App 上画悬浮窗，用画中画小窗代替——把歌词逐帧画进
/// AVSampleBufferDisplayLayer，交给系统画中画显示。小窗里的播放 / 暂停键回调给 Dart。
/// 需要：Info.plist 的 UIBackgroundModes 含 audio，且正在播放（音频会话处于活动状态）。
final class LyricPiP: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
  static let shared = LyricPiP()
  var onEvent: ((String, Any?) -> Void)?

  private let display = AVSampleBufferDisplayLayer()
  private var host: UIView?
  private var pip: AVPictureInPictureController?
  private var timer: Timer?

  private var text = "Lyra"
  private var next = ""
  private var lineStart = 0.0
  private var lineEnd = 0.0
  private var basePos = 0.0
  private var baseAt = CACurrentMediaTime()
  private var playing = false
  private var speed = 1.0
  private var fontSize: CGFloat = 18
  private var played = UIColor(red: 0.957, green: 0.824, blue: 0.541, alpha: 1)

  /// 画面尺寸（10:3，画中画小窗按这个比例）。
  private let canvas = CGSize(width: 900, height: 270)

  var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

  func style(size: Double?, color: Int64?) {
    if let s = size { fontSize = CGFloat(max(12, min(36, s))) }
    if let c = color {
      let v = UInt32(truncatingIfNeeded: c)
      played = UIColor(
        red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    render()
  }

  private func keyWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    return windows.first(where: { $0.isKeyWindow }) ?? windows.first
  }

  private func setup() -> Bool {
    if pip != nil { return true }
    guard isSupported, let window = keyWindow() else { return false }
    // 显示层要挂在视图树里才能进画中画：放在 Flutter 视图下面（被盖住，用户看不到）
    let v = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 60))
    v.isUserInteractionEnabled = false
    display.frame = v.bounds
    display.videoGravity = .resizeAspect
    v.layer.addSublayer(display)
    window.insertSubview(v, at: 0)
    host = v
    let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: display, playbackDelegate: self)
    let c = AVPictureInPictureController(contentSource: source)
    c.delegate = self
    // 开着时切到后台自动进画中画
    c.canStartPictureInPictureAutomaticallyFromInline = true
    pip = c
    render()
    return true
  }

  /// 打开（App 在前台时由用户操作触发）。画中画就绪要一点时间，没就绪就稍后再试一次。
  func start() -> Bool {
    guard setup(), let c = pip else { return false }
    render()
    if c.isPictureInPicturePossible {
      c.startPictureInPicture()
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
        guard let c = self?.pip else { return }
        if c.isPictureInPicturePossible {
          c.startPictureInPicture()
        } else {
          self?.onEvent?("failed", "画中画暂时不可用，请在播放时再试")
        }
      }
    }
    return true
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    pip?.stopPictureInPicture()
    pip?.delegate = nil
    pip = nil
    host?.removeFromSuperview()
    host = nil
    display.flushAndRemoveImage()
  }

  func update(text: String, next: String, start: Double, end: Double, pos: Double, playing: Bool, speed: Double) {
    let changed = playing != self.playing
    self.text = text
    self.next = next
    self.lineStart = start
    self.lineEnd = end
    self.basePos = pos
    self.baseAt = CACurrentMediaTime()
    self.playing = playing
    self.speed = speed
    if changed { pip?.invalidatePlaybackState() }
    render()
    // 唱到一半时按时钟补帧（逐句染色）；暂停时不刷新
    if playing && pip != nil {
      if timer == nil {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.render() }
      }
    } else {
      timer?.invalidate()
      timer = nil
    }
  }

  private func progress() -> CGFloat {
    if lineEnd <= lineStart { return 1 }
    let now = basePos + (playing ? (CACurrentMediaTime() - baseAt) * speed : 0)
    return CGFloat(max(0, min(1, (now - lineStart) / (lineEnd - lineStart))))
  }

  private func render() {
    guard pip != nil, let buffer = draw() else { return }
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
    guard let fmt = format else { return }
    var timing = CMSampleTimingInfo(
      duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sample)
    guard let sb = sample else { return }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as NSArray?,
      let dict = attachments.firstObject as? NSMutableDictionary
    {
      dict[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true
    }
    if display.status == .failed { display.flush() }
    display.enqueue(sb)
  }

  private func draw() -> CVPixelBuffer? {
    let w = Int(canvas.width), h = Int(canvas.height)
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    var out: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out) == kCVReturnSuccess,
      let pb = out
    else { return nil }
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    guard
      let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    ctx.setFillColor(UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    // UIKit 坐标（左上原点）
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    UIGraphicsPushContext(ctx)
    defer { UIGraphicsPopContext() }

    let scale = canvas.width / 360  // 按 360pt 宽的小窗换算字号
    let pad = 24 * scale
    let maxW = canvas.width - pad * 2
    var font = UIFont.systemFont(ofSize: fontSize * scale * 1.1, weight: .bold)
    var size = (text as NSString).size(withAttributes: [.font: font])
    if size.width > maxW {
      font = UIFont.systemFont(ofSize: max(font.pointSize * 0.7, font.pointSize * maxW / size.width), weight: .bold)
      size = (text as NSString).size(withAttributes: [.font: font])
    }
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = .byTruncatingTail
    let hasNext = !next.isEmpty
    let lineY = hasNext ? canvas.height * 0.22 : (canvas.height - size.height) / 2
    let lineRect = CGRect(x: pad, y: lineY, width: maxW, height: size.height + 4)
    (text as NSString).draw(in: lineRect, withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: para])
    let p = progress()
    if p > 0 {
      let tw = min(size.width, maxW)
      let x0 = pad + (maxW - tw) / 2
      ctx.saveGState()
      ctx.clip(to: CGRect(x: x0, y: 0, width: tw * p, height: canvas.height))
      (text as NSString).draw(in: lineRect, withAttributes: [.font: font, .foregroundColor: played, .paragraphStyle: para])
      ctx.restoreGState()
    }
    if hasNext {
      let f2 = UIFont.systemFont(ofSize: font.pointSize * 0.68, weight: .medium)
      let r2 = CGRect(x: pad, y: lineRect.maxY + 14 * scale, width: maxW, height: f2.lineHeight + 4)
      (next as NSString).draw(in: r2, withAttributes: [.font: f2, .foregroundColor: UIColor(white: 1, alpha: 0.6), .paragraphStyle: para])
    }
    return pb
  }

  // MARK: 画中画回调

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    onEvent?("closed", nil)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error
  ) {
    onEvent?("failed", error.localizedDescription)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
    onEvent?("toggle", playing)
  }

  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
    // 直播式时间轴：小窗里不显示进度条
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
    !playing
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    onEvent?("skip", skipInterval.seconds)
    completionHandler()
  }
}
