// 播放失败的归类：把音源脚本 / 播放器给出的各种原始错误归成用户看得懂的几类，
// 多个音源都失败时挑「最能说明问题」的那个告诉用户。

enum FailKind {
  /// 需要平台会员 / 没有版权（咪咕 200002、网易 fee=1 等）。
  permission,

  /// 只拿到试听片段。
  trial,

  /// 播放地址被拒绝（403 / 401），通常是链接过期或签名失效。
  forbidden,

  /// 播放地址不存在（404 / 410）。
  notFound,

  /// 音源响应超时。
  timeout,

  /// 网络连不上。
  network,

  /// 其它。
  other,
}

/// 原始错误 → 类别。
FailKind classifyFailure(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('200002') || m.contains('无权限') || m.contains('没有权限') || m.contains('permission') || m.contains('会员') || m.contains('付费') || m.contains('版权') || RegExp(r'\bvip\b').hasMatch(m)) {
    return FailKind.permission;
  }
  if (m.contains('试听')) return FailKind.trial;
  if (RegExp(r'\b40[13]\b').hasMatch(m) || m.contains('forbidden') || m.contains('unauthorized')) return FailKind.forbidden;
  if (RegExp(r'\b(404|410)\b').hasMatch(m) || m.contains('not found')) return FailKind.notFound;
  if (m.contains('timeout') || m.contains('timed out') || m.contains('超时')) return FailKind.timeout;
  if (m.contains('socketexception') || m.contains('failed host lookup') || m.contains('connection') || m.contains('network') || m.contains('网络')) return FailKind.network;
  return FailKind.other;
}

/// 类别 → 给用户看的说明（other 为空串）。
String failureLabel(FailKind k) => switch (k) {
      FailKind.permission => '需要平台会员或没有版权',
      FailKind.trial => '只拿到试听片段',
      FailKind.forbidden => '播放地址被拒绝（链接失效）',
      FailKind.notFound => '播放地址不存在',
      FailKind.timeout => '音源响应超时',
      FailKind.network => '网络连接失败',
      FailKind.other => '',
    };

/// 多个错误里挑最能说明问题的一个，拼成「类别：原始错误」。没有可归类的就用最后一个错误原文。
String summarizeFailures(List<String> errors) {
  if (errors.isEmpty) return '';
  String? best;
  var rank = FailKind.values.length;
  for (final e in errors) {
    final k = classifyFailure(e);
    if (k != FailKind.other && k.index < rank) {
      rank = k.index;
      best = e;
    }
  }
  if (best == null) return errors.last;
  final label = failureLabel(FailKind.values[rank]);
  return best.contains(label) ? best : '$label：$best';
}

/// 播放器（just_audio）抛出的错误 → 说明。
String describePlayError(Object e) {
  final raw = e.toString().trim();
  final label = failureLabel(classifyFailure(raw));
  final short = raw.length > 100 ? raw.substring(0, 100) : raw;
  return label.isEmpty ? short : '$label（$short）';
}
