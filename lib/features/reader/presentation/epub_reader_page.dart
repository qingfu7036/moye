import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../app/providers.dart';
import '../../../core/epub/epub_parser.dart';
import '../../../core/models/annotation.dart';
import '../../../core/models/book.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/tts/tts_service.dart';
import '../../library/data/library_repository.dart';
import 'widgets/epub_image_block.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/region_mark_layer.dart';
import 'widgets/tts_sheet.dart';

class _EpubSearchResult {
  const _EpubSearchResult({
    required this.chapterIndex,
    required this.blockIndex,
    required this.start,
    required this.end,
  });

  final int chapterIndex;
  final int blockIndex;
  final int start;
  final int end;
}

enum _EpubReaderAction { tts, bookmarks, settings }

class _EpubPalette {
  const _EpubPalette(this.name, this.background, this.foreground, this.muted);

  final String name;
  final Color background;
  final Color foreground;
  final Color muted;
}

const _epubPalettes = [
  _EpubPalette('雾纸', Color(0xFFF2F6F1), Color(0xFF202A24), Color(0xFF63716A)),
  _EpubPalette('暖页', Color(0xFFF1EBDD), Color(0xFF2C271E), Color(0xFF786C59)),
  _EpubPalette('夜读', Color(0xFF121815), Color(0xFFDDE6E0), Color(0xFF8B9A91)),
];

class _EpubPlacedCell {
  const _EpubPlacedCell({
    required this.cell,
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.columnSpan,
  });

  final EpubTableCell cell;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
}

class _EpubTableLayout {
  const _EpubTableLayout({
    required this.cells,
    required this.columnWidths,
    required this.rowHeights,
  });

  final List<_EpubPlacedCell> cells;
  final List<double> columnWidths;
  final List<double> rowHeights;

  double get width => columnWidths.fold(0, (sum, value) => sum + value);
  double get height => rowHeights.fold(0, (sum, value) => sum + value);

  double columnOffset(int column) =>
      columnWidths.take(column).fold(0, (sum, value) => sum + value);

  double rowOffset(int row) =>
      rowHeights.take(row).fold(0, (sum, value) => sum + value);

  double cellWidth(_EpubPlacedCell placed) => columnWidths
      .skip(placed.column)
      .take(placed.columnSpan)
      .fold(0, (sum, value) => sum + value);

  double cellHeight(_EpubPlacedCell placed) => rowHeights
      .skip(placed.row)
      .take(placed.rowSpan)
      .fold(0, (sum, value) => sum + value);
}

/// A small table layout that understands colspan/rowspan. Flutter's [Table]
/// cannot merge cells, so this measures the grid and positions each cell.
class _EpubSpanTable extends StatelessWidget {
  const _EpubSpanTable({
    required this.rows,
    required this.cellStyle,
    required this.palette,
  });

  final List<List<EpubTableCell>> rows;
  final TextStyle cellStyle;
  final _EpubPalette palette;

  static const double _padding = 6;
  static const double _minColumnWidth = 48;
  static const double _maxColumnWidth = 360;
  static const double _maxSpanWidth = 480;

