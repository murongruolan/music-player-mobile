// 导入字体：用户选一个 .ttf / .otf，复制到 App 文档目录，用 FontLoader 注册成「LyraCustom」字体族。
// 只在本 App 内生效；下次启动时自动重新加载。别的设备同步到「custom」时找不到文件，退回系统字体。
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const customFontFamily = 'LyraCustom';

bool _loaded = false;

/// 当前是否已经有可用的导入字体。
bool get customFontReady => _loaded;

Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/lyra-custom-font');

Future<void> _register(Uint8List bytes) async {
  final loader = FontLoader(customFontFamily)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
  _loaded = true;
}

/// 启动时调用：之前导入过就重新注册。
Future<void> loadCustomFont() async {
  try {
    final f = await _file();
    if (await f.exists()) await _register(await f.readAsBytes());
  } catch (_) {}
}

/// 选文件并导入。返回导入的文件名；用户取消返回 null；文件不是字体时抛出说明。
Future<String?> importCustomFont() async {
  final x = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: '字体', extensions: ['ttf', 'otf', 'ttc'], mimeTypes: ['font/ttf', 'font/otf', 'application/x-font-ttf', 'application/x-font-otf', 'application/octet-stream']),
  ]);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  if (bytes.length < 1024 || bytes.length > 40 * 1024 * 1024) throw const FormatException('文件大小不像字体（应在 1 KB ~ 40 MB 之间）');
  // TrueType 0x00010000 / 'true' / OpenType 'OTTO' / 字体集 'ttcf'
  final head = String.fromCharCodes(bytes.sublist(0, 4));
  final isTtf = bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0;
  if (!isTtf && head != 'OTTO' && head != 'true' && head != 'ttcf') throw const FormatException('这不是 .ttf / .otf 字体文件');
  await _register(bytes);
  await (await _file()).writeAsBytes(bytes, flush: true);
  return x.name;
}
