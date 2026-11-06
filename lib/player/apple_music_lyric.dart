// Apple Music 风格歌词（SpringSkin 专用）：分块、智能模糊、点击反馈。
// - 分块：按段落（section）或每 1-2 行为一块；有翻译时本句+翻译为一块
// - 模糊：只有正在唱的块清晰，用户滚动时全清晰，停滚 1.5s 后自动恢复模糊
// - 点击：块有半透明背景动画，点击后跳转到该时间
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/state.dart';
import '../data/mock.dart';
import '../ui/kit.dart';

class AppleMusicLyric extends StatefulWidget {
  /// 用户开始滚动或看下面歌词时调用（通知 SpringSkin 收起控制台）
  final VoidCallback? onUserScroll;
  
  /// 用户点击歌词外空白时调用（通知 SpringSkin 显示控制台）
  final VoidCallback? onTapOutside;
  
  const AppleMusicLyric({super.key, this.onUserScroll, this.onTapOutside});
  
  @override
  State<AppleMusicLyric> createState() => _AppleMusicLyricState();
}

class _LyricChunk {
  final List<int> lineIndices; // 这个块包含哪几行（lyrics 数组的下标）
  final String mainText;       // 主歌词（可能是多行拼起来的）
  final String transText;      // 翻译（如果有）
  final double startTime;      // 块开始时间（第一行的 t）
  final double endTime;        // 块结束时间（最后一行的 t + d，或下一块的 startTime）
  
  _LyricChunk(this.lineIndices, this.mainText, this.transText, this.startTime, this.endTime);
}

class _AppleMusicLyricState extends State<AppleMusicLyric> with TickerProviderStateMixin {
  final _scrollC = ScrollController();
  late final Ticker _ticker = createTicker((_) => _frame());
  AppState? _app;
  
  List<_LyricChunk> _chunks = [];
  int _currentChunk = -1;
  bool _userScrolling = false; // 用户正在手动滚动
  Timer? _blurTimer;
  int _tapChunk = -1;          // 点击中的块（用于显示背景动画）
  int _lyricsVersion = -1;
  
  // 块的全局位置缓存（用于判断点击是否在块内）
  final _chunkKeys = <int, GlobalKey>{};
  
  @override
  void initState() {
    super.initState();
    _scrollC.addListener(_onScroll);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = context.appRead;
    if (a != _app) {
      _app?.pos.removeListener(_onPos);
      _app?.removeListener(_onApp);
      _app = a
        ..pos.addListener(_onPos)
        ..addListener(_onApp);
      _buildChunks();
      _syncTicker();
    }
  }
  
  void _syncTicker() {
    final run = _app?.playing ?? false;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }
  
  void _onApp() {
    if (_app!.lyricsVersion != _lyricsVersion) _buildChunks();
    _syncTicker();
  }
  
  void _onPos() {
    if (!_ticker.isActive) _frame();
  }
  
  void _frame() {
    if (!mounted || _chunks.isEmpty) return;
    final p = _app!.smoothPos + _app!.set.loff;
    var nk = -1;
    for (var i = 0; i < _chunks.length; i++) {
      if (_chunks[i].startTime <= p) nk = i;
    }
    if (nk != _currentChunk) {
      setState(() => _currentChunk = nk);
      if (!_userScrolling && _scrollC.hasClients) {
        _scrollToChunk(nk, animate: true);
      }
    }
  }
  
  void _buildChunks() {
    // 分块策略：
    // 1. 有翻译时：本句 + 翻译为一块
    // 2. 无翻译时：尝试每两句合成一块（前提是同一 section 且间隔不太大）
    // 3. section 变化时强制切块
    _chunks = [];
    _chunkKeys.clear();
    
    var i = 0;
    while (i < lyrics.length) {
      final lines = <int>[i];
      final first = lyrics[i];
      var mainText = first.text.trim();
      var transText = first.trans.trim();
      var endTime = i + 1 < lyrics.length ? lyrics[i + 1].t : first.t + first.d;
      
      if (transText.isNotEmpty) {
        // 有翻译：本句 + 翻译为一块
        i++;
      } else if (i + 1 < lyrics.length) {
        final next = lyrics[i + 1];
        // 尝试合并下一句：同 section、间隔 < 3 秒
        if (next.section == first.section && (next.t - (first.t + first.d)) < 3) {
          lines.add(i + 1);
          mainText = '$mainText\n${next.text.trim()}';
          endTime = i + 2 < lyrics.length ? lyrics[i + 2].t : next.t + next.d;
          i += 2;
        } else {
          i++;
        }
      } else {
        i++;
      }
      
      final k = _chunks.length;
      _chunkKeys[k] = GlobalKey();
      _chunks.add(_LyricChunk(lines, mainText, transText, first.t, endTime));
    }
    
    _lyricsVersion = _app!.lyricsVersion;
    setState(() => _currentChunk = -1);
  }
  
