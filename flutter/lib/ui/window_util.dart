import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:screen_retriever/screen_retriever.dart';

/// Windows 窗口度量与设置持久化的工具集合。
class WindowUtil {
  WindowUtil._();

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final int Function(int) _getSystemMetrics = _user32
      .lookupFunction<Int32 Function(Int32), int Function(int)>(
          'GetSystemMetrics');

  static const int _smCYCAPTION = 4;
  static const int _smCYSIZEFRAME = 32;
  static const int _smCXPADDEDBORDER = 92;

  /// 窗口非客户区总高度（标题栏 + 上下边框），逻辑像素（主屏 DPI）。
  static int titleBarChromeHeight() {
    final frame =
        _getSystemMetrics(_smCYSIZEFRAME) + _getSystemMetrics(_smCXPADDEDBORDER);
    return _getSystemMetrics(_smCYCAPTION) + frame * 2;
  }

  /// 主屏工作区（逻辑像素）。
  static Future<Rect> workArea() async {
    try {
      final d = await screenRetriever.getPrimaryDisplay();
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    } catch (_) {
      return const Rect.fromLTWH(0, 0, 1600, 900);
    }
  }

  /// 所有可能的屏幕区域并集，用于校验恢复的窗口位置。
  static Future<Rect> allScreensBounds() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      Rect union = Rect.zero;
      for (final d in displays) {
        final r = Rect.fromLTWH(
          d.visiblePosition?.dx ?? 0,
          d.visiblePosition?.dy ?? 0,
          d.visibleSize?.width ?? d.size.width,
          d.visibleSize?.height ?? d.size.height,
        );
        union = union.isEmpty ? r : union.expandToInclude(r);
      }
      return union;
    } catch (_) {
      return const Rect.fromLTWH(0, 0, 1600, 900);
    }
  }
}

/// 轻量设置持久化：%LOCALAPPDATA%\EpubReader\flutter-settings.json
class AppSettings {
  AppSettings._();

  static File? _cache;

  static File get _file {
    if (_cache != null) return _cache!;
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    final dir = Directory('$base\\EpubReader');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cache = File('${dir.path}\\flutter-settings.json');
  }

  static Map<String, dynamic> load() {
    try {
      if (!_file.existsSync()) return {};
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static void save(Map<String, dynamic> data) {
    try {
      _file.writeAsStringSync(jsonEncode(data));
    } catch (_) {
      // 保存失败不影响阅读
    }
  }

  /// 读取窗口边界；不在任何屏幕内时返回 null。
  static Rect? loadBounds() {
    final m = load();
    final x = (m['x'] as num?)?.toDouble();
    final y = (m['y'] as num?)?.toDouble();
    final w = (m['width'] as num?)?.toDouble();
    final h = (m['height'] as num?)?.toDouble();
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  static void saveBounds(Rect bounds) => save({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      });
}
