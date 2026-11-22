import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/phase0_store.dart';
import '../core/reading_anchor.dart';
import '../engines/docx/docx_document.dart';
import 'docx_block_view.dart';
import 'docx_reader_header.dart';

class DocxLab extends StatefulWidget {
  const DocxLab({super.key});

  @override
  State<DocxLab> createState() => _DocxLabState();
}

class _DocxLabState extends State<DocxLab> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  DocxDocument? _doc;
  Object? _error;
  final List<ReadingAnchor> _annotations = [];
  String _selectedText = '';
  int _firstVisible = 0;
  int _initialBlock = 0;
  double _fontSize = 17;
  Timer? _saveTimer;

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
      final asset = await rootBundle.load('assets/fixtures/sample.docx');
      final doc = const DocxParser().parse(asset.buffer.asUint8List());
      final raw = await Phase0Store.instance.readJson('docx_state.json');
      if (!mounted) return;
      setState(() {
        _doc = doc;
        if (raw is Map) {
          _firstVisible = (raw['block'] as num?)?.toInt() ?? 0;
          _initialBlock = _firstVisible;
          _fontSize = (raw['fontSize'] as num?)?.toDouble() ?? _fontSize;
          final anchors = raw['anchors'];
          if (anchors is List) {
            _annotations
              ..clear()
              ..addAll(anchors.whereType<Map>().map((value) =>
                  ReadingAnchor.fromJson(value.map(
                      (key, value) => MapEntry(key.toString(), value)))));
          }
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
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
    if (_doc == null) return;
    await Phase0Store.instance.writeJson('docx_state.json', {
      'block': _firstVisible,
      'fontSize': _fontSize,
      'anchors': _annotations.map((anchor) => anchor.toJson()).toList(),
    });
  }

  void _saveSelection() {
    final doc = _doc;
    if (doc == null) return;
    final quote = _selectedText.trim();
    if (quote.isEmpty) return;
    if (quote.contains('\n')) {
      _message('Phase 0 原型先验证段内标注；跨段选择留到 Phase 3。');
      return;
    }
    final matchingBlocks = <int>[];
    for (var i = 0; i < doc.blocks.length; i++) {
      if (doc.blocks[i].text.contains(quote)) matchingBlocks.add(i);
    }
    if (matchingBlocks.length != 1) {
      _message('所选文字在文档中重复出现，Phase 0 无法唯一定位，未保存。');
      return;
    }
    final bestBlock = matchingBlocks.single;
    final block = doc.blocks[bestBlock];
    if (block.kind == DocxBlockKind.table) {
      _message('Phase 0 尚未实现表格单元格内高亮；请在普通段落中选择。');
      return;
    }
    final start = block.text.indexOf(quote);
    if (start != block.text.lastIndexOf(quote)) {
      _message('该段中相同文字出现多次，Phase 0 不静默选择第一处，未保存。');
      return;
    }
    final anchor = ReadingAnchor(
      format: BookFormat.docx,
      quote: quote,
      blockIndex: bestBlock,
      charOffset: start,
      pageStart: start,
      pageEnd: start + quote.length,
      docxPath: block.path,
      contextBefore:
          block.text.substring(math.max(0, start - 24), start),
      contextAfter: block.text.substring(
        math.min(block.text.length, start + quote.length),
        math.min(block.text.length, start + quote.length + 24),
      ),
      textHash: Anchoring.textHash(doc.plainText),
      color: 'blue',
    );
    setState(() {
      _annotations.insert(0, anchor);
      _selectedText = '';
    });
    _scheduleSave();
    _message('已保存 DOCX 标注：${block.path} :$start');
  }

  Future<void> _runProbe() async {
    final doc = _doc;
    if (doc == null) return;
    const marker = 'MOYE-DOCX-PARAGRAPH-ANCHOR';
    final index = doc.blocks.indexWhere((block) => block.text.contains(marker));
    if (index < 0) {
      _message('未找到 DOCX 段落标记');
      return;
    }
    final block = doc.blocks[index];
    final offset = block.text.indexOf(marker);
    setState(() => _firstVisible = index);
    if (_scroll.isAttached) {
      await _scroll.scrollTo(
        index: index,
        alignment: 0.2,
        duration: const Duration(milliseconds: 280),
      );
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DOCX 段落定位验证'),
        content: SelectableText(
          '段落路径: ${block.path}\n'
          '文本偏移: $offset..${offset + marker.length - 1}\n'
          '样式: ${block.styleName} (${block.styleId})\n'
          '文本: ${block.text}',
          key: const Key('docx-probe-result'),
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
    if (_error != null) return Center(child: Text('DOCX 解析失败：$_error'));
    final doc = _doc;
    if (doc == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final first = _firstVisible.clamp(0, math.max(0, doc.blocks.length - 1)).toInt();
    final path = doc.blocks.isEmpty ? '—' : doc.blocks[first].path;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          DocxReaderHeader(
            document: doc,
            fontSize: _fontSize,
            path: path,
            annotationCount: _annotations.length,
            onFontDown: _fontSize <= 13
                ? null
                : () {
                    setState(() => _fontSize -= 1);
                    _scheduleSave();
                  },
            onFontUp: _fontSize >= 28
                ? null
                : () {
                    setState(() => _fontSize += 1);
                    _scheduleSave();
                  },
            onProbe: _runProbe,
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
                key: ValueKey('docx-$_initialBlock'),
                itemScrollController: _scroll,
                itemPositionsListener: _positions,
                initialScrollIndex:
                    _initialBlock.clamp(0, math.max(0, doc.blocks.length - 1)),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
                itemCount: doc.blocks.length,
                itemBuilder: (context, index) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: DocxBlockView(
                      block: doc.blocks[index],
                      blockIndex: index,
                      fontSize: _fontSize,
                      annotations: _annotations,
                      highlightColor: const Color(0xFF7CB7D8),
                      linkColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_selectedText.trim().isNotEmpty)
            DocxSelectionBar(text: _selectedText, onSave: _saveSelection),
        ],
      ),
    );
  }
}
