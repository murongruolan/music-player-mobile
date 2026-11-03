/// 同步通知用的 WebSocket（只收文本消息）。
abstract class SyncSocket {
  Stream<String> get messages;
  void send(String text);
  Future<void> close();
}

typedef SocketConnector = Future<SyncSocket?> Function(Uri uri);