  void _onScroll() {
    if (_scrollC.hasClients) {
      final offset = _scrollC.offset;
      final atTop = offset <= 10;
      
      if (!_userScrolling && !atTop) {
        setState(() => _userScrolling = true);
        widget.onUserScroll?.call();
      }
      
      _blurTimer?.cancel();
      _blurTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _userScrolling = false);
      });
    }
  }
  
  void _scrollToChunk(int k, {bool animate = true}) {
    if (k < 0 || k >= _chunks.length || !_scrollC.hasClients) return;
    
    // 找到块的位置
    final key = _chunkKeys[k];
    if (key?.currentContext == null) return;
    
    final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    // 滚动到该块，让它在屏幕 30% 的位置
    final scrollPos = renderBox.localToGlobal(Offset.zero).dy;
    final viewportHeight = _scrollC.position.viewportDimension;
    final targetOffset = _scrollC.offset + scrollPos - viewportHeight * 0.3;
    
    if (animate) {
      _scrollC.animateTo(
        targetOffset.clamp(_scrollC.position.minScrollExtent, _scrollC.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollC.jumpTo(
        targetOffset.clamp(_scrollC.position.minScrollExtent, _scrollC.position.maxScrollExtent),
      );
    }
  }
  
  @override
  void dispose() {
    _app?.pos.removeListener(_onPos);
    _app?.removeListener(_onApp);
    _scrollC.dispose();
    _ticker.dispose();
    _blurTimer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_chunks.isEmpty) {
      return const Center(child: Text('暂无歌词', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 16)));
    }
    
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _handleTap(d.localPosition),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.15, 0.75, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scrollC,
          padding: const EdgeInsets.symmetric(vertical: 60),
          itemCount: _chunks.length,
          itemBuilder: (c, i) => _buildChunk(i),
        ),
      ),
    );
  }
  
  Widget _buildChunk(int i) {
    final chunk = _chunks[i];
    final isCurrent = i == _currentChunk;
    final shouldBlur = !_userScrolling && !isCurrent;
    final isTapped = _tapChunk == i;
    
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chunk.mainText,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          if (chunk.transText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              chunk.transText,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: Color(0xB3FFFFFF),
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
    
    // 点击背景动画
    content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isTapped ? const Color(0x33FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
    
    // 模糊效果：非当前块且不在滚动中时模糊
    if (shouldBlur) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.decal),
        child: Opacity(
          opacity: 0.35,
          child: content,
        ),
      );
    }
    
    return GestureDetector(
      key: _chunkKeys[i],
      onTapUp: (_) => _onChunkTap(i),
      child: content,
    );
  }
  
  void _onChunkTap(int i) {
    setState(() => _tapChunk = i);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _tapChunk = -1);
    });
    
    final chunk = _chunks[i];
    _app!.seek(chunk.startTime + 0.05);
    toast('跳转到 ${fmtTime(chunk.startTime)}', 'lyric');
  }
  
  void _handleTap(Offset localPos) {
    // 判断是否点击在歌词块外的空白区域
    bool hitAnyChunk = false;
    
    for (final entry in _chunkKeys.entries) {
      final key = entry.value;
      if (key.currentContext == null) continue;
      
      final renderBox = key.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;
      
      final localToGlobal = renderBox.localToGlobal(Offset.zero);
      final globalToLocal = (context.findRenderObject() as RenderBox).globalToLocal(localToGlobal);
      final chunkRect = globalToLocal & renderBox.size;
      
      if (chunkRect.contains(localPos)) {
        hitAnyChunk = true;
        break;
      }
    }
    
    if (!hitAnyChunk) {
      // 点击在空白：唤起控制台
      widget.onTapOutside?.call();
    }
  }
}
