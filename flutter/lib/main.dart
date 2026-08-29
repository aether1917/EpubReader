import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'epub/book.dart';
import 'ui/file_association.dart';
import 'ui/reader_window.dart';

/// 纸墨传承 + Material 3：暖棕纸色种子色，浅色/深色双主题。
const Color _seedColor = Color(0xFF8B6A4F);

void main(List<String> args) {
  runAppEntry(args);
}

Future<void> runAppEntry(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 命令行工具模式：--register / --selftest
  if (args.isNotEmpty) {
    final a0 = args[0].toLowerCase();
    if (a0 == '--register') {
      stdout.writeln(await FileAssociation.setAsDefault());
      exit(0);
    }
    if (a0 == '--selftest' && args.length > 1) {
      _selfTest(args[1]);
      exit(0);
    }
  }

  await windowManager.ensureInitialized();

  EpubBook? book;
  String? error;

  final fileArgs = args
      .where((a) => a.toLowerCase().endsWith('.epub') && File(a).existsSync())
      .toList();
  if (fileArgs.isNotEmpty) {
    try {
      book = EpubBook.open(fileArgs.first);
    } catch (e) {
      error = e.toString();
    }
  } else {
    final f = await _pickEpub();
    if (f == null) exit(0); // 用户取消：直接退出
    try {
      book = EpubBook.open(f.path);
    } catch (e) {
      error = e.toString();
    }
  }

  // 窗口先创建后隐藏；由 ReaderWindow 恢复记忆位置后再 show，避免闪烁
  const windowOptions = WindowOptions(
    size: Size(1000, 760),
    minimumSize: Size(480, 420),
    title: 'EpubReader',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () {});

  runApp(EpubReaderApp(book: book, error: error));
}

Future<XFile?> _pickEpub() {
  return openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'EPUB 文件', extensions: ['epub']),
    ],
  );
}

void _selfTest(String path) {
  stdout.writeln('=== EpubReader 自检 ===');
  try {
    final book = EpubBook.open(path);
    stdout.writeln('书名     : ${book.title.isEmpty ? '(未设置)' : book.title}');
    stdout.writeln('章节数   : ${book.spine.length}');
    stdout.writeln('目录条数 : ${book.toc.length}');
    for (final t in book.toc.take(20)) {
      stdout.writeln('  ${'\u3000' * t.level}${t.title} -> ${t.href}');
    }
    if (book.spine.isEmpty) {
      stdout.writeln('失败：spine 为空，EPUB 无内容章节。');
      return;
    }
    final f = book.chapterFile(book.spine.first);
    stdout.writeln('首章文件 : ${f?.path}  存在=${f?.existsSync()}');
    book.dispose();
    stdout.writeln('OK');
  } catch (e) {
    stdout.writeln('失败：$e');
  }
}

class EpubReaderApp extends StatelessWidget {
  const EpubReaderApp({super.key, required this.book, this.error});

  final EpubBook? book;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final light = ColorScheme.fromSeed(seedColor: _seedColor);
    final dark = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'EpubReader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: light, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
      themeMode: ThemeMode.system,
      home: ReaderWindow(book: book, startError: error),
    );
  }
}
