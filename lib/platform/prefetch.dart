// 空闲预载：当前平台的发现页加载完、用户停手 [idle] 之后，逐个把其他平台的发现页数据拉进 PlatformHub 的缓存，
// 切换平台时就能直接出内容。约束：
//   - 只在 Wi-Fi / 有线网络下进行（判断失败按非 Wi-Fi 处理，不预载）；
//   - 一次只拉一个平台，每拉完一个都重新等一段空闲；用户一有触摸 / 滚动就重新计时；
//   - 只拉列表数据（推荐歌单 / 榜单 / 此刻热门 / 歌单分类），不拉图片、不进二级页；
//   - 失败不重试（PlatformHub 不缓存失败结果，真切过去时会正常重新请求）。
import 'dart:async';
import 'package:flutter/gestures.dart';
import '../core/network.dart';
import 'models.dart';
import 'registry.dart';

class IdlePrefetch {
  final PlatformHub hub;
  final Duration idle;
  final Future<bool> Function() _unmetered;

  IdlePrefetch(this.hub, {this.idle = const Duration(milliseconds: 2500), Future<bool> Function()? unmetered}) : _unmetered = unmetered ?? onUnmeteredNetwork;

  final _queue = <String>[];
  Timer? _timer;
  bool _routed = false, _busy = false;

  /// 已经预载过（或正在预载）的平台，避免每次回到发现页都重来一遍。
  final _done = <String>{};

  /// 测试用：当前排队中的平台代码。
  List<String> get pending => List.unmodifiable(_queue);

  /// 当前平台 [current] 的发现页已就绪：排队预载其余平台。
  void start(String current) {
    final cur = PlatformHub.codeOf(current);
    _done.add(cur);
    _queue
      ..clear()
      ..addAll(Plat.all.where((c) => !_done.contains(c) && hub.supports(c)));
    if (_queue.isEmpty) return stop();
    if (!_routed) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      _routed = true;
    }
    if (!_busy) _arm();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    if (_routed) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      _routed = false;
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(idle, _step);
  }

  // 有操作就重新计时；正在请求的那个平台让它跑完，下一个再等空闲。
  void _onPointer(PointerEvent e) {
    if (_timer != null && (e is PointerDownEvent || e is PointerMoveEvent || e is PointerScrollEvent)) _arm();
  }

  Future<void> _step() async {
    _timer = null;
    if (_queue.isEmpty) return stop();
    if (!await _unmetered()) return stop();
    final c = _queue.removeAt(0);
    _done.add(c);
    _busy = true;
    try {
      await Future.wait<Object?>([
        hub.discover(c),
        hub.playlistCategories(c),
      ].map((f) => f.then<Object?>((v) => v, onError: (Object _) => null)));
    } finally {
      _busy = false;
    }
    if (_queue.isEmpty) return stop();
    if (_routed) _arm();
  }
}

/// 当前是否在 Wi-Fi / 有线网络。判断不了时按非 Wi-Fi 处理（不预载）。
Future<bool> onUnmeteredNetwork() async => await currentNetwork() == NetKind.unmetered;
