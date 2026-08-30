import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'book.dart';

/// 章节渲染器：把 XHTML DOM 翻译成 Material 3 阅读排版组件。
///
/// 块级元素映射为 Flutter 布局组件；行内内容聚合为 [TextSpan] 树；
/// 样式随 [ColorScheme] 与 [fontSize] 适配浅色/深色主题与窗口宽度。
class ChapterRenderer {
  ChapterRenderer({
    required this.book,
    required this.spineHref,
    required this.colorScheme,
    required this.fontSize,
    required this.contentWidth,
    required this.onNavigate,
  });

  final EpubBook book;

  /// 当前章节的 spine 路径（用于解析相对链接/图片）。
  final String spineHref;
  final ColorScheme colorScheme;
  final double fontSize;
  final double contentWidth;

  /// 链接点击回调，传入原始 href（含可能的 #片段）。
  final void Function(String href) onNavigate;

  int imageCount = 0;
  final List<TapGestureRecognizer> _recognizers = [];

  // ——— 排版度量 ———

  static const double _lineHeight = 1.85;
  static const double _imageMaxRatio = 0.92;

  TextStyle get _bodyStyle => TextStyle(
        fontSize: fontSize,
        height: _lineHeight,
        color: colorScheme.onSurface,
        fontFamily: 'Georgia',
        fontFamilyFallback: const ['Times New Roman', 'SimSun', 'Microsoft YaHei'],
      );

  TextStyle get _secondaryStyle =>
      _bodyStyle.copyWith(color: colorScheme.onSurfaceVariant);

  TextStyle _headingStyle(int level) {
    const scales = [1.7, 1.45, 1.28, 1.14, 1.06, 1.0];
    return _bodyStyle.copyWith(
      fontSize: fontSize * scales[level - 1],
      height: 1.35,
      fontWeight: level <= 2 ? FontWeight.w600 : FontWeight.w500,
    );
  }

  static const _monoFamily = 'Consolas';
  static const _monoFallback = ['Courier New', 'Microsoft YaHei'];

  // ——— 入口 ———

  /// 解析章节文件并渲染为组件列表。
  List<Widget> renderFile(File file) {
    final doc = html_parser.parse(_decodeBytes(file.readAsBytesSync()));
    final body = doc.body;
    if (body == null) return const [];
    return renderNodes(body.nodes);
  }

  List<Widget> renderNodes(List<dom.Node> nodes) => _blocks(nodes, indent: 0);

  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  static String _decodeBytes(List<int> raw) {
    var bytes = raw;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ——— 块级渲染 ———

  static const _blockTags = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'div', 'section', 'article',
    'aside', 'header', 'footer', 'main', 'nav', 'figure', 'figcaption',
    'blockquote', 'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tfoot',
    'tr', 'th', 'td', 'pre', 'hr', 'dl', 'dt', 'dd', 'center', 'address',
    'details', 'summary', 'fieldset', 'form', 'caption', 'svg',
  };

