// 本地键值存储。
// - SecureKvStore：系统钥匙串（iOS Keychain / Android Keystore 加密存储），放令牌、设备 ID、服务器地址。
// - PrefsKvStore：shared_preferences，放非敏感、可能较大的数据（公告已读、同步状态、听歌统计、埋点队列）。
// - MemoryKvStore：测试和截图。
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class KvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryKvStore implements KvStore {
  final _m = <String, String>{};
  MemoryKvStore([Map<String, String>? initial]) {
    if (initial != null) _m.addAll(initial);
  }
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class SecureKvStore implements KvStore {
  final FlutterSecureStorage _s;
  SecureKvStore()
      // ignore: prefer_const_constructors
      : _s = FlutterSecureStorage(
          // ignore: prefer_const_constructors
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  // 钥匙串偶发读写失败（如重装后 Android 密钥失效）时不让 App 崩溃：读不到就当没有。
  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _s.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (_) {}
  }
}

class PrefsKvStore implements KvStore {
  final _p = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) async {
    try {
      return await _p.getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _p.setString(key, value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _p.remove(key);
    } catch (_) {}
  }
}
