import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/phase0_store.dart';
import '../core/reading_anchor.dart';
import '../engines/epub/epub_document.dart';
import 'epub_reader_widgets.dart';

class EpubLab extends StatefulWidget {
  const EpubLab({super.key});

  @override
  State<EpubLab> createState() => _EpubLabState();
}

class _EpubLabState extends State<EpubLab> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  EpubDocument? _book;
  Object? _error;
  int _chapterIndex = 0;
  int _firstVisible = 0;
  int _initialBlock = 0;
  double _fontSize = 19;
  double _lineHeight = 1.8;
  int _paletteIndex = 0;
  String _selectedText = '';
  final List<ReadingAnchor> _annotations = [];
  Timer? _saveTimer;

  EpubChapter? get _chapter {
    final book = _book;
    if (book == null || book.chapters.isEmpty) return null;
    return book.chapters[_chapterIndex.clamp(0, book.chapters.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    _load();
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    _saveTimer?.cancel();
    _persist();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await rootBundle.load('assets/fixtures/sample.epub');
      final book = const EpubParser().parse(data.buffer.asUint8List());
      if (!mounted) return;
      setState(() => _book = book);
      await _restoreState(book);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _restoreState(EpubDocument book) async {
    final raw = await Phase0Store.instance.readJson('epub_state.json');
    if (!mounted || raw is! Map) return;
    final chapter = (raw['chapter'] as num?)?.toInt() ?? 0;
    final block = (raw['block'] as num?)?.toInt() ?? 0;
    final anchors = raw['anchors'];
    setState(() {
      _chapterIndex = chapter.clamp(0, book.chapters.length - 1);
      _initialBlock = block;
      _firstVisible = block;
      _fontSize = (raw['fontSize'] as num?)?.toDouble() ?? _fontSize;
      _lineHeight = (raw['lineHeight'] as num?)?.toDouble() ?? _lineHeight;
      _paletteIndex = (raw['palette'] as num?)?.toInt() ?? 0;
      if (anchors is List) {
        _annotations
          ..clear()
          ..addAll(anchors.whereType<Map>().map((value) =>
              ReadingAnchor.fromJson(
                  value.map((key, value) => MapEntry(key.toString(), value)))));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.isAttached) {
        _scroll.jumpTo(index: _firstVisible.clamp(0, 9999), alignment: 0);
      }
    });
  }

  void _onPositions() {
    final positions = _positions.itemPositions.value;
    final visible = positions.where((position) => position.itemLeadingEdge < 0.6);
    if (visible.isEmpty) return;
    final first = visible
        .map((position) => position.index)
        .reduce((a, b) => math.min(a, b));
    if (first != _firstVisible && mounted) {
      setState(() => _firstVisible = first);
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persist);
  }

  Future<void> _persist() async {
    if (_book == null) return;
    await Phase0Store.instance.writeJson('epub_state.json', {
      'chapter': _chapterIndex,
      'block': _firstVisible,
      'fontSize': _fontSize,
      'lineHeight': _lineHeight,
      'palette': _paletteIndex,
      'anchors': _annotations.map((anchor) => anchor.toJson()).toList(),
    });
  }

  void _selectChapter(int index) {
    if (index == _chapterIndex) return;
    setState(() {
      _chapterIndex = index;
      _firstVisible = 0;
      _initialBlock = 0;
      _selectedText = '';
    });
    _scheduleSave();
  }

  void _saveSelection() {
    final chapter = _chapter;
    final book = _book;
    if (chapter == null || book == null) return;
    final quote = _selectedText.trim();
    if (quote.isEmpty) return;
    if (quote.contains('\n')) {
      _message('Phase 0 原型先验证段内标注；跨段选择留到 Phase 3。');
      return;
    }
    final matchingBlocks = <int>[];
    for (var i = 0; i < chapter.blocks.length; i++) {
      if (chapter.blocks[i].text.contains(quote)) matchingBlocks.add(i);
    }
    if (matchingBlocks.length != 1) {
      _message('选择内容跨段或在章节中重复出现，Phase 0 无法唯一定位，未保存。');
      return;
    }
    final bestBlock = matchingBlocks.single;
    final text = chapter.blocks[bestBlock].text;
    final start = text.indexOf(quote);
    if (start != text.lastIndexOf(quote)) {
      _message('该段中相同文字出现多次，Phase 0 不静默选择第一处，未保存。');
      return;
    }
    final anchor = ReadingAnchor(
      format: BookFormat.epub,
      quote: quote,
      spineIndex: chapter.index,
      blockIndex: bestBlock,
      pageStart: start,
      pageEnd: start + quote.length,
      charOffset: start,
      cfi: book.cfiFor(chapter, bestBlock, charOffset: start),
      contextBefore: text.substring(math.max(0, start - 32), start),
      contextAfter: text.substring(
        math.min(text.length, start + quote.length),
        math.min(text.length, start + quote.length + 32),
      ),
      textHash: Anchoring.textHash(chapter.plainText),
      color: 'yellow',
    );
    setState(() {
      _annotations.insert(0, anchor);
      _selectedText = '';
    });
    _scheduleSave();
    _message('已保存 EPUB 标注：${anchor.cfi}');
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text('EPUB 解析失败：$_error'),
      );
    }
    final book = _book;
    if (book == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildReader(context, book);
  }

  Widget _buildReader(BuildContext context, EpubDocument book) {
    final chapter = _chapter;
    if (chapter == null) return const Center(child: Text('本书没有可读章节'));
    final palette = readerPalettes[_paletteIndex % readerPalettes.length];
    final block =
        _firstVisible.clamp(0, math.max(0, chapter.blocks.length - 1)).toInt();
    final cfi = book.cfiFor(chapter, block);
    return ColoredBox(
      color: palette.background,
      child: Column(
        children: [
          EpubHeader(
            book: book,
            chapter: chapter,
            chapterIndex: _chapterIndex,
            fontSize: _fontSize,
            lineHeight: _lineHeight,
            palette: palette,
            onFontDown: _fontSize <= 14
                ? null
                : () {
                    setState(() => _fontSize -= 1);
                    _scheduleSave();
                  },
            onFontUp: _fontSize >= 30
                ? null
                : () {
                    setState(() => _fontSize += 1);
                    _scheduleSave();
                  },
            onChapter: _selectChapter,
            onLineHeight: (value) {
              setState(() => _lineHeight = value);
              _scheduleSave();
            },
            onCyclePalette: () {
              setState(() => _paletteIndex =
                  (_paletteIndex + 1) % readerPalettes.length);
              _scheduleSave();
            },
            cfi: cfi,
            annotationCount:
                _annotations.where((a) => a.spineIndex == chapter.index).length,
          ),
          Expanded(
            child: SelectionArea(
              onSelectionChanged: (content) {
                final next = content?.plainText ?? '';
                if (next != _selectedText) {
                  setState(() => _selectedText = next);
                }
              },
              child: ScrollablePositionedList.builder(
                key: ValueKey('epub-${chapter.index}-$_initialBlock'),
                itemScrollController: _scroll,
                itemPositionsListener: _positions,
                initialScrollIndex: _initialBlock.clamp(
                    0, math.max(0, chapter.blocks.length - 1)),
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 44),
                itemCount: chapter.blocks.length,
                itemBuilder: (context, index) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _buildBlock(chapter, index, palette),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: palette.panel,
              border: Border(top: BorderSide(color: palette.divider)),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 15, color: palette.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    cfi,
                    key: const Key('epub-cfi-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  '${_annotations.where((a) => a.spineIndex == chapter.index).length} 条标注',
                  style: TextStyle(color: palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_selectedText.trim().isNotEmpty)
            EpubSelectionBar(
              palette: palette,
              text: _selectedText,
              onSave: _saveSelection,
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(
      EpubChapter chapter, int index, ReaderPalette palette) {
    final block = chapter.blocks[index];
    if (block.kind == EpubBlockKind.image) {
      final bytes = block.imageBytes;
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            height: 300,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      );
    }
    final spans = buildEpubSpans(
      block,
      _annotations,
      chapter.index,
      index,
      const Color(0xFFF1CC67),
    );
    final style = _styleFor(block.kind, palette);
    final content = Text.rich(TextSpan(children: spans, style: style));
    if (block.kind == EpubBlockKind.listItem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Text('•', style: style.copyWith(color: palette.muted)),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    if (block.kind == EpubBlockKind.quote) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 9),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.muted, width: 2)),
        ),
        child: content,
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: block.kind == EpubBlockKind.heading1 ? 16 : 6,
        bottom: block.kind == EpubBlockKind.heading1 ? 12 : 6,
      ),
      child: content,
    );
  }

  TextStyle _styleFor(EpubBlockKind kind, ReaderPalette palette) {
    final base = TextStyle(
      color: palette.foreground,
      fontSize: _fontSize,
      height: _lineHeight,
    );
    return switch (kind) {
      EpubBlockKind.heading1 => base.copyWith(
          fontSize: _fontSize + 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      EpubBlockKind.heading2 => base.copyWith(
          fontSize: _fontSize + 7,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      EpubBlockKind.heading3 => base.copyWith(
          fontSize: _fontSize + 3,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
      EpubBlockKind.quote => base.copyWith(
          color: palette.muted,
          fontStyle: FontStyle.italic,
        ),
      EpubBlockKind.code => base.copyWith(
          fontFamily: 'Consolas',
          fontSize: _fontSize - 1,
          height: 1.5,
        ),
      _ => base,
    };
  }
}
