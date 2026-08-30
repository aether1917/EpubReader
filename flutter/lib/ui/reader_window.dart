import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:html/dom.dart' as dom;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../epub/book.dart';
import '../epub/chapter_renderer.dart';
import 'file_association.dart';
import 'window_util.dart';

/// 阅读窗口：MD3 界面 + 章节渲染 + 窗口高度自适应内容。
class ReaderWindow extends StatefulWidget {
  const ReaderWindow({super.key, required this.book, this.startError});

  final EpubBook? book;

  /// 打开书籍失败时的错误信息（book 为 null 时显示错误页）。
  final String? startError;

  @override
  State<ReaderWindow> createState() => _ReaderWindowState();
}

class _ReaderWindowState extends State<ReaderWindow> with WindowListener {
  static const double _headerHeight = 52;
  static const double _progressHeight = 2;
  static const double _contentMaxWidth = 780;
  static const double _minWindowHeight = 480;

  EpubBook? _book;
  String? _error;
  int _index = -1;
  double _fontSize = 17;
  bool _userResized = false;
  bool _fitting = false;
  String _windowTitle = 'EpubReader';

  final ScrollController _scroll = ScrollController();
  final GlobalKey _contentKey = GlobalKey();
  final MenuController _tocMenu = MenuController();

  Timer? _fitPollTimer;
  Timer? _fitDebounce;
  Timer? _resizeEventDebounce;

  // ——— 渲染缓存：组件树（按 章节|字号|主题）+ 解析 DOM（按文件路径）———
  // 避免 resize/重建时反复读盘、解析、构树；页签切换时同章同字号直接复用。
  final Map<String, List<Widget>> _renderCache = {};
  final Map<String, ChapterRenderer> _renderOwners = {};
  final Map<String, dom.Document> _docCache = {};
  static const int _renderCacheMax = 3;
  static const int _docCacheMax = 4;
  DateTime _lastProgrammaticFit = DateTime.fromMillisecondsSinceEpoch(0);
  Size _lastWindowSize = Size.zero;
  int _fitPolls = 0;
  int _stableCount = 0;
  double _lastMeasuredContentH = -1;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _book = widget.book;
    _error = widget.startError;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await windowManager.setPreventClose(true);
      await _restoreOrCenter();
      if (_book != null && mounted) {
        _openChapter(0);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _fitPollTimer?.cancel();
    _fitDebounce?.cancel();
    _resizeEventDebounce?.cancel();
    _clearRenderCache();
    _scroll.dispose();
    _book?.dispose();
    super.dispose();
  }

