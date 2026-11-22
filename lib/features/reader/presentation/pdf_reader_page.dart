import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../app/providers.dart';
import '../../../core/models/annotation.dart';
import '../../../core/models/book.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/tts/tts_service.dart';
import '../../library/data/library_repository.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/region_mark_layer.dart';
import 'widgets/tts_sheet.dart';

class _PdfOutlineEntry {
  const _PdfOutlineEntry({
    required this.title,
    required this.pageNumber,
    required this.depth,
  });

  final String title;
  final int pageNumber;
  final int depth;
}

/// First Phase 2 slice: a real PDF reader with page-position persistence.
///
/// EPUB/DOCX renderers are intentionally not faked here; the library only
/// offers the reader entry for formats the current engine can open.
class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

enum _PdfReaderAction { tts, bookmarks, settings }

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey _captureKey = GlobalKey();
  late final LibraryRepository _repository;
  late final PdfTextSearcher _searcher;
  late final TtsService _tts;
  final TextEditingController _searchController = TextEditingController();
  File? _file;
  Book? _book;
  Object? _error;
  Timer? _saveDebounce;
  Timer? _speechSaveDebounce;
  bool _ttsUsed = false;
  bool _progressSaveErrorShown = false;
  List<RegionAnnotation> _annotations = const [];
  bool _marking = false;
  bool _searchOpen = false;
  bool _restoringPosition = true;
  double _pageOffset = 0;
  double _zoom = 0;
  int _page = 1;
  int _totalPages = 0;
  int _ttsPageCursor = 1;
  int? _ttsShownPage;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(libraryRepositoryProvider);
    _searcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _tts = TtsService()..addListener(_onTtsChanged);
    _controller.addListener(_onViewControllerChanged);
    _load();
  }

  void _onViewControllerChanged() {
    if (!_restoringPosition) _scheduleSave();
  }

  double _currentPageOffset() {
    if (!_controller.isReady) return _pageOffset;
    final layouts = _controller.layout.pageLayouts;
    if (_page < 1 || _page > layouts.length) return 0;
    final pageRect = layouts[_page - 1];
    if (pageRect.height <= 0) return 0;
    final visible = _controller.visibleRect;
    return ((visible.top - pageRect.top) / pageRect.height)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Future<void> _restoreReaderPosition() async {
    if (!_controller.isReady) {
      _restoringPosition = false;
      return;
    }
    try {
      if (_zoom.isFinite && _zoom > 0) {
        await _controller.setZoom(
          _controller.viewSize.center(Offset.zero),
          _zoom.clamp(0.5, _controller.maxScale).toDouble(),
          duration: Duration.zero,
        );
      } else {
        _zoom = _controller.currentZoom;
      }
    } catch (_) {
      _restoringPosition = false;
      return;
    }
    await _restorePageOffset();
  }

  Future<void> _applyZoom(double zoom) async {
    if (!_controller.isReady) return;
    final safe = zoom.clamp(0.5, _controller.maxScale).toDouble();
    await _controller.setZoom(
      _controller.viewSize.center(Offset.zero),
      safe,
      duration: Duration.zero,
    );
    if (!mounted) return;
    setState(() => _zoom = safe);
    await _repository.saveReaderSetting('reader.pdf.zoom', safe.toString());
  }

  Future<void> _showPdfSettings() async {
    var sheetZoom = _controller.isReady ? _controller.currentZoom : _zoom;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final zoom = sheetZoom;
          final sliderMax = zoom > 3 ? zoom : 3.0;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PDF 阅读设置',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('缩放 ${zoom.toStringAsFixed(2)}×'),
                  Slider(
                    value: zoom.clamp(0.5, sliderMax).toDouble(),
                    min: 0.5,
                    max: sliderMax,
                    divisions: 20,
                    onChanged: (value) {
                      sheetZoom = value;
                      setSheetState(() {});
                      unawaited(_applyZoom(value));
                    },
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _controller.isReady
                            ? () {
                                sheetZoom = _controller.coverScale;
                                setSheetState(() {});
                                unawaited(_applyZoom(sheetZoom));
                              }
                            : null,
                        icon: const Icon(Icons.fit_screen_rounded, size: 18),
                        label: const Text('适应宽度'),
                      ),
                      TextButton.icon(
                        onPressed: _controller.isReady
                            ? () {
                                sheetZoom =
                                    _controller.alternativeFitScale ??
                                    _controller.coverScale;
                                setSheetState(() {});
                                unawaited(_applyZoom(sheetZoom));
                              }
                            : null,
                        icon: const Icon(
                          Icons.picture_in_picture_rounded,
                          size: 18,
                        ),
                        label: const Text('适应页面'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '缩放会单独保存，重新打开 PDF 时恢复。',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _restorePageOffset() async {
    if (!mounted || !_controller.isReady) {
      _restoringPosition = false;
      return;
    }
    try {
      final offset = _pageOffset.clamp(0.0, 1.0).toDouble();
      if (offset > 0.001) {
        final layouts = _controller.layout.pageLayouts;
        if (_page >= 1 && _page <= layouts.length) {
          await _controller.goToPage(
            pageNumber: _page,
            duration: Duration.zero,
          );
          final pageRect = layouts[_page - 1];
          await _controller.goToPosition(
            documentOffset: Offset(
              pageRect.left,
              pageRect.top + pageRect.height * offset,
            ),
            duration: Duration.zero,
          );
        }
      }
    } finally {
      _restoringPosition = false;
    }
  }

  void _onSearchChanged() {
    final index = _searcher.currentIndex;
    if (index != null && index < _searcher.matches.length) {
      final page = _searcher.matches[index].pageNumber;
      if (page != _page) {
        _page = page;
        _scheduleSave();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _speechSaveDebounce?.cancel();
    _controller.removeListener(_onViewControllerChanged);
    _tts
      ..removeListener(_onTtsChanged)
      ..dispose();
    if (_ttsUsed) unawaited(_saveSpeechProgress().catchError((_) {}));
    _searcher.removeListener(_onSearchChanged);
    _searcher.dispose();
    _searchController.dispose();
    if (_page > 0 && _totalPages > 0) {
      unawaited(
        _repository
            .saveProgress(
              widget.bookId,
              pageNumber: _page,
              totalPages: _totalPages,
              pageOffset: _currentPageOffset(),
            )
            .catchError((_) {}),
      );
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final book = await _repository.findById(widget.bookId);
      if (book == null) {
        throw StateError('这本书已不在书库中');
      }
      if (book.format != BookFormat.pdf) {
        throw StateError('当前阅读器只支持 PDF；EPUB/DOCX 将在后续阶段接入');
      }
      final progress = await _repository.getProgress(book.id);
      final settings = await _repository.getReaderSettings();
      final annotations = await _repository.listAnnotations(book.id);
      final file = ref
          .read(appServicesProvider)
          .paths
          .resolveRelative(book.relativePath);
      if (!await file.exists()) {
        throw StateError('书籍文件不存在');
      }
      // Keep PDFium out of the library-only startup path. Initializing here
      // pays native memory only when a PDF is actually opened.
      await pdfrxFlutterInitialize();
      await _repository.markOpened(book.id);
      if (!mounted) return;
      setState(() {
        _book = book;
        _file = file;
        _page = progress?.pageNumber ?? 1;
        _pageOffset = progress?.pageOffset ?? 0;
        _zoom = double.tryParse(settings['reader.pdf.zoom'] ?? '') ?? 0;
        _annotations = annotations;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _openTts() async {
    _ttsUsed = true;
    if (!_controller.isReady || _totalPages <= 0) return;
    var page = _page;
    String? text;
    while (page <= _totalPages) {
      final pageText = await _searcher.loadText(pageNumber: page);
      final candidate = pageText?.fullText.trim() ?? '';
      if (candidate.isNotEmpty) {
        text = candidate;
        break;
      }
      page++;
    }
    if (text == null) {
      _message('当前页没有文字层；扫描版 PDF 暂不支持朗读');
      return;
    }
    _ttsPageCursor = page;
    _ttsShownPage = page;
    await _tts.loadSegments([
      TtsSegment(text: text, pageNumber: page),
    ], nextSegmentLoader: _loadNextPdfSegment);
    if (!mounted) return;
    await showTtsSheet(context, _tts);
  }

  Future<TtsSegment?> _loadNextPdfSegment() async {
    var page = _ttsPageCursor + 1;
    while (page <= _totalPages) {
      final pageText = await _searcher.loadText(pageNumber: page);
      final text = pageText?.fullText.trim() ?? '';
      _ttsPageCursor = page;
      if (text.isNotEmpty) {
        return TtsSegment(text: text, pageNumber: page);
      }
      page++;
    }
    return null;
  }

  void _onTtsChanged() {
    final page = _tts.currentSegment?.pageNumber;
    if (!mounted) return;
    if (page == null) {
      if (_ttsUsed) _scheduleSpeechSave();
      return;
    }
    if (page == _ttsShownPage || page == _page) return;
    _ttsShownPage = page;
    unawaited(_goToPage(page));
    _scheduleSpeechSave();
  }

  void _scheduleSpeechSave() {
    if (!_ttsUsed) return;
    _speechSaveDebounce?.cancel();
    _speechSaveDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_saveSpeechProgress().catchError((_) {})),
    );
  }

  Future<void> _saveSpeechProgress() async {
    if (!_ttsUsed || !_controller.isReady) return;
    await _repository.saveSpeechProgress(
      widget.bookId,
      anchorJson: jsonEncode({'page': _page, 'offset': _currentPageOffset()}),
      percent: _totalPages <= 0
          ? 0
          : (_page / _totalPages).clamp(0.0, 1.0).toDouble(),
      mode: 'pdf',
    );
  }

  Future<void> _addBookmark() async {
    await _repository.createBookmark(
      bookId: widget.bookId,
      pageNumber: _page,
      pageOffset: _currentPageOffset(),
      label: '第 $_page 页',
    );
    if (mounted) _message('已添加书签');
  }

  void _jumpBookmark(Bookmark bookmark) {
    final page = bookmark.pageNumber;
    if (page == null) return;
    unawaited(_goToPage(page));
  }

  Future<void> _showBookmarks() async {
    await showBookmarksSheet(
      context: context,
      bookId: widget.bookId,
      currentLabel: '第 $_page 页',
      onAddCurrent: _addBookmark,
      onJump: _jumpBookmark,
    );
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
    final changed = _page != page;
    _page = page;
    _scheduleSave();
    if (changed && mounted) setState(() {});
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    if (_restoringPosition || _totalPages <= 0 || _page <= 0) return;
    try {
      await _repository.saveProgress(
        widget.bookId,
        pageNumber: _page,
        totalPages: _totalPages,
        pageOffset: _currentPageOffset(),
      );
      _progressSaveErrorShown = false;
    } catch (error) {
      if (mounted && !_progressSaveErrorShown) {
        _progressSaveErrorShown = true;
        _message('阅读位置保存失败：$error');
      }
    }
  }

  Future<void> _close() async {
    _saveDebounce?.cancel();
    await _save();
    if (mounted) {
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(storageStatsProvider);
      context.pop();
    }
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _searcher.resetTextSearch();
      _searchController.clear();
    }
    setState(() => _searchOpen = !_searchOpen);
  }

  void _runSearch(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      _searcher.resetTextSearch();
      setState(() {});
      return;
    }
    _searcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
    setState(() {});
  }

  PreferredSizeWidget _buildSearchBar(ThemeData theme) {
    final matches = _searcher.matches.length;
    final current = _searcher.currentIndex;
    final status = _searchController.text.trim().isEmpty
        ? '输入关键词后按回车'
        : _searcher.isSearching
        ? '搜索中… 已找到 $matches 个结果'
        : matches == 0
        ? '没有找到结果'
        : '${current == null ? 1 : current + 1} / $matches 个结果';
    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('pdf-search-input'),
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _runSearch,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '在本书中搜索',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('pdf-search-prev'),
                    tooltip: '上一个结果',
                    onPressed: matches > 0
                        ? () => unawaited(_searcher.goToPrevMatch())
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    key: const Key('pdf-search-next'),
                    tooltip: '下一个结果',
                    onPressed: matches > 0
                        ? () => unawaited(_searcher.goToNextMatch())
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭搜索',
                    onPressed: _toggleSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  status,
                  key: const Key('pdf-search-status'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goToPage(int pageNumber) async {
    if (_totalPages <= 0) return;
    final target = pageNumber.clamp(1, _totalPages);
    try {
      await _controller.goToPage(pageNumber: target);
    } catch (error) {
      if (mounted) _message('跳转失败：$error');
      return;
    }
    if (!mounted) return;
    setState(() => _page = target);
    _scheduleSave();
  }

  Future<void> _showPageJump() async {
    if (_totalPages <= 0) return;
    var input = '$_page';
    final target = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('跳转页码'),
        content: TextFormField(
          key: const Key('pdf-page-input'),
          initialValue: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '输入 1–$_totalPages'),
          onChanged: (value) => input = value,
          onFieldSubmitted: (value) {
            final page = int.tryParse(value);
            if (page != null) Navigator.pop(dialogContext, page);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('pdf-page-jump-confirm'),
            onPressed: () {
              final page = int.tryParse(input);
              if (page != null) Navigator.pop(dialogContext, page);
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await _goToPage(target);
  }

  Future<void> _showOutline() async {
    if (!_controller.isReady) return;
    List<PdfOutlineNode> outline;
    try {
      outline =
          await _controller.useDocument((document) => document.loadOutline()) ??
          const [];
    } catch (error) {
      if (mounted) _message('读取 PDF 目录失败：$error');
      return;
    }
    if (!mounted) return;

    final entries = <_PdfOutlineEntry>[];
    void collect(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        final destination = node.dest;
        if (destination != null) {
          entries.add(
            _PdfOutlineEntry(
              title: node.title.trim().isEmpty ? '（无标题）' : node.title,
              pageNumber: destination.pageNumber,
              depth: depth,
            ),
          );
        }
        if (node.children.isNotEmpty) collect(node.children, depth + 1);
      }
    }

    collect(outline, 0);
    if (entries.isEmpty) {
      _message('这本 PDF 没有可用目录');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.65,
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                key: Key(
                  'pdf-outline-${entry.pageNumber}-${entry.depth}-$index',
                ),
                contentPadding: EdgeInsets.only(
                  left: 16 + entry.depth * 16,
                  right: 16,
                ),
                title: Text(entry.title),
                subtitle: Text('第 ${entry.pageNumber} 页'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_goToPage(entry.pageNumber));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onRegionSelected(Rect normalized) async {
    setState(() => _marking = false);
    final bytes = await captureRegion(_captureKey, normalized);
    if (!mounted) return;
    final note = await showAnnotationNoteDialog(context, imageBytes: bytes);
    if (note == null || !mounted) return;
    try {
      final annotation = await _repository.createAnnotation(
        bookId: widget.bookId,
        left: normalized.left,
        top: normalized.top,
        width: normalized.width,
        height: normalized.height,
        note: note,
        pageNumber: _page,
        imageBytes: bytes,
      );
      if (!mounted) return;
      setState(() => _annotations = [annotation, ..._annotations]);
      _message('已保存区域标记');
    } catch (error) {
      if (mounted) _message('保存标记失败：$error');
    }
  }

  Future<void> _showAnnotation(RegionAnnotation annotation) async {
    final image = annotation.imagePath == null
        ? null
        : ref
              .read(appServicesProvider)
              .paths
              .resolveRelative(annotation.imagePath!);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('标记 · 第 ${annotation.pageNumber ?? _page} 页'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null && image.existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(image, width: 340, fit: BoxFit.contain),
                ),
              const SizedBox(height: 12),
              SelectableText(
                annotation.note.isEmpty ? '（无备注）' : annotation.note,
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('yyyy-MM-dd HH:mm')
                    .format(annotation.createdAt.toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = _book;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回书库',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: book == null
            ? const Text('阅读')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    book.author.isEmpty ? book.format.label : book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: _totalPages > 0 ? _toggleSearch : null,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: _totalPages > 0 ? _showOutline : null,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
          PopupMenuButton<_PdfReaderAction>(
            tooltip: '更多阅读工具',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              switch (action) {
                case _PdfReaderAction.tts:
                  unawaited(_openTts());
                case _PdfReaderAction.bookmarks:
                  unawaited(_showBookmarks());
                case _PdfReaderAction.settings:
                  unawaited(_showPdfSettings());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PdfReaderAction.tts,
                child: ListTile(
                  leading: Icon(Icons.headphones_rounded),
                  title: Text('朗读'),
                ),
              ),
              PopupMenuItem(
                value: _PdfReaderAction.bookmarks,
                child: ListTile(
                  leading: Icon(Icons.bookmark_outline_rounded),
                  title: Text('书签'),
                ),
              ),
              PopupMenuItem(
                value: _PdfReaderAction.settings,
                child: ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('阅读设置'),
                ),
              ),
            ],
          ),
          if (_totalPages > 0)
            Center(
              child: Tooltip(
                message: '跳转页码',
                child: TextButton(
                  key: const Key('reader-page-indicator'),
                  onPressed: _showPageJump,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.65,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '$_page / $_totalPages',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
        ],
        bottom: _searchOpen ? _buildSearchBar(theme) : null,
      ),
      body: _buildBody(theme),
      floatingActionButton: _file == null
          ? null
          : FloatingActionButton.small(
              tooltip: _marking ? '取消框选' : '标记区域',
              onPressed: () => setState(() => _marking = !_marking),
              child: Icon(
                _marking ? Icons.close_rounded : Icons.crop_free_rounded,
              ),
            ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('无法打开这本书', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(
                '$_error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: const Text('返回书库'),
              ),
            ],
          ),
        ),
      );
    }
    final file = _file;
    if (file == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RegionMarkLayer(
      boundaryKey: _captureKey,
      marking: _marking,
      annotations: _annotations
          .where((annotation) => annotation.pageNumber == _page)
          .toList(),
      onSelected: _onRegionSelected,
      onAnnotationTap: _showAnnotation,
      onCancel: () => setState(() => _marking = false),
      child: PdfViewer.file(
        file.path,
        controller: _controller,
        initialPageNumber: _page,
        params: PdfViewerParams(
          backgroundColor: theme.scaffoldBackgroundColor,
          margin: 12,
          // Bound off-screen prefetch and rendered page images. The default
          // pdfrx cache is 100 MB; a 200 MB PDF should not reserve that on top
          // of Flutter and PDFium memory.
          maxImageBytesCachedOnMemory: 32 * 1024 * 1024,
          horizontalCacheExtent: 0.5,
          verticalCacheExtent: 0.5,
          pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
          textSelectionParams: const PdfTextSelectionParams(enabled: false),
          onPageChanged: _onPageChanged,
          onViewerReady: (document, controller) {
            _totalPages = controller.pageCount;
            if (_page > _totalPages) _page = _totalPages;
            if (mounted) setState(() {});
            unawaited(_restoreReaderPosition());
          },
        ),
      ),
    );
  }
}
