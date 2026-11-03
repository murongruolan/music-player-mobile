// 手机端用 dart:io 的 WebSocket，不额外引依赖。
import 'dart:async';
import 'dart:io';
import 'sync_socket.dart';

Future<SyncSocket?> connectSyncSocket(Uri uri) async {
  final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 15));
  return _IoSocket(ws);
}

class _IoSocket implements SyncSocket {
  final WebSocket _ws;
  _IoSocket(this._ws);
  @override
  Stream<String> get messages => _ws.where((m) => m is String).cast<String>();
  @override
  void send(String text) => _ws.add(text);
  @override
  Future<void> close() => _ws.close();
}
