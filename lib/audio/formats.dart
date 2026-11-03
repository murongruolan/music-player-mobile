// 音频格式支持矩阵与识别。纯逻辑，供测试覆盖。
//
// 真实解码由平台播放器完成：Android = Media3/ExoPlayer，iOS = AVPlayer。
// 这里只负责「从 URI / MIME 判断格式」和「声明支持范围」，播放能力以平台为准。

/// 平台播放器可直接解码的格式（Media3 与 AVPlayer 的交集，移动端主流格式全覆盖）。
const supportedFormats = <String>{
  'mp3', 'aac', 'm4a', 'mp4', 'flac', 'wav', 'ogg', 'oga', 'opus', 'webm', '3gp', 'amr',
};

/// 平台播放器不支持、需要额外解码器的格式（APE / TTA / TAK 等）。
/// 这些格式将来要么引入 FFmpeg 扩展（本地编译成本高），要么由音源脚本直接返回
/// 转码后的流。当前明确不支持，UI 侧不应静默失败。
const unsupportedFormats = <String>{'ape', 'tta', 'tak', 'dsf', 'dff', 'wv'};

/// 从 URI 扩展名识别格式；识别不出返回空字符串。
String formatOfUri(Uri uri) {
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1);
}

/// 该 URI 是否可能被平台播放器直接解码。
/// 识别不出扩展名时不武断拒绝（很多流媒体 URL 无扩展名，交给平台尝试）。
bool isLikelySupported(Uri uri) {
  final fmt = formatOfUri(uri);
  if (fmt.isEmpty) return true;
  return !unsupportedFormats.contains(fmt);
}

/// 人话格式名（测试 / 日志用）。
String formatLabel(String fmt) => switch (fmt) {
      'mp3' => 'MP3',
      'aac' => 'AAC',
      'm4a' || 'mp4' => 'M4A',
      'flac' => 'FLAC',
      'wav' => 'WAV',
      'ogg' || 'oga' => 'OGG',
      'opus' || 'webm' => 'Opus',
      'ape' => 'APE',
      _ => fmt.toUpperCase(),
    };