  @override
  Widget build(BuildContext context) {
    final layout = _measure(rows, cellStyle, MediaQuery.textScalerOf(context));
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        children: [
          for (final placed in layout.cells)
            Positioned(
              left: layout.columnOffset(placed.column),
              top: layout.rowOffset(placed.row),
              width: layout.cellWidth(placed),
              height: layout.cellHeight(placed),
              child: Container(
                decoration: BoxDecoration(
                  color: placed.cell.isHeader
                      ? palette.muted.withValues(alpha: 0.12)
                      : palette.background,
                  border: Border.all(
                    color: palette.muted.withValues(alpha: 0.32),
                    width: 0.8,
                  ),
                ),
                padding: const EdgeInsets.all(_padding),
                child: placed.cell.text.isEmpty
                    ? const SizedBox.shrink()
                    : SelectableText(
                        placed.cell.text,
                        style: placed.cell.isHeader
                            ? cellStyle.copyWith(fontWeight: FontWeight.w700)
                            : cellStyle,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  static _EpubTableLayout _measure(
    List<List<EpubTableCell>> rows,
    TextStyle style,
    TextScaler textScaler,
  ) {
    final occupied = <int, Set<int>>{};
    final cells = <_EpubPlacedCell>[];
    var columnCount = 1;

    bool isOccupied(int row, int column) =>
        occupied[row]?.contains(column) ?? false;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      var column = 0;
      for (final cell in rows[rowIndex]) {
        while (isOccupied(rowIndex, column)) {
          column++;
        }
        final columnSpan = cell.colSpan.clamp(1, 64);
        final rowSpan = cell.rowSpan.clamp(1, rows.length - rowIndex);
        cells.add(
          _EpubPlacedCell(
            cell: cell,
            row: rowIndex,
            column: column,
            rowSpan: rowSpan,
            columnSpan: columnSpan,
          ),
        );
        for (var r = rowIndex; r < rowIndex + rowSpan; r++) {
          final occupiedColumns = occupied.putIfAbsent(r, () => <int>{});
          for (var c = column; c < column + columnSpan; c++) {
            occupiedColumns.add(c);
          }
        }
        column += columnSpan;
        if (column > columnCount) columnCount = column;
      }
    }

    final columnWidths = List<double>.filled(columnCount, _minColumnWidth);
    final spanningCells = <_EpubPlacedCell>[];
    for (final placed in cells) {
      final painter = _measurePainter(placed.cell.text, style, textScaler);
      final desired = math.min(
        placed.columnSpan == 1 ? _maxColumnWidth : _maxSpanWidth,
        math.max(_minColumnWidth, painter.width + _padding * 2),
      );
      if (placed.columnSpan == 1) {
        columnWidths[placed.column] = math.max(
          columnWidths[placed.column],
          desired,
        );
      } else {
        spanningCells.add(placed);
      }
    }
    for (final placed in spanningCells) {
      final painter = _measurePainter(placed.cell.text, style, textScaler);
      final desired = math.min(
        _maxSpanWidth,
        math.max(_minColumnWidth, painter.width + _padding * 2),
      );
      final current = columnWidths
          .skip(placed.column)
          .take(placed.columnSpan)
          .fold<double>(0, (sum, value) => sum + value);
      if (desired > current) {
        final extra = (desired - current) / placed.columnSpan;
        for (
          var c = placed.column;
          c < placed.column + placed.columnSpan;
          c++
        ) {
          columnWidths[c] += extra;
        }
      }
    }

    final rowHeights = List<double>.filled(rows.length, 28);
    for (final placed in cells) {
      final width = columnWidths
          .skip(placed.column)
          .take(placed.columnSpan)
          .fold<double>(0, (sum, value) => sum + value);
      final painter = _measurePainter(
        placed.cell.text,
        style,
        textScaler,
        maxWidth: math.max(24, width - _padding * 2),
      );
      final desired = painter.height + _padding * 2 + 1;
      if (placed.rowSpan == 1) {
        rowHeights[placed.row] = math.max(rowHeights[placed.row], desired);
      } else {
        final current = rowHeights
            .skip(placed.row)
            .take(placed.rowSpan)
            .fold<double>(0, (sum, value) => sum + value);
        if (desired > current) {
          final extra = (desired - current) / placed.rowSpan;
          for (var r = placed.row; r < placed.row + placed.rowSpan; r++) {
            rowHeights[r] += extra;
          }
        }
      }
    }

    return _EpubTableLayout(
      cells: cells,
      columnWidths: columnWidths,
      rowHeights: rowHeights,
    );
  }

  static TextPainter _measurePainter(
    String text,
    TextStyle style,
    TextScaler textScaler, {
    double? maxWidth,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth ?? double.infinity);
  }
}

class EpubReaderPage extends ConsumerStatefulWidget {
  const EpubReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends ConsumerState<EpubReaderPage> {
  static const double _baseFontSize = 19;

  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final GlobalKey _captureKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  late final LibraryRepository _repository;
  late final TtsService _tts;

  EpubDocument? _document;
  Book? _book;
  Object? _error;
  Timer? _saveDebounce;
  Timer? _speechSaveDebounce;
  bool _ttsUsed = false;
  bool _progressSaveErrorShown = false;
  int _chapterIndex = 0;
  int _initialBlock = 0;
  int _currentBlock = 0;
  int _listGeneration = 0;
  final Map<int, Offset> _activePointers = {};
  double _fontSize = 19;
  double _pinchStartDistance = 0;
  double _pinchStartFontSize = 19;
  double _trackpadStartFontSize = 19;
  double _lineHeight = 1.8;
  double _paragraphSpacing = 11;
  int _paletteIndex = 0;
  int _ttsHighlightBlock = -1;
  List<RegionAnnotation> _annotations = const [];
  bool _marking = false;
  bool _searchOpen = false;
  bool _suppressPositionUpdates = false;
  String _searchQuery = '';
  List<_EpubSearchResult> _searchResults = const [];
  int? _searchResultIndex;

  _EpubSearchResult? get _currentSearchResult {
    final index = _searchResultIndex;
    if (index == null || index < 0 || index >= _searchResults.length) {
      return null;
    }
    return _searchResults[index];
  }

  EpubChapter? get _chapter {
    final document = _document;
    if (document == null || document.chapters.isEmpty) return null;
    return document.chapters[_chapterIndex.clamp(
      0,
      document.chapters.length - 1,
    )];
  }

  @override
  void initState() {
    super.initState();
    _repository = ref.read(libraryRepositoryProvider);
    _tts = TtsService()..addListener(_onTtsChanged);
    _positions.itemPositions.addListener(_onPositions);
    _load();
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _tts
      ..removeListener(_onTtsChanged)
      ..dispose();
    _saveDebounce?.cancel();
    _speechSaveDebounce?.cancel();
    unawaited(_save().catchError((_) {}));
    if (_ttsUsed) unawaited(_saveSpeechProgress().catchError((_) {}));
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final book = await _repository.findById(widget.bookId);
      if (book == null) throw StateError('这本书已不在书库中');
      if (book.format != BookFormat.epub) {
        throw StateError('这不是 EPUB 文件');
      }
      final file = ref
          .read(appServicesProvider)
          .paths
          .resolveRelative(book.relativePath);
      if (!await file.exists()) throw StateError('书籍文件不存在');
      final bytes = await file.readAsBytes();
      final document = const EpubParser().parse(bytes);
      final progress = await _repository.getProgress(book.id);
      final settings = await _repository.getReaderSettings();
      final annotations = await _repository.listAnnotations(book.id);
      var chapter = 0;
      var block = 0;
      final anchor = progress?.anchorJson;
      if (anchor != null) {
        try {
          final decoded = jsonDecode(anchor);
          if (decoded is Map) {
            chapter = (decoded['chapter'] as num?)?.toInt() ?? 0;
            block = (decoded['block'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {
          // Ignore a corrupt anchor and start at the first chapter.
        }
      }
      await _repository.markOpened(book.id);
      if (!mounted) return;
      setState(() {
        _book = book;
        _document = document;
        final requested = document.chapters.isEmpty
            ? 0
            : chapter.clamp(0, document.chapters.length - 1);
        _chapterIndex = _firstReadableChapter(document, requested);
        _initialBlock = _chapterIndex == requested ? block : 0;
        _currentBlock = _initialBlock;
        _fontSize =
            (double.tryParse(settings['reader.epub.fontSize'] ?? '') ??
                    _fontSize)
                .clamp(15.0, 36.0);
        _lineHeight =
            (double.tryParse(settings['reader.epub.lineHeight'] ?? '') ??
                    _lineHeight)
                .clamp(1.4, 2.2);
        _paragraphSpacing =
            (double.tryParse(settings['reader.epub.paragraphSpacing'] ?? '') ??
                    _paragraphSpacing)
                .clamp(4.0, 28.0);
        final savedPalette =
            int.tryParse(settings['reader.epub.palette'] ?? '') ??
            _paletteIndex;
        _paletteIndex = savedPalette.clamp(0, _epubPalettes.length - 1);
        _annotations = annotations;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onPositions() {
    if (_suppressPositionUpdates) return;
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions.reduce((a, b) => a.index < b.index ? a : b);
    if (first.index == _currentBlock) return;
    _currentBlock = first.index;
    if (mounted) setState(() {});
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(
        _save().catchError((Object error) {
          if (mounted && !_progressSaveErrorShown) {
            _progressSaveErrorShown = true;
            _message('阅读位置保存失败：$error');
          }
        }),
      );
    });
  }

  Future<void> _save() async {
    final document = _document;
    final chapter = _chapter;
    if (document == null || chapter == null || chapter.blocks.isEmpty) return;
    final block = _currentBlock.clamp(0, chapter.blocks.length - 1);
    await _repository.saveEpubProgress(
      widget.bookId,
      chapterIndex: _chapterIndex,
      blockIndex: block,
      cfi: document.cfiFor(chapter, block),
      chapterCount: document.chapters.length,
    );
    await _repository.saveReaderSetting(
      'reader.epub.fontSize',
      _fontSize.toString(),
    );
    await _repository.saveReaderSetting(
      'reader.epub.lineHeight',
      _lineHeight.toString(),
    );
    await _repository.saveReaderSetting(
      'reader.epub.paragraphSpacing',
      _paragraphSpacing.toString(),
    );
    await _repository.saveReaderSetting(
      'reader.epub.palette',
      _paletteIndex.toString(),
    );
  }

  Future<void> _close() async {
    _saveDebounce?.cancel();
    try {
      await _save();
      _progressSaveErrorShown = false;
    } catch (error) {
      if (mounted) _message('阅读位置保存失败：$error');
    }
    if (mounted) {
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(storageStatsProvider);
      context.pop();
    }
  }

  void _goToChapter(int index) {
    final document = _document;
    if (document == null) return;
    final requested = index.clamp(0, document.chapters.length - 1);
    final next = _firstReadableChapter(document, requested);
    if (next == _chapterIndex) return;
    setState(() {
      _chapterIndex = next;
      _initialBlock = 0;
      _currentBlock = 0;
    });
    _scheduleSave();
  }

  Future<void> _openTts() async {
    _ttsUsed = true;
    final document = _document;
    if (document == null || document.chapters.isEmpty) return;
    final segments = <TtsSegment>[];
    for (
      var chapterIndex = _chapterIndex;
      chapterIndex < document.chapters.length;
      chapterIndex++
    ) {
      final blocks = document.chapters[chapterIndex].blocks;
      final start = chapterIndex == _chapterIndex ? _currentBlock : 0;
      for (var blockIndex = start; blockIndex < blocks.length; blockIndex++) {
        final text = blocks[blockIndex].text.trim();
        if (text.isEmpty) continue;
        segments.add(
          TtsSegment(
            text: text,
            chapterIndex: chapterIndex,
            blockIndex: blockIndex,
          ),
        );
      }
    }
    if (segments.isEmpty) {
      _message('当前位置没有可朗读的文本');
      return;
    }
    await _tts.initialize();
    if (!_tts.initialized) {
      _message('系统语音初始化失败：${_tts.error ?? '未知错误'}');
      return;
    }
    await _tts.loadSegments(segments);
    if (!mounted) return;
    await showTtsSheet(context, _tts);
  }

  void _onTtsChanged() {
    if (!mounted) return;
    final segment = _tts.currentSegment;
    final chapterIndex = segment?.chapterIndex;
    final blockIndex = segment?.blockIndex;
    if (chapterIndex == null || blockIndex == null) {
      if (_ttsHighlightBlock != -1) {
        setState(() => _ttsHighlightBlock = -1);
      }
      if (_ttsUsed) _scheduleSpeechSave();
      return;
    }
    if (chapterIndex != _chapterIndex) {
      _ttsHighlightBlock = blockIndex;
      _jumpToBlock(chapterIndex, blockIndex);
      return;
    }
    if (blockIndex != _ttsHighlightBlock) {
      setState(() => _ttsHighlightBlock = blockIndex);
      if (_scroll.isAttached) {
        _scroll.jumpTo(index: blockIndex, alignment: 0.05);
      }
      _scheduleSpeechSave();
    }
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
    if (!_ttsUsed) return;
    final document = _document;
    if (document == null || document.chapters.isEmpty) return;
    final chapterIndex = _chapterIndex.clamp(0, document.chapters.length - 1);
    final chapter = document.chapters[chapterIndex];
    final blockIndex = (_tts.currentSegment?.blockIndex ?? _currentBlock).clamp(
      0,
      chapter.blocks.isEmpty ? 0 : chapter.blocks.length - 1,
    );
    final percent = document.chapters.isEmpty
        ? 0.0
        : ((chapterIndex +
                      (chapter.blocks.isEmpty
                          ? 0
                          : blockIndex / chapter.blocks.length)) /
                  document.chapters.length)
              .clamp(0.0, 1.0)
              .toDouble();
    await _repository.saveSpeechProgress(
      widget.bookId,
      anchorJson: jsonEncode({
        'chapter': chapterIndex,
        'block': blockIndex,
        'cfi': document.cfiFor(chapter, blockIndex),
      }),
      percent: percent,
      mode: 'epub',
    );
  }

  Future<void> _addBookmark() async {
    final chapter = _chapter;
    if (chapter == null) return;
    await _repository.createBookmark(
      bookId: widget.bookId,
      chapterIndex: _chapterIndex,
      blockIndex: _currentBlock,
      label: '第 ${_chapterIndex + 1} 章 · 第 ${_currentBlock + 1} 段',
    );
    if (mounted) _message('已添加书签');
  }

  void _jumpBookmark(Bookmark bookmark) {
    final chapter = bookmark.chapterIndex;
    if (chapter == null) return;
    _jumpToBlock(chapter, bookmark.blockIndex ?? 0);
  }

  Future<void> _showBookmarks() async {
    await showBookmarksSheet(
      context: context,
      bookId: widget.bookId,
      currentLabel: '当前位置',
      onAddCurrent: _addBookmark,
      onJump: _jumpBookmark,
    );
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _clearSearch();
      return;
    }
    setState(() => _searchOpen = true);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = '';
      _searchResults = const [];
      _searchResultIndex = null;
    });
  }

  void _runSearch(String raw) {
    final document = _document;
    final query = raw.trim();
    if (document == null || query.isEmpty) {
      _clearSearch();
      return;
    }
    final needle = query.toLowerCase();
    final results = <_EpubSearchResult>[];
    for (
      var chapterIndex = 0;
      chapterIndex < document.chapters.length;
      chapterIndex++
    ) {
      final blocks = document.chapters[chapterIndex].blocks;
      for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
        final text = blocks[blockIndex].text;
        if (text.isEmpty) continue;
        final lower = text.toLowerCase();
        var from = 0;
        while (from <= lower.length - needle.length) {
          final at = lower.indexOf(needle, from);
          if (at < 0) break;
          results.add(
            _EpubSearchResult(
              chapterIndex: chapterIndex,
              blockIndex: blockIndex,
              start: at,
              end: at + query.length,
            ),
          );
          from = at + query.length;
          if (results.length >= 500) break;
        }
        if (results.length >= 500) break;
      }
      if (results.length >= 500) break;
    }
    setState(() {
      _searchOpen = true;
      _searchQuery = query;
      _searchResults = results;
      _searchResultIndex = results.isEmpty ? null : 0;
    });
    if (results.isEmpty) {
      _message('没有找到结果');
    } else {
      _jumpToSearchResult(0);
    }
  }

  void _jumpToSearchResult(int resultIndex) {
    final document = _document;
    if (document == null ||
        resultIndex < 0 ||
        resultIndex >= _searchResults.length) {
      return;
    }
    final result = _searchResults[resultIndex];
    setState(() => _searchResultIndex = resultIndex);
    _jumpToBlock(result.chapterIndex, result.blockIndex);
  }

  void _jumpToBlock(int chapterIndex, int blockIndex) {
    final document = _document;
    if (document == null) return;
    final chapter = _firstReadableChapter(document, chapterIndex);
    _suppressPositionUpdates = true;
    setState(() {
      _chapterIndex = chapter;
      _initialBlock = blockIndex;
      _currentBlock = blockIndex;
      _listGeneration++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.isAttached) {
        _scroll.jumpTo(index: blockIndex, alignment: 0);
      }
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _suppressPositionUpdates = false;
      });
    });
    _scheduleSave();
  }

  Future<void> _followEpubLink(EpubLink link) async {
    final target = link.target;
    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('mailto:')) {
      _message('外部链接暂不支持在应用内打开');
      return;
    }
    final document = _document;
    if (document == null) return;
    final hash = target.indexOf('#');
    final file = hash < 0 ? target : target.substring(0, hash);
    final fragment = hash < 0 ? '' : target.substring(hash + 1);
    final chapterIndex = document.chapters.indexWhere(
      (chapter) => chapter.href == file,
    );
    if (chapterIndex < 0) {
      _message('找不到链接目标');
      return;
    }
    final chapter = document.chapters[chapterIndex];
    final blockIndex = fragment.isEmpty ? null : chapter.anchors[fragment];
    if (blockIndex != null &&
        blockIndex >= 0 &&
        blockIndex < chapter.blocks.length) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(fragment.startsWith('note') ? '脚注' : '链接目标'),
          content: SingleChildScrollView(
            child: SelectableText(chapter.blocks[blockIndex].text),
          ),
          actions: [
            TextButton(
              key: const Key('epub-link-target-close'),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    _jumpToBlock(chapterIndex, fragment.isEmpty ? 0 : blockIndex ?? 0);
  }

  PreferredSizeWidget _buildSearchBar(_EpubPalette palette) {
    final total = _searchResults.length;
    final current = _searchResultIndex;
    final status = _searchQuery.isEmpty
        ? '输入关键词后按回车'
        : total == 0
        ? '没有找到结果'
        : '${current == null ? 1 : current + 1} / $total 个结果';
    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: Material(
        color: palette.background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('epub-search-input'),
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _runSearch,
                      style: TextStyle(color: palette.foreground),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '在本书中搜索',
                        hintStyle: TextStyle(color: palette.muted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: palette.muted,
                        ),
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
                    key: const Key('epub-search-prev'),
                    tooltip: '上一个结果',
                    color: palette.foreground,
                    onPressed: total == 0
                        ? null
                        : () => _jumpToSearchResult(
                            ((current ?? 0) - 1 + total) % total,
                          ),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    key: const Key('epub-search-next'),
                    tooltip: '下一个结果',
                    color: palette.foreground,
                    onPressed: total == 0
                        ? null
                        : () => _jumpToSearchResult(
                            ((current ?? -1) + 1) % total,
                          ),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭搜索',
                    color: palette.foreground,
                    onPressed: _clearSearch,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: Text(
                  status,
                  key: const Key('epub-search-status'),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: palette.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pageForward() {
    final chapter = _chapter;
    if (chapter == null) return;
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) {
      _scroll.scrollTo(
        index: 0,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
      );
      return;
    }
    final last = positions
        .map((position) => position.index)
        .reduce((a, b) => a > b ? a : b);
    final next = last + 1;
    if (next < chapter.blocks.length && _scroll.isAttached) {
      _scroll.scrollTo(
        index: next,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
      );
    } else {
      _goToChapter(_chapterIndex + 1);
    }
  }

  void _pageBackward() {
    final chapter = _chapter;
    if (chapter == null) return;
    final positions = _positions.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions
        .map((position) => position.index)
        .reduce((a, b) => a < b ? a : b);
    final previous = first - 1;
    if (previous >= 0 && _scroll.isAttached) {
      _scroll.scrollTo(
        index: previous,
        alignment: 0,
        duration: const Duration(milliseconds: 220),
      );
    } else {
      _goToChapter(_chapterIndex - 1);
    }
  }

  /// Some EPUBs start with an empty titlepage/spine item. Never open such a
  /// chapter as the initial screen or a TOC target; search forward first, then
  /// backward, and fall back to the original index only if the book is empty.
  int _firstReadableChapter(EpubDocument document, int start) {
    if (document.chapters.isEmpty) return 0;
    final safeStart = start.clamp(0, document.chapters.length - 1);
    for (var i = safeStart; i < document.chapters.length; i++) {
      if (document.chapters[i].blocks.isNotEmpty) return i;
    }
    for (var i = safeStart - 1; i >= 0; i--) {
      if (document.chapters[i].blocks.isNotEmpty) return i;
    }
    return safeStart;
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
        chapterIndex: _chapterIndex,
        blockIndex: _currentBlock,
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
        title: Text('标记 · 第 ${(annotation.chapterIndex ?? 0) + 1} 章'),
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
                annotation.createdAt.toLocal().toString().substring(0, 16),
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

  void _zoomBy(double delta) {
    final next = (_fontSize + delta).clamp(15.0, 36.0);
    if (next == _fontSize) return;
    setState(() {
      _initialBlock = _currentBlock;
      _fontSize = next;
    });
    _scheduleSave();
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length != 2) return;
    final points = _activePointers.values.toList(growable: false);
    _pinchStartDistance = (points[0] - points[1]).distance;
    if (_pinchStartDistance < 1) return;
    _pinchStartFontSize = _fontSize;
    _initialBlock = _currentBlock;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length != 2 || _pinchStartDistance <= 0) return;
    final points = _activePointers.values.toList(growable: false);
    final distance = (points[0] - points[1]).distance;
    if (distance < 1) return;
    final next = (_pinchStartFontSize * distance / _pinchStartDistance).clamp(
      15.0,
      36.0,
    );
    if ((next - _fontSize).abs() < 0.5) return;
    setState(() => _fontSize = next);
    _scheduleSave();
  }

  void _onPointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _pinchStartDistance = 0;
    }
  }

  void _onTrackpadStart(PointerPanZoomStartEvent event) {
    _trackpadStartFontSize = _fontSize;
    _initialBlock = _currentBlock;
  }

  void _onTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale <= 0) return;
    final next = (_trackpadStartFontSize * event.scale).clamp(15.0, 36.0);
    if ((next - _fontSize).abs() < 0.5) return;
    setState(() => _fontSize = next);
    _scheduleSave();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _zoomBy(event.scrollDelta.dy < 0 ? 1 : -1);
    }
  }

