// 直链层公共类型：DirectUrl（播放地址 + 实际音质 + 请求头）与失效异常。
//
// DirectUrl 表示「平台直链」拿到的播放地址：与音源脚本不同，它可能要求播放请求带
// 特定头（酷我 / 咪咕的 Referer、网易的 Cookie 不需要带进播放请求），引擎会用
// AudioSource.uri(uri, headers: …) 播放。

/// 平台直链的取流结果。
class DirectUrl {
  final String url;

  /// 实际命中的音质（App 档位名：128k / HQ / SQ / Hi-Res）。
  final String quality;

  /// 播放该地址必须带的请求头（没有就为空）。
  final Map<String, String> headers;

  /// 平台代码（wy / tx / kg / kw / mg），播放链路页展示用。
  final String platform;

  /// 是否试听片段（网易云 freeTrialInfo 非空）。
  final bool trial;

  const DirectUrl({
    required this.url,
    required this.quality,
    required this.platform,
    this.headers = const {},
    this.trial = false,
  });

  @override
  String toString() => 'DirectUrl($platform, $quality, ${url.length}B)';
}

/// 登录态失效：直链层发现凭证不再有效时抛出，编排层负责 markExpired 并回退音源脚本。
class DirectAuthException implements Exception {
  final String message;
  const DirectAuthException(this.message);
  @override
  String toString() => message;
}

/// 直链层的音质档位映射（与洛雪音质名对齐）。
class DirectQuality {
  DirectQuality._();

  /// 网易云 br 值（eapi song/enhance/player/url 的 br 参数）。
  static String wyBr(String q) => switch (q) {
        '128k' => '128000',
        '320k' => '320000',
        'flac' => '999000',
        'flac24bit' || 'hires' => '1999000',
        _ => '320000',
      };

  /// 网易云 level（weapi v1 接口用；eapi 兼容 br，两者取其一）。
  static String wyLevel(String q) => switch (q) {
        '128k' => 'standard',
        '320k' => 'higher',
        'flac' => 'lossless',
        'flac24bit' || 'hires' => 'hires',
        _ => 'higher',
      };

  /// QQ 音质前缀与扩展名。
  static (String, String) txPrefix(String q) => switch (q) {
        'flac' || 'flac24bit' || 'hires' => ('F000', 'flac'),
        '320k' => ('M800', 'mp3'),
        _ => ('M500', 'mp3'),
      };

  /// QQ / 酷狗 / 酷我 / 咪咕的直链通常只能给到这些档位；请求更高档位时往下收。
  static String clamp(String q) => switch (q) {
        'flac24bit' || 'hires' || 'master' || 'atmos' || 'atmos_plus' => 'flac',
        'flac' => 'flac',
        '320k' || 'HQ' => '320k',
        _ => '128k',
      };

  /// 洛雪音质 → App 档位名（ResolvedUrl / 播放链路页用）。
  static String appQuality(String lx) => switch (lx) {
        '128k' => '128k',
        '320k' => 'HQ',
        'flac' => 'SQ',
        'flac24bit' || 'hires' => 'Hi-Res',
        _ => 'HQ',
      };
}