  void _clearRenderCache() {
    final owners = List.of(_renderOwners.values);
    _renderCache.clear();
    _renderOwners.clear();
    _docCache.clear();
    if (owners.isEmpty) return;
    // 等当前帧的元素树 detached 后再释放手势识别器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in owners) {
        r.dispose();
      }
    });
  }

  void _cacheRender(String key, List<Widget> widgets, ChapterRenderer owner) {
    _renderCache.remove(key);
    _renderCache[key] = widgets;
    _renderOwners.remove(key);
    _renderOwners[key] = owner;
    while (_renderCache.length > _renderCacheMax) {
      final oldest = _renderCache.keys.first;
      _renderCache.remove(oldest);
      final o = _renderOwners.remove(oldest);
      if (o != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => o.dispose());
      }
    }
  }

  void _cacheDoc(String path, dom.Document doc) {
    _docCache.remove(path);
    _docCache[path] = doc;
    while (_docCache.length > _docCacheMax) {
      _docCache.remove(_docCache.keys.first);
    }
  }

  /// 后台 isolate 预解析下一章，翻页时省去读盘+解析等待。
  void _prefetchNextDom() {
    if (_book == null) return;
    final next = _index + 1;
    final spine = _safeBook.spine;
    if (next < 0 || next >= spine.length) return;
    final f = _safeBook.chapterFile(spine[next]);
    if (f == null || !f.existsSync() || _docCache.containsKey(f.path)) return;
    final path = f.path;
    Isolate.run(() => ChapterRenderer.parseChapter(File(path))).then((doc) {
      if (doc != null && mounted && !_docCache.containsKey(path)) {
        _cacheDoc(path, doc);
      }
    }).catchError((_) {});
  }

  // ——— 窗口生命周期 ———

  @override
  void onWindowClose() async {
    try {
      AppSettings.saveBounds(await windowManager.getBounds());
    } catch (_) {}
    await windowManager.destroy();
  }

  Future<void> _restoreOrCenter() async {
    final area = await WindowUtil.workArea();
    final defaultW = math.max(800.0, area.width * 0.7);
    final defaultH = math.max(600.0, area.height * 0.8);
    Rect bounds = Rect.fromLTWH(
      area.left + (area.width - defaultW) / 2,
      area.top + (area.height - defaultH) / 2,
      defaultW,
      defaultH,
    );
    final saved = AppSettings.loadBounds();
    if (saved != null && saved.width >= 320 && saved.height >= 320) {
      final screens = await WindowUtil.allScreensBounds();
      if (screens.overlaps(saved)) bounds = saved;
    }
    await windowManager.setBounds(bounds);
    await windowManager.setTitle(_windowTitle);
    _lastWindowSize = bounds.size;
    await windowManager.show();
    await windowManager.focus();
  }

  // ——— 窗口尺寸事件驱动（onWindowResize + 去抖），区分程序化与手动调整 ———

  @override
  void onWindowResize() {
    // 拖拽缩放期间事件密集，合并为停顿后的单次处理
    _resizeEventDebounce?.cancel();
    _resizeEventDebounce =
        Timer(const Duration(milliseconds: 150), _handleWindowSizeChanged);
  }

  Future<void> _handleWindowSizeChanged() async {
    if (!mounted) return;
    final size = await windowManager.getSize();
    if (size == Size.zero) return;
    final changed = _lastWindowSize != Size.zero && size != _lastWindowSize;
    final sinceFit =
        DateTime.now().difference(_lastProgrammaticFit).inMilliseconds;
    if (changed && sinceFit > 1200) {
      if (!_userResized) {
        setState(() => _userResized = true);
      }
      if (size.width != _lastWindowSize.width) _scheduleFontAdapt();
    }
    _lastWindowSize = size;
  }

  void _scheduleFontAdapt() {
    _fitDebounce?.cancel();
    _fitDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || _lastWindowSize.width <= 0) return;
      final newSize = (12 + _lastWindowSize.width / 110).clamp(14.0, 26.0);
      if ((newSize - _fontSize).abs() >= 0.5) {
        setState(() => _fontSize = newSize);
      }
    });
  }

  // ——— 内容高度自适应窗口 ———

  void _startFitPolls() {
    if (_userResized) return;
    _fitPolls = 0;
    _stableCount = 0;
    _lastMeasuredContentH = -1;
    _fitPollTimer?.cancel();
    _fitPollTimer = Timer.periodic(const Duration(milliseconds: 320), (_) async {
      if (!mounted || _userResized) {
        _fitPollTimer?.cancel();
        return;
      }
      await _fitWindowToContent();
      if (++_fitPolls >= 20 || _stableCount >= 2) _fitPollTimer?.cancel();
    });
  }

  Future<void> _fitWindowToContent() async {
    if (_fitting || !mounted || _userResized) return;
    final ctx = _contentKey.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final contentH = box.size.height;
    if (contentH <= 0) return;

    if ((contentH - _lastMeasuredContentH).abs() < 1) {
      _stableCount++;
    } else {
      _stableCount = 0;
    }
    _lastMeasuredContentH = contentH;

    final area = await WindowUtil.workArea();
    final chrome = WindowUtil.titleBarChromeHeight().toDouble();
    final desired = (contentH + _headerHeight + _progressHeight + 28 + chrome)
        .clamp(_minWindowHeight, area.height);

    final cur = await windowManager.getSize();
    final pos = await windowManager.getPosition();
    if ((desired - cur.height).abs() < 3) return;

    _fitting = true;
    try {
      var y = pos.dy;
      if (y + desired > area.bottom) {
        y = math.max(area.top, area.bottom - desired);
      }
      _lastProgrammaticFit = DateTime.now();
      await windowManager.setSize(Size(cur.width, desired));
      await windowManager.setPosition(Offset(pos.dx, y));
      _lastWindowSize = Size(cur.width, desired);
    } finally {
      _fitting = false;
    }
  }

  // ——— 章节导航 ———

  EpubBook get _safeBook => _book!;

  void _openChapter(int index, {String? anchor}) {
    if (_book == null || index < 0 || index >= _safeBook.spine.length) return;
    setState(() {
      _index = index;
      _windowTitle = 'EpubReader — ${_fileName()}';
    });
    windowManager.setTitle(_windowTitle);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (anchor != null) {
      _scheduleAnchorJump(anchor);
    } else {
      _startFitPolls();
    }
    _prefetchNextDom();
  }

  String _fileName() {
    final p = _book?.sourcePath ?? '';
    return p.replaceAll('\\', '/').split('/').last;
  }

  void _goPrev() {
    if (_index > 0) _openChapter(_index - 1);
  }

  void _goNext() {
    if (_book != null && _index < _safeBook.spine.length - 1) {
      _openChapter(_index + 1);
    }
  }

  /// 解析章节内相对链接 → 包内 posix 路径。
  String _resolvePkgPath(String href) {
    final base = _safeBook.spine[_index];
    final baseDir =
        base.contains('/') ? base.substring(0, base.lastIndexOf('/')) : '';
    final parts = '$baseDir/${href.split('#').first}'.split('/');
    final out = <String>[];
    for (final p in parts) {
      if (p.isEmpty || p == '.') continue;
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(p);
      }
    }
    return out.join('/');
  }

  void _onLink(String href) {
    final plain = href.split('#').first;
    final anchor = href.contains('#') ? href.split('#')[1] : null;
    if (plain.startsWith('http://') || plain.startsWith('https://')) {
      Process.run('cmd', ['/c', 'start', '', href], runInShell: true);
      return;
    }
    if (plain.isEmpty) {
      if (anchor != null) _jumpToAnchor(anchor);
      return;
    }
    final pkgPath = _resolvePkgPath(href);
    final idx = _safeBook.spine
        .indexWhere((s) => s.split('#').first.toLowerCase() == pkgPath.toLowerCase());
    if (idx >= 0) {
      _openChapter(idx, anchor: anchor);
    } else if (anchor != null) {
      _jumpToAnchor(anchor);
    }
  }

  void _jumpToAnchor(String anchor, {int attempt = 0}) {
    final ctx = GlobalObjectKey('anchor:$anchor').currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 240),
        alignment: 0.02,
      );
    } else if (attempt < 8) {
      Future.delayed(
        const Duration(milliseconds: 130),
        () => _jumpToAnchor(anchor, attempt: attempt + 1),
      );
    }
  }

  void _scheduleAnchorJump(String anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToAnchor(anchor);
    });
  }

  // ——— 打开其他书籍 ———

  Future<void> _openAnother() async {
    final file = await _pickEpub();
    if (file == null) return;
    await _loadBook(file.path);
  }

  static Future<XFile?> _pickEpub() {
    return openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'EPUB 文件', extensions: ['epub']),
      ],
    );
  }

  Future<void> _loadBook(String path) async {
    try {
      final book = EpubBook.open(path);
      final old = _book;
      _clearRenderCache();
      setState(() {
        _book = book;
        _error = null;
        _index = -1;
        _lastMeasuredContentH = -1;
      });
      old?.dispose();
      _openChapter(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('无法打开：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ——— 设为默认打开方式 ———

  Future<void> _setDefault() async {
    final msg = await FileAssociation.setAsDefault();
    if (!mounted) return;
    final goSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('默认打开方式'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('好的'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开系统设置'),
          ),
        ],
      ),
    );
    if (goSettings == true) {
      await FileAssociation.openDefaultAppsSettings();
    }
  }

  // ——— 拖放 ———

  void _onDropFiles(List<XFile> files) {
    for (final f in files) {
      if (f.path.toLowerCase().endsWith('.epub')) {
        _loadBook(f.path);
        return;
      }
    }
  }

  // ——— 构建 ———

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_book == null) {
      return _ErrorView(
        message: _error ?? '未打开书籍',
        onOpen: () async {
          final f = await _pickEpub();
          if (f != null) await _loadBook(f.path);
        },
      );
    }

    final spine = _safeBook.spine;
    final pos = _index >= 0 && spine.isNotEmpty
        ? '${_index + 1} / ${spine.length}'
        : '';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _goPrev,
        const SingleActivator(LogicalKeyboardKey.pageUp): _goPrev,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
        const SingleActivator(LogicalKeyboardKey.pageDown): _goNext,
        const SingleActivator(LogicalKeyboardKey.escape): () => windowManager.close(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _openAnother,
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragDone: (d) => _onDropFiles(d.files),
          child: Scaffold(
            body: Column(
              children: [
                _buildHeader(context, pos),
                Container(
                  height: _progressHeight,
                  color: scheme.surfaceContainerHighest,
                  child: spine.isEmpty
                      ? null
                      : LinearProgressIndicator(
                          value: (_index + 1) / spine.length,
                          minHeight: _progressHeight,
                          backgroundColor: Colors.transparent,
                        ),
                ),
                Expanded(child: _buildContent(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String pos) {
    final scheme = Theme.of(context).colorScheme;
    final spine = _safeBook.spine;
    final chapterTitle = _index >= 0 && _index < spine.length
        ? (_safeBook.tocEntryFor(spine[_index])?.title ??
            spine[_index].split('/').last)
        : '';

    return Container(
      height: _headerHeight,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一章（← / PageUp）',
              onPressed: _index > 0 ? _goPrev : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '下一章（→ / PageDown）',
              onPressed: _index < spine.length - 1 ? _goNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
            const SizedBox(width: 4),
            _buildTocMenu(context),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              pos,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '打开其他 EPUB 文件（Ctrl+O）',
              onPressed: _openAnother,
              icon: const Icon(Icons.folder_open),
            ),
            IconButton(
              tooltip: '将 EpubReader 设为 .epub 文件的默认打开方式',
              onPressed: _setDefault,
              icon: const Icon(Icons.push_pin_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTocMenu(BuildContext context) {
    final toc = _safeBook.toc;
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      controller: _tocMenu,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        maximumSize: const WidgetStatePropertyAll(Size(380, 480)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      ),
      menuChildren: [
        if (toc.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('（无目录）'),
          )
        else
          ...List.generate(toc.length, (i) {
            final entry = toc[i];
            final spineIdx = _safeBook.spineIndexOf(entry);
            final current = spineIdx >= 0 && spineIdx == _index;
            return MenuItemButton(
              onPressed: () {
                _tocMenu.close();
                _openChapter(
                  spineIdx >= 0 ? spineIdx : _index,
                  anchor:
                      entry.href.contains('#') ? entry.href.split('#')[1] : null,
                );
              },
              leadingIcon: current
                  ? Icon(Icons.check, size: 18, color: scheme.primary)
                  : const SizedBox(width: 18),
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Text(
                  '\u3000' * entry.level + entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: current ? scheme.primary : scheme.onSurface,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }),
      ],
      builder: (context, controller, child) => Tooltip(
        message: '目录：选择章节跳转',
        child: TextButton.icon(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.toc, size: 20),
          label: const Text('目录'),
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final spine = _safeBook.spine;
    List<Widget> children = const [];

    // 缓存键：章节 + 字号 + 明暗主题；命中时零解析零构树
    final cacheKey = _index >= 0 && _index < spine.length
        ? '$_index|$_fontSize|${brightness.name}'
        : '';

    if (cacheKey.isNotEmpty && _renderCache.containsKey(cacheKey)) {
      children = _renderCache.remove(cacheKey)!;
      _renderCache[cacheKey] = children; // LRU 触碰
    } else if (cacheKey.isNotEmpty) {
      final spineHref = spine[_index];
      final owner = ChapterRenderer(
        book: _safeBook,
        spineHref: spineHref,
        colorScheme: scheme,
        fontSize: _fontSize,
        contentWidth: math.min(_contentMaxWidth - 72, 760),
        onNavigate: _onLink,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

      final f = _safeBook.chapterFile(spineHref);
      if (f == null || !f.existsSync()) {
        children = [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('章节文件缺失：$spineHref',
                style: TextStyle(color: scheme.error)),
          ),
        ];
      } else {
        try {
          final doc = _docCache.remove(f.path) ?? ChapterRenderer.parseChapter(f);
          if (doc == null) {
            children = const [];
          } else {
            _cacheDoc(f.path, doc);
            children = owner.renderNodes(doc.body!.nodes);
          }
        } catch (e) {
          children = [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('本章内容渲染失败：$e',
                  style: TextStyle(color: scheme.error)),
            ),
          ];
        }
      }
      _cacheRender(cacheKey, children, owner);
    }

    final hPad = math.max(
      24.0,
      (_lastWindowSize.width - _contentMaxWidth) / 2,
    );

    return RepaintBoundary(
      child: SelectionArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 28),
          child: Column(
            key: _contentKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// 打开失败 / 无书时的错误页。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onOpen});

  final String message;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 56, color: scheme.primary),
              const SizedBox(height: 16),
              Text('EpubReader', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open),
                label: const Text('打开 EPUB 文件…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
