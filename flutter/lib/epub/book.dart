import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

/// 目录条目（与 C# 版 TocEntry 对应）。
class TocEntry {
  TocEntry({required this.title, required this.href, this.level = 0});

  final String title;

  /// OPF 相对路径，可带 `#锚点` 片段。
  final String href;

  final int level;
}

/// 一个已解包的 EPUB 书籍：解析 container → OPF → spine / manifest / 目录。
class EpubBook {
  EpubBook._(this.sourcePath, this.tempDir);

  final String sourcePath;
  final Directory tempDir;

  String title = '';
  late final Directory opfDir;
  final List<String> spine = [];
  final List<TocEntry> toc = [];

  /// OPF 所在目录相对包根的 posix 路径（根目录时为 ''）。
  String _opfRelDir = '';

  bool _disposed = false;

  /// 打开并解析 EPUB 文件；解析失败抛出异常。
  static EpubBook open(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('文件不存在', path);
    }
    final tempDir = Directory.systemTemp.createTempSync('EpubReader_');
    final book = EpubBook._(path, tempDir);
    try {
      _extractZip(file.readAsBytesSync(), tempDir);
      book._parse();
      return book;
    } catch (_) {
      book.dispose();
      rethrow;
    }
  }

  // ——— 解析 ———

  void _parse() {
    final containerFile = _locate(const ['META-INF/container.xml']);
    if (containerFile == null) {
      throw const FormatException('不是有效的 EPUB：缺少 META-INF/container.xml');
    }
    final container = xml.XmlDocument.parse(_readText(containerFile));
    xml.XmlElement? rootfile;
    for (final e in allElements(container)) {
      if (e.name.local == 'rootfile') {
        rootfile = e;
        break;
      }
    }
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null || opfPath.isEmpty) {
      throw const FormatException('不是有效的 EPUB：container.xml 中缺少 rootfile');
    }

    final opfFile = _locate([opfPath]);
    if (opfFile == null) {
      throw FormatException('OPF 文件缺失：$opfPath');
    }
    opfDir = opfFile.parent;
    final slash = opfPath.lastIndexOf('/');
    _opfRelDir = slash >= 0 ? opfPath.substring(0, slash) : '';
    final opf = xml.XmlDocument.parse(_readText(opfFile));

    for (final e in allElements(opf)) {
      if (e.name.local == 'title' && title.isEmpty) {
        title = e.innerText.trim();
      }
    }

    final idToHref = <String, String>{};
    for (final e in allElements(opf)) {
      if (e.name.local == 'item') {
        final id = e.getAttribute('id');
        final href = e.getAttribute('href');
        if (id != null && href != null) idToHref[id] = href;
      }
    }

    String? ncxHref;
    for (final e in allElements(opf)) {
      if (e.name.local == 'spine') {
        final ncxId = e.getAttribute('toc');
        if (ncxId != null && idToHref.containsKey(ncxId)) {
          ncxHref = idToHref[ncxId];
        }
        for (final ref in allElements(e, recursive: false)) {
          if (ref.name.local == 'itemref') {
            final idref = ref.getAttribute('idref');
            if (idref != null && idToHref.containsKey(idref)) {
              spine.add(normalizeHref(idToHref[idref]!));
            }
          }
        }
      }
    }

    if (ncxHref != null) {
      final ncxFile = _locate([_joinPosix(_opfRelDir, ncxHref)]);
      if (ncxFile != null) _loadNcx(ncxFile);
    }
    if (toc.isEmpty) _loadNav();
  }

  void _loadNcx(File ncxFile) {
    try {
      final doc = xml.XmlDocument.parse(_readText(ncxFile));
      void walk(xml.XmlElement navPoint, int level) {
        String? label;
        String? src;
        for (final e in allElements(navPoint, recursive: false)) {
          if (e.name.local == 'navLabel') {
            for (final t in allElements(e, recursive: false)) {
              if (t.name.local == 'text') label = t.innerText.trim();
            }
          } else if (e.name.local == 'content') {
            src = e.getAttribute('src');
          }
        }
        if (label != null && label.isNotEmpty && src != null) {
          toc.add(TocEntry(title: label, href: normalizeHref(src), level: level));
        }
        for (final child in allElements(navPoint, recursive: false)) {
          if (child.name.local == 'navPoint') walk(child, level + 1);
        }
      }

      for (final e in allElements(doc)) {
        if (e.name.local == 'navMap') {
          for (final p in allElements(e, recursive: false)) {
            if (p.name.local == 'navPoint') walk(p, 0);
          }
        }
      }
    } catch (_) {
      // 忽略损坏的 NCX，回落到 nav.xhtml
    }
  }

  void _loadNav() {
    final candidates = <File>[];
    final navFile = _locate(const ['nav.xhtml', 'nav.html']);
    if (navFile != null) candidates.add(navFile);
    for (final spineHref in spine) {
      final f = _locate([_joinPosix(_opfRelDir, spineHref)]);
      if (f != null) candidates.add(f);
    }
    for (final f in candidates) {
      try {
        final doc = html_parser.parse(_readText(f));
        final navs = doc.querySelectorAll('nav');
        dom.Element? chosen;
        for (final nav in navs) {
          final type =
              qualifiedAttr(nav, 'epub:type') ?? nav.attributes['type'];
          if (type != null && type.split(RegExp(r'\s+')).contains('toc')) {
            chosen = nav;
            break;
          }
        }
        chosen ??= navs.isNotEmpty ? navs.first : null;
        if (chosen == null) continue;

        void walkList(dom.Element list, int level) {
          for (final li in list.children.whereType<dom.Element>()) {
            if (li.localName != 'li') continue;
            var added = false;
            for (final a in li.children.whereType<dom.Element>()) {
              if (a.localName == 'a') {
                final href = a.attributes['href'];
                final t = a.text.trim();
                if (href != null && href.isNotEmpty && t.isNotEmpty) {
                  toc.add(TocEntry(title: t, href: normalizeHref(href), level: level));
                  added = true;
                }
              } else if (a.localName == 'ol' || a.localName == 'ul') {
                walkList(a, level + 1);
              }
            }
            if (!added) {
              for (final sub in li.children.whereType<dom.Element>()) {
                if (sub.localName == 'ol' || sub.localName == 'ul') {
                  walkList(sub, level + 1);
                }
              }
            }
          }
        }

        for (final child in chosen.children.whereType<dom.Element>()) {
          if (child.localName == 'ol' || child.localName == 'ul') {
            walkList(child, 0);
          }
        }
        // nav 内散落的 <a>（无 ol/li 结构）兜底收集
        if (toc.isEmpty) {
          for (final a in chosen.querySelectorAll('a')) {
            final href = a.attributes['href'];
            final t = a.text.trim();
            if (href != null && href.isNotEmpty && t.isNotEmpty) {
              toc.add(TocEntry(title: t, href: normalizeHref(href)));
            }
          }
        }
        if (toc.isNotEmpty) return;
      } catch (_) {
        // 尝试下一个候选
      }
    }
  }

  // ——— 路径与内容 ———

  /// 规范化 href：去转义、统一 `/` 分隔，保留 `#片段`。
  static String normalizeHref(String href) {
    final i = href.indexOf('#');
    final pathPart = i >= 0 ? href.substring(0, i) : href;
    final anchor = i >= 0 ? href.substring(i) : '';
    final decoded = Uri.decodeComponent(pathPart).replaceAll('\\', '/');
    return decoded + anchor;
  }

  /// spine 路径（OPF 相对）→ 绝对文件；找不到时做大小写不敏感回退。
  File? chapterFile(String spineHref) {
    final plain = spineHref.split('#').first;
    var f = File(_joinFs(opfDir.path, plain));
    if (f.existsSync()) return f;
    return _locate([_joinPosix(_opfRelDir, plain)]);
  }

  /// 目录条目 → spine 序号（-1 表示未找到）。
  int spineIndexOf(TocEntry entry) {
    final plain = entry.href.split('#').first.toLowerCase();
    for (var i = 0; i < spine.length; i++) {
      if (spine[i].split('#').first.toLowerCase() == plain) return i;
    }
    return -1;
  }

  /// 当前 spine 章节对应的目录条目（无则 null）。
  TocEntry? tocEntryFor(String spineHref) {
    final plain = spineHref.split('#').first.toLowerCase();
    for (final t in toc) {
      if (t.href.split('#').first.toLowerCase() == plain) return t;
    }
    return null;
  }

  /// 相对某章节文件解析链接/图片路径 → 包内绝对路径。
  String resolveFromChapter(String chapterSpineHref, String rel) {
    final base = chapterSpineHref.split('#').first;
    final baseDir = base.contains('/') ? base.substring(0, base.lastIndexOf('/')) : '';
    final parts = _joinPosix(baseDir, rel).split('/');
    final out = <String>[];
    for (final p in parts) {
      if (p.isEmpty || p == '.') continue;
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(p);
    }
    return _joinFs(_joinFs(tempDir.path, _opfRelDir), out.join('/'));
  }

  File? _locate(List<String> relPaths) {
    for (final rel in relPaths) {
      final direct = File(_joinFs(tempDir.path, rel));
      if (direct.existsSync()) return direct;
      // 大小写不敏感回退
      final parts = rel.split('/');
      var dir = tempDir;
      var ok = true;
      for (var i = 0; i < parts.length - 1; i++) {
        final next = _findChildDir(dir, parts[i]);
        if (next == null) {
          ok = false;
          break;
        }
        dir = next;
      }
      if (!ok) continue;
      final name = parts.last.toLowerCase();
      for (final e in dir.listSync()) {
        if (e is File &&
            e.path.split(Platform.pathSeparator).last.toLowerCase() == name) {
          return e;
        }
      }
    }
    return null;
  }

  Directory? _findChildDir(Directory dir, String name) {
    final lower = name.toLowerCase();
    for (final e in dir.listSync()) {
      if (e is Directory &&
          e.path.split(Platform.pathSeparator).last.toLowerCase() == lower) {
        return e;
      }
    }
    return null;
  }

  String _readText(File f) =>
      utf8.decode(f.readAsBytesSync(), allowMalformed: true);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // 文件占用等情况：留给系统临时目录清理
    }
  }

  // ——— 工具 ———

  /// package:html 中带命名空间的属性（如 xlink:href、epub:type）的键不是
  /// 普通字符串，直接 attributes['xlink:href'] 查不到；按 toString 匹配。
  static String? qualifiedAttr(dom.Element e, String name) {
    for (final k in e.attributes.keys) {
      if (k.toString() == name) return e.attributes[k];
    }
    return null;
  }

  static Iterable<xml.XmlElement> allElements(
    xml.XmlNode node, {
    bool recursive = true,
  }) sync* {
    for (final c in node.childElements) {
      yield c;
      if (recursive) yield* allElements(c);
    }
  }

  static void _extractZip(Uint8List bytes, Directory dest) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      var name = entry.name.replaceAll('\\', '/');
      while (name.startsWith('/')) {
        name = name.substring(1);
      }
      final parts = name.split('/')
        ..removeWhere((p) => p.isEmpty || p == '.');
      if (parts.isEmpty || parts.any((p) => p == '..')) continue; // 防 zip slip
      var target = dest;
      for (var i = 0; i < parts.length - 1; i++) {
        target = Directory(_joinFs(target.path, parts[i]));
        target.createSync(recursive: true);
      }
      File(_joinFs(target.path, parts.last))
          .writeAsBytesSync(entry.content as List<int>);
    }
  }

  static String _joinPosix(String base, String child) {
    if (base.isEmpty || base == '/') return child;
    return '$base/$child';
  }

  static String _joinFs(String base, String rel) {
    final clean = rel.replaceAll('/', Platform.pathSeparator);
    return base.endsWith(Platform.pathSeparator)
        ? base + clean
        : '$base${Platform.pathSeparator}$clean';
  }
}
