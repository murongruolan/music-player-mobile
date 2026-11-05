import 'package:flutter_test/flutter_test.dart';
import 'package:lyra/download/downloads.dart';

void main() {
  test('续传时的文件总大小', () {
    expect(parseTotalBytes('bytes 1000-9999/10000', 9000, 1000), 10000);
    expect(parseTotalBytes(null, 9000, 1000), 10000);
    expect(parseTotalBytes(null, 5000, 0), 5000);
    expect(parseTotalBytes('bytes 0-99/*', null, 0), 0);
    expect(parseTotalBytes(null, null, 1000), 0);
  });
}
