import 'dart:io';

String systemVersion() {
  try {
    return Platform.operatingSystemVersion;
  } catch (_) {
    return '';
  }
}

String deviceName(String platform) {
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty && host != 'localhost') return host;
  } catch (_) {}
  return switch (platform) { 'ios' => 'iPhone', 'android' => 'Android 手机', _ => platform };
}
