// 编译覆盖检查：强制 flutter test 编译整个应用层（main/reader_window 等 UI 代码）。
import 'package:epub_reader/main.dart';
import 'package:epub_reader/ui/reader_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('应用层类型可实例化引用（编译完整性）', () {
    expect(EpubReaderApp, isNotNull);
    expect(ReaderWindow, isNotNull);
  });
}