  Future<void> _showImage(Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: size.width * 0.92,
            height: size.height * 0.86,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.memory(
                      bytes,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: '关闭图片',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showToc() async {
    final document = _document;
    if (document == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: ListView.builder(
          itemCount: document.toc.length,
          itemBuilder: (context, index) {
            final entry = document.toc[index];
            return ListTile(
              title: Text(entry.title),
              subtitle: Text('第 ${entry.chapterIndex + 1} 章'),
              onTap: () {
                Navigator.pop(context);
                _goToChapter(entry.chapterIndex);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('阅读设置', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Text('整体缩放（文字 + 图片） ${_fontSize.toStringAsFixed(0)}'),
                Slider(
                  value: _fontSize,
                  min: 15,
                  max: 36,
                  divisions: 21,
                  onChanged: (value) {
                    setSheetState(() {});
                    setState(() => _fontSize = value);
                    _scheduleSave();
                  },
                ),
                Text('行距 ${_lineHeight.toStringAsFixed(1)}'),
                Slider(
                  value: _lineHeight,
                  min: 1.4,
                  max: 2.2,
                  divisions: 8,
                  onChanged: (value) {
                    setSheetState(() {});
                    setState(() => _lineHeight = value);
                    _scheduleSave();
                  },
                ),
                Text('段间距 ${_paragraphSpacing.toStringAsFixed(0)}'),
                Slider(
                  value: _paragraphSpacing,
                  min: 4,
                  max: 28,
                  divisions: 12,
                  onChanged: (value) {
                    setSheetState(() {});
                    setState(() => _paragraphSpacing = value);
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '文字和图片会一起缩放；图片放大后超宽可左右拖动，点图片右上角按钮可全屏查看。也可用右上角 +/-、Ctrl+滚轮或双指缩放。',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < _epubPalettes.length; i++)
                      ChoiceChip(
                        label: Text(_epubPalettes[i].name),
                        selected: _paletteIndex == i,
                        onSelected: (_) {
                          setSheetState(() {});
                          setState(() => _paletteIndex = i);
                          _scheduleSave();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final chapter = _chapter;
    final palette = _epubPalettes[_paletteIndex];
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.foreground,
        leading: IconButton(
          tooltip: '返回书库',
          onPressed: _close,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _book?.title ?? '阅读',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: palette.foreground),
            ),
            if (chapter != null)
              Text(
                chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: palette.muted),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: document == null ? null : _toggleSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: '整体缩小（Ctrl+滚轮）',
            onPressed: _fontSize <= 15 ? null : () => _zoomBy(-1),
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          IconButton(
            tooltip: '整体放大（Ctrl+滚轮）',
            onPressed: _fontSize >= 36 ? null : () => _zoomBy(1),
            icon: const Icon(Icons.zoom_in_rounded),
          ),
          IconButton(
            tooltip: '目录',
            onPressed: document == null ? null : _showToc,
            icon: const Icon(Icons.format_list_bulleted_rounded),
          ),
          PopupMenuButton<_EpubReaderAction>(
            tooltip: '更多阅读工具',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) {
              switch (action) {
                case _EpubReaderAction.tts:
                  unawaited(_openTts());
                case _EpubReaderAction.bookmarks:
                  unawaited(_showBookmarks());
                case _EpubReaderAction.settings:
                  unawaited(_showSettings());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _EpubReaderAction.tts,
                child: ListTile(
                  leading: Icon(Icons.headphones_rounded),
                  title: Text('朗读'),
                ),
              ),
              PopupMenuItem(
                value: _EpubReaderAction.bookmarks,
                child: ListTile(
                  leading: Icon(Icons.bookmark_outline_rounded),
                  title: Text('书签'),
                ),
              ),
              PopupMenuItem(
                value: _EpubReaderAction.settings,
                child: ListTile(
                  leading: Icon(Icons.text_fields_rounded),
                  title: Text('阅读设置'),
                ),
              ),
            ],
          ),
        ],
        bottom: _searchOpen ? _buildSearchBar(palette) : null,
      ),
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerEnd,
        onPointerCancel: _onPointerEnd,
        onPointerPanZoomStart: _onTrackpadStart,
        onPointerPanZoomUpdate: _onTrackpadUpdate,
        onPointerSignal: _onPointerSignal,
        child: _buildBody(palette),
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: _marking ? '取消框选' : '标记区域',
        onPressed: () => setState(() => _marking = !_marking),
        child: Icon(_marking ? Icons.close_rounded : Icons.crop_free_rounded),
      ),
    );
  }

  Widget _buildBody(_EpubPalette palette) {
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 40, color: palette.muted),
              const SizedBox(height: 12),
              Text(
                '无法打开这本 EPUB',
                style: TextStyle(color: palette.foreground, fontSize: 16),
              ),
              const SizedBox(height: 8),
              SelectableText(
                '$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, fontSize: 12),
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
    final document = _document;
    final chapter = _chapter;
    if (document == null || chapter == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chapter.blocks.isEmpty) {
      return Center(
        child: Text('本章没有可显示的文本', style: TextStyle(color: palette.muted)),
      );
    }
    return Column(
      children: [
        Expanded(
          child: RegionMarkLayer(
            boundaryKey: _captureKey,
            marking: _marking,
            annotations: _annotations
                .where((annotation) => annotation.chapterIndex == _chapterIndex)
                .toList(),
            onSelected: _onRegionSelected,
            onAnnotationTap: _showAnnotation,
            onCancel: () => setState(() => _marking = false),
            child: ScrollablePositionedList.builder(
              key: ValueKey('epub-chapter-$_chapterIndex-$_listGeneration'),
              itemScrollController: _scroll,
              itemPositionsListener: _positions,
              initialScrollIndex: _initialBlock.clamp(
                0,
                chapter.blocks.length - 1,
              ),
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              itemCount: chapter.blocks.length,
              itemBuilder: (context, index) => index == _ttsHighlightBlock
                  ? Container(
                      color: palette.muted.withValues(alpha: 0.10),
                      child: _block(chapter.blocks[index], palette, index),
                    )
                  : _block(chapter.blocks[index], palette, index),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          color: palette.background,
          child: Column(
            children: [
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('epub-previous-page'),
                    onPressed: _chapterIndex > 0 || _currentBlock > 0
                        ? _pageBackward
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                    label: const Text('上一页'),
                  ),
                  Expanded(
                    child: Text(
                      '第 ${_chapterIndex + 1} / ${document.chapters.length} 章'
                      ' · 第 ${_currentBlock + 1} / ${chapter.blocks.length} 段',
                      key: const Key('epub-chapter-indicator'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('epub-next-page'),
                    onPressed: _pageForward,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: const Text('下一页'),
                  ),
                ],
              ),
              Text(
                '也可使用鼠标滚轮 / 触控板滚动',
                style: TextStyle(color: palette.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableBlock(EpubBlock block, _EpubPalette palette, int index) {
    final rows = block.tableRows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final cellStyle = TextStyle(
      color: palette.foreground,
      fontSize: _fontSize * 0.85,
      height: 1.45,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          key: PageStorageKey('epub-table-$_chapterIndex-$index'),
          scrollDirection: Axis.horizontal,
          child: _EpubSpanTable(
            rows: rows,
            cellStyle: cellStyle,
            palette: palette,
          ),
        ),
      ),
    );
  }

  Widget _block(EpubBlock block, _EpubPalette palette, int index) {
    final base = TextStyle(
      color: palette.foreground,
      fontSize: _fontSize,
      height: _lineHeight,
    );
    if (block.kind == EpubBlockKind.image) {
      final bytes = block.imageBytes;
      if (bytes == null) return const SizedBox.shrink();
      return EpubImageBlock(
        bytes: bytes,
        scale: _fontSize / _baseFontSize,
        scrollKey: PageStorageKey('epub-image-$_chapterIndex-$index'),
        onTap: () => _showImage(bytes),
      );
    }
    if (block.kind == EpubBlockKind.table) {
      return _tableBlock(block, palette, index);
    }
    final text = block.text;
    if (text.isEmpty) return const SizedBox.shrink();
    final style = switch (block.kind) {
      EpubBlockKind.heading1 => base.copyWith(
        fontSize: _fontSize * 1.65,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      EpubBlockKind.heading2 => base.copyWith(
        fontSize: _fontSize * 1.35,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      EpubBlockKind.heading3 => base.copyWith(
        fontSize: _fontSize * 1.15,
        fontWeight: FontWeight.w700,
      ),
      EpubBlockKind.code => base.copyWith(
        fontFamily: 'Consolas',
        fontSize: _fontSize * 0.9,
        height: 1.5,
      ),
      EpubBlockKind.quote => base.copyWith(
        color: palette.muted,
        fontStyle: FontStyle.italic,
      ),
      _ => base,
    };
    final rubySpans = <TextSpan>[];
    var rubyCursor = 0;
    for (final ruby in block.rubies) {
      if (ruby.start < rubyCursor ||
          ruby.end <= ruby.start ||
          ruby.end > text.length ||
          ruby.annotation.isEmpty) {
        continue;
      }
      if (ruby.start > rubyCursor) {
        rubySpans.add(TextSpan(text: text.substring(rubyCursor, ruby.start)));
      }
      rubySpans.add(TextSpan(text: text.substring(ruby.start, ruby.end)));
      rubySpans.add(
        TextSpan(
          text: '(${ruby.annotation})',
          style: style.copyWith(
            fontSize: (style.fontSize ?? _fontSize) * 0.55,
            color: palette.muted,
          ),
        ),
      );
      rubyCursor = ruby.end;
    }
    if (rubyCursor < text.length && rubySpans.isNotEmpty) {
      rubySpans.add(TextSpan(text: text.substring(rubyCursor)));
    }
    final rubyChild = rubySpans.isEmpty
        ? null
        : SelectableText.rich(TextSpan(style: style, children: rubySpans));
    final searchMatch = _currentSearchResult;
    final showSearchMatch =
        searchMatch != null &&
        searchMatch.chapterIndex == _chapterIndex &&
        searchMatch.blockIndex == index &&
        searchMatch.start >= 0 &&
        searchMatch.end <= text.length &&
        searchMatch.end > searchMatch.start;
    final child =
        rubyChild ??
        (showSearchMatch
            ? SelectableText.rich(
                TextSpan(
                  style: style,
                  children: [
                    if (searchMatch.start > 0)
                      TextSpan(text: text.substring(0, searchMatch.start)),
                    TextSpan(
                      text: text.substring(searchMatch.start, searchMatch.end),
                      style: style.copyWith(
                        backgroundColor: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.25),
                      ),
                    ),
                    if (searchMatch.end < text.length)
                      TextSpan(text: text.substring(searchMatch.end)),
                  ],
                ),
              )
            : SelectableText(text, style: style));
    final linkChips = block.links
        .where(
          (link) =>
              link.start >= 0 &&
              link.end > link.start &&
              link.end <= text.length,
        )
        .take(8)
        .map((link) {
          final label = text.substring(link.start, link.end);
          final isFootnote = link.target.contains('#');
          return ActionChip(
            key: Key('epub-link-$_chapterIndex-$index-${link.start}'),
            avatar: Icon(
              isFootnote ? Icons.notes_rounded : Icons.link_rounded,
              size: 14,
            ),
            label: Text(
              isFootnote ? '脚注 $label' : '链接 $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => unawaited(_followEpubLink(link)),
          );
        })
        .toList();
    final content = linkChips.isEmpty
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: linkChips),
            ],
          );
    return Padding(
      padding: EdgeInsets.only(
        bottom: block.kind == EpubBlockKind.listItem
            ? _paragraphSpacing * 0.45
            : _paragraphSpacing,
        left: block.kind == EpubBlockKind.listItem ? 18 : 0,
      ),
      child: block.kind == EpubBlockKind.listItem
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: style),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