  /// 一个待输出片段：element 用于回填 id 锚点。
  List<Widget> _blocks(List<dom.Node> nodes, {required int indent}) {
    final frags = <(dom.Element?, Widget)>[];
    var inlineRun = <dom.Node>[];

    void flushInline() {
      if (inlineRun.isEmpty) return;
      final spans = _inline(inlineRun, _bodyStyle);
      inlineRun = [];
      if (spans.isEmpty) return;
      frags.add((
        null,
        _pad(
          child: Text.rich(TextSpan(children: spans), style: _bodyStyle),
          bottom: fontSize * 0.45,
        ),
      ));
    }

    void add(dom.Element? e, Widget w) => frags.add((e, w));

    for (final node in nodes) {
      if (node is dom.Text) {
        if (node.text.trim().isNotEmpty) inlineRun.add(node);
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName ?? '';

      if (!_blockTags.contains(tag)) {
        inlineRun.add(node);
        continue;
      }
      flushInline();

      switch (tag) {
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          final level = int.parse(tag.substring(1));
          add(
            node,
            _pad(
              child: Text.rich(
                TextSpan(children: _inline(node.nodes, _headingStyle(level))),
                style: _headingStyle(level),
              ),
              top: level <= 2 ? fontSize * 0.9 : fontSize * 0.6,
              bottom: fontSize * 0.4,
            ),
          );
        case 'p':
          final spans = _inline(node.nodes, _bodyStyle);
          if (spans.isNotEmpty) {
            add(
              node,
              _pad(
                child: Text.rich(TextSpan(children: spans), style: _bodyStyle),
                bottom: fontSize * 0.55,
              ),
            );
          }
        case 'img':
          final w = _image(node);
          if (w != null) add(node, w);
        case 'blockquote':
          add(
            node,
            _pad(
              child: _quote(node),
              top: fontSize * 0.5,
              bottom: fontSize * 0.5,
            ),
          );
        case 'pre':
          add(node, _pad(child: _codeBlock(node), top: fontSize * 0.4, bottom: fontSize * 0.6));
        case 'hr':
          add(
            node,
            _pad(
              child: Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
              top: fontSize * 0.8,
              bottom: fontSize * 0.8,
            ),
          );
        case 'br':
          add(null, SizedBox(height: fontSize * 0.6));
        case 'ul':
          add(node, _pad(child: _list(node, ordered: false, indent: indent), bottom: fontSize * 0.55));
        case 'ol':
          add(node, _pad(child: _list(node, ordered: true, indent: indent), bottom: fontSize * 0.55));
        case 'table':
          add(node, _pad(child: _table(node), top: fontSize * 0.4, bottom: fontSize * 0.6));
        case 'svg':
          add(node, _pad(child: _svgWidget(node), bottom: fontSize * 0.5));
        case 'dl':
        case 'figure':
        case 'details':
        case 'form':
        case 'fieldset':
          add(
            node,
            _pad(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _blocks(node.nodes, indent: indent),
              ),
              top: tag == 'figure' ? fontSize * 0.5 : 0,
              bottom: fontSize * 0.5,
            ),
          );
        case 'figcaption':
          add(
            node,
            _pad(
              child: Text.rich(
                TextSpan(children: _inline(node.nodes, _secondaryStyle)),
                style: _secondaryStyle,
              ),
              bottom: fontSize * 0.5,
            ),
          );
        case 'li':
        case 'tr':
        case 'td':
        case 'th':
        case 'thead':
        case 'tbody':
        case 'tfoot':
        case 'caption':
          // 已由父级处理；散落时降级为普通容器
          for (final w in _genericContainer(node, indent: indent)) {
            add(node, w);
          }
        default:
          for (final w in _genericContainer(node, indent: indent)) {
            add(node, w);
          }
      }
    }
    flushInline();

    // 回填 id 锚点，供目录/文内链接跳转定位
    return [
      for (final (e, w) in frags)
        (e != null && e.id.isNotEmpty)
            ? KeyedSubtree(key: GlobalObjectKey('anchor:${e.id}'), child: w)
            : w,
    ];
  }

