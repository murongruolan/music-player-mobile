// Web 端没有 dart:io WebSocket（Web 版只用于截图），实时通知不可用，引擎退回到定时拉取。
import 'sync_socket.dart';

Future<SyncSocket?> connectSyncSocket(Uri uri) async => null;
