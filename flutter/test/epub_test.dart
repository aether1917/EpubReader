import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_reader/epub/book.dart';
import 'package:epub_reader/epub/chapter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个最小但结构完整的 EPUB（NCX 目录 + nav.xhtml + 图片）。
List<int> _buildTestEpub() {
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode('''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>'''),
    'OEBPS/content.opf': utf8.encode('''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试之书</dc:title>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>'''),
    'OEBPS/toc.ncx': utf8.encode('''<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head/><docTitle><text>测试之书</text></docTitle>
  <navMap>
    <navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="ch1.xhtml"/></navPoint>
    <navPoint id="n2" playOrder="2"><navLabel><text>第二章</text></navLabel><content src="ch2.xhtml#sec"/></navPoint>
  </navMap>
</ncx>'''),
    'OEBPS/ch1.xhtml': utf8.encode('''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c1</title></head><body>
<h1 id="top">第一章</h1>
<p>段落一，包含 <strong>粗体</strong>、<em>斜体</em> 与 <a href="ch2.xhtml#sec">链接</a>。</p>
<blockquote>引用内容</blockquote>
<ul><li>条目甲</li><li>条目乙</li></ul>
<table><tr><th>列A</th><th>列B</th></tr><tr><td>1</td><td>2</td></tr></table>
<pre><code>int x = 1;</code></pre>
<hr/>
<p><img src="images/pic.png" alt="图片"/></p>
</body></html>'''),
    'OEBPS/ch2.xhtml': utf8.encode('''<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c2</title></head><body>
<h1 id="sec">第二章</h1><p>结束章。</p>
</body></html>'''),
    'OEBPS/images/pic.png': _fakePng(),
  };

  final archive = Archive();
  files.forEach((name, data) {
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return ZipEncoder().encode(archive);
}

/// 1x1 红色 PNG。
Uint8List _fakePng() => Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
      0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
      0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File epubFile;
  setUpAll(() {
    epubFile = File(
        '${Directory.systemTemp.path}/epub_reader_test_${DateTime.now().millisecondsSinceEpoch}.epub')
      ..writeAsBytesSync(_buildTestEpub());
  });

  tearDownAll(() {
    if (epubFile.existsSync()) epubFile.deleteSync();
  });

  test('EpubBook 解析 container/OPF/spine/NCX', () {
    final book = EpubBook.open(epubFile.path);
    addTearDown(book.dispose);

    expect(book.title, '测试之书');
    expect(book.spine, ['ch1.xhtml', 'ch2.xhtml']);
    expect(book.toc.length, 2);
    expect(book.toc[0].title, '第一章');
    expect(book.toc[0].href, 'ch1.xhtml');
    expect(book.toc[1].href, 'ch2.xhtml#sec');
    expect(book.toc[1].level, 0);

    expect(book.spineIndexOf(book.toc[1]), 1);
    expect(book.tocEntryFor('ch1.xhtml')?.title, '第一章');

    final f = book.chapterFile('ch1.xhtml');
    expect(f, isNotNull);
    expect(f!.existsSync(), isTrue);
    final img = book.resolveFromChapter('ch1.xhtml', 'images/pic.png');
    expect(File(img).existsSync(), isTrue, reason: '图片路径应可解析：$img');
  });

  test('ChapterRenderer 渲染章节组件（标题/段落/引用/列表/表格/代码/图片）', () {
    final book = EpubBook.open(epubFile.path);
    addTearDown(book.dispose);

    final renderer = ChapterRenderer(
      book: book,
      spineHref: 'ch1.xhtml',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6A4F)),
      fontSize: 17,
      contentWidth: 700,
      onNavigate: (_) {},
    );
    addTearDown(renderer.dispose);

    final widgets = renderer.renderFile(book.chapterFile('ch1.xhtml')!);
    expect(widgets, isNotEmpty);
    expect(renderer.imageCount, 1, reason: '应解析出 1 张图片');
  });

  test('normalizeHref 保留片段并解码', () {
    expect(EpubBook.normalizeHref('a%20b/c.xhtml#frag'), 'a b/c.xhtml#frag');
    expect(EpubBook.normalizeHref('x/y.xhtml'), 'x/y.xhtml');
  });
}