  /// div/section/article 等通用容器：纯行内内容聚合成段，否则递归布局。
  List<Widget> _genericContainer(dom.Element e, {required int indent}) {
    final hasBlockChild = e.nodes
        .any((n) => n is dom.Element && _blockTags.contains(n.localName ?? ''));
    if (!hasBlockChild) {
      final spans = _inline(e.nodes, _bodyStyle);
      if (spans.isEmpty) return const [];
      return [
        _pad(
          child: Text.rich(TextSpan(children: spans), style: _bodyStyle),
          bottom: fontSize * 0.35,
        ),
      ];
    }
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _blocks(e.nodes, indent: indent),
      ),
    ];
  }

  Widget _quote(dom.Element e) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(left: fontSize * 0.4),
      padding: EdgeInsets.symmetric(
        vertical: fontSize * 0.15,
        horizontal: fontSize * 0.8,
      ),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _blocks(e.nodes, indent: 0),
      ),
    );
  }

  Widget _codeBlock(dom.Element e) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          _trimBlankLines(e.text),
          style: TextStyle(
            fontSize: fontSize * 0.85,
            height: 1.6,
            fontFamily: _monoFamily,
            fontFamilyFallback: _monoFallback,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _list(dom.Element e, {required bool ordered, required int indent}) {
    final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
    final rows = <Widget>[];

    var i = start;
    for (final child in e.children.whereType<dom.Element>()) {
      if (child.localName != 'li') continue;
      final marker = ordered
          ? Text('${i++}.', style: _bodyStyle)
          : Text('•', style: _bodyStyle);
      rows.add(Padding(
        padding: EdgeInsets.only(
          bottom: fontSize * 0.18,
          left: indent * fontSize * 0.9,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ordered ? fontSize * 1.7 : fontSize * 0.9,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: marker,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _blocks(child.nodes, indent: indent),
              ),
            ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _table(dom.Element e) {
    final rows = <dom.Element>[];
    for (final n in e.nodes) {
      if (n is! dom.Element) continue;
      switch (n.localName) {
        case 'tr':
          rows.add(n);
        case 'thead' || 'tbody' || 'tfoot':
          for (final tr in n.children.whereType<dom.Element>()) {
            if (tr.localName == 'tr') rows.add(tr);
          }
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    final tableRows = <TableRow>[];
    for (final tr in rows) {
      final cells = tr.children
          .whereType<dom.Element>()
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .toList();
      if (cells.isEmpty) continue;
      final isHeader = cells.every((c) => c.localName == 'th');
      tableRows.add(TableRow(
        decoration: BoxDecoration(
          color: isHeader
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
              : null,
        ),
        children: [
          for (final c in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: _cellContent(c, isHeader: isHeader),
            ),
        ],
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: contentWidth),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(
            color: colorScheme.outlineVariant,
            width: 1,
            borderRadius: BorderRadius.circular(6),
          ),
          children: tableRows,
        ),
      ),
    );
  }

  Widget _cellContent(dom.Element cell, {required bool isHeader}) {
    final style = isHeader
        ? _bodyStyle.copyWith(fontWeight: FontWeight.w600)
        : _bodyStyle;
    final hasBlockChild = cell.nodes
        .any((n) => n is dom.Element && _blockTags.contains(n.localName ?? ''));
    if (hasBlockChild) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _blocks(cell.nodes, indent: 0),
      );
    }
    final spans = _inline(cell.nodes, style);
    return Text.rich(TextSpan(children: spans), style: style);
  }

  /// SVG：EPUB 封面常见 `<svg><image xlink:href="cover.jpg"/></svg>` 结构，
  /// 引用了位图时直接渲染该图片，仅纯矢量内容才显示占位框。
  Widget _svgWidget(dom.Element e) {
    final img =
        e.localName == 'image' ? e : e.querySelector('image');
    if (img != null) {
      final href =
          EpubBook.qualifiedAttr(img, 'xlink:href') ??
              EpubBook.qualifiedAttr(img, 'href') ??
              '';
      final alt = img.attributes['alt'] ?? e.querySelector('title')?.text ?? '';
      if (href.isNotEmpty && !href.startsWith('#') && !href.startsWith('data:')) {
        final w = _imageFromFile(href, alt);
        if (w != null) return w;
      }
    }
    final alt = e.attributes['alt'] ?? e.querySelector('title')?.text ?? 'SVG 图形';
    return _assetPlaceholder(icon: Icons.image_outlined, label: alt);
  }

  Widget _assetPlaceholder({required IconData icon, required String label}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: _secondaryStyle.copyWith(fontSize: fontSize * 0.8),
          ),
        ],
      ),
    );
  }

  Widget? _image(dom.Element e) {
    final src = e.attributes['src'] ?? e.attributes['data-src'];
    final alt = e.attributes['alt'] ?? '';
    if (src == null || src.isEmpty || src.startsWith('data:')) return null;
    return _imageFromFile(src, alt);
  }

  Widget? _imageFromFile(String src, String alt) {
    if (src.toLowerCase().endsWith('.svg')) {
      return _assetPlaceholder(
        icon: Icons.image_outlined,
        label: alt.isEmpty ? 'SVG 图形' : alt,
      );
    }

    final f = File(_resolveRelative(src));
    if (!f.existsSync()) {
      return _assetPlaceholder(
        icon: Icons.broken_image_outlined,
        label: alt.isEmpty ? '图片缺失' : alt,
      );
    }
    imageCount++;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: fontSize * 0.4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentWidth * _imageMaxRatio),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              f,
              fit: BoxFit.scaleDown,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _assetPlaceholder(
                icon: Icons.broken_image_outlined,
                label: alt.isEmpty ? '图片无法显示' : alt,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ——— 行内渲染 ———

  List<InlineSpan> _inline(List<dom.Node> nodes, TextStyle base) {
    final out = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = _collapseWs(node.text);
        if (text.isEmpty) continue;
        out.add(TextSpan(text: text, style: base));
      } else if (node is dom.Element) {
        out.addAll(_inlineElement(node, base));
      }
    }
    return out;
  }

  List<InlineSpan> _inlineElement(dom.Element e, TextStyle base) {
    switch (e.localName ?? '') {
      case 'a':
        final href = e.attributes['href'];
        if (href == null || href.isEmpty) return _inline(e.nodes, base);
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onNavigate(href);
        _recognizers.add(recognizer);
        return [
          TextSpan(
            style: base.copyWith(
              color: colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: colorScheme.primary.withValues(alpha: 0.5),
            ),
            children: _inline(e.nodes, base),
            recognizer: recognizer,
          ),
        ];
      case 'b' || 'strong':
        return _inline(e.nodes, base.copyWith(fontWeight: FontWeight.w700));
      case 'i' || 'em' || 'cite' || 'var' || 'dfn':
        return _inline(e.nodes, base.copyWith(fontStyle: FontStyle.italic));
      case 'u' || 'ins':
        return _inline(e.nodes, base.copyWith(decoration: TextDecoration.underline));
      case 's' || 'strike' || 'del':
        return _inline(e.nodes, base.copyWith(decoration: TextDecoration.lineThrough));
      case 'sup' || 'sub':
        return _inline(e.nodes, base.copyWith(fontSize: fontSize * 0.72));
      case 'small':
        return _inline(e.nodes, base.copyWith(fontSize: fontSize * 0.85));
      case 'code' || 'kbd' || 'samp':
        return _inline(
          e.nodes,
          base.copyWith(
            fontFamily: _monoFamily,
            fontFamilyFallback: _monoFallback,
            fontSize: base.fontSize == null ? null : base.fontSize! * 0.9,
            color: colorScheme.tertiary,
          ),
        );
      case 'mark':
        return _inline(e.nodes, base.copyWith(color: colorScheme.tertiary));
      case 'br':
        return const [TextSpan(text: '\n')];
      case 'img':
        final w = _image(e);
        if (w == null) return const [];
        return [WidgetSpan(alignment: PlaceholderAlignment.middle, child: w)];
      case 'svg':
        return [
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: _svgWidget(e)),
        ];
      default:
        return _inline(e.nodes, base);
    }
  }

  // ——— 工具 ———

  String _resolveRelative(String rel) =>
      book.resolveFromChapter(spineHref, rel);

  static String _collapseWs(String s) =>
      s.replaceAll(RegExp(r'[ \t\r\n\f\v]+'), ' ');

  static String _trimBlankLines(String s) {
    final lines = s.split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  Widget _pad({required Widget child, double top = 0, double bottom = 0}) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: child,
    );
  }
}
