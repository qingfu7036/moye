import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../app/moye_theme.dart';
import '../core/phase0_store.dart';
import '../core/reading_anchor.dart';

class PdfLab extends StatefulWidget {
  const PdfLab({super.key});

  @override
  State<PdfLab> createState() => _PdfLabState();
}

class _PdfLabState extends State<PdfLab> {
  static const _textPdf = 'assets/fixtures/sample.pdf';
  static const _scannedPdf = 'assets/fixtures/scanned.pdf';

  PdfViewerController _controller = PdfViewerController();
  String _asset = _textPdf;
  bool? _hasTextLayer;
  int _pageCount = 0;
  int? _currentPage = 1;
  PdfTextSelectionDelegate? _selection;
  String _selectedText = '';
  final List<ReadingAnchor> _anchors = [];
  String? _probeResult;
  bool _busy = false;
  final bool _showDetails = true;

  @override
  void initState() {
    super.initState();
    _loadAnchors();
  }

  Future<void> _loadAnchors() async {
    final decoded =
        await Phase0Store.instance.readJson(_storeNameFor(_asset));
    final anchors = decoded is List
        ? decoded
            .whereType<Map>()
            .map((raw) => ReadingAnchor.fromJson(
                  raw.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList()
        : const <ReadingAnchor>[];
    if (!mounted) return;
    setState(() {
      _anchors
        ..clear()
        ..addAll(anchors.where((anchor) => anchor.format == BookFormat.pdf));
    });
  }

  String _storeNameFor(String asset) =>
      'pdf_anchors_${asset.split('/').last.replaceAll('.', '_')}.json';

  void _switchAsset(String asset) {
    if (_asset == asset) return;
    setState(() {
      _asset = asset;
      _controller = PdfViewerController();
      _hasTextLayer = null;
      _pageCount = 0;
      _currentPage = 1;
      _selection = null;
      _selectedText = '';
      _probeResult = null;
      _anchors.clear();
    });
    _loadAnchors();
  }

  Future<void> _onDocumentLoaded() async {
    if (!_controller.isReady) return;
    final document = _controller.document;
    final count = document.pages.length;
    var characters = 0;
    for (var i = 0; i < math.min(3, count); i++) {
      final text = await document.pages[i].loadStructuredText(ensureLoaded: true);
      characters += text.fullText.trim().length;
    }
    if (!mounted) return;
    setState(() {
      _pageCount = count;
      _hasTextLayer = characters > 20;
      _currentPage = _controller.pageNumber ?? 1;
    });
  }

  void _onSelectionChanged(PdfTextSelection selection) {
    if (selection is! PdfTextSelectionDelegate) return;
    _selection = selection;
    final cached = selection.selectedTextIfLoaded ?? '';
    if (cached != _selectedText && mounted) {
      setState(() => _selectedText = cached);
    }
    selection.getSelectedText().then((text) {
      if (mounted && text != _selectedText) {
        setState(() => _selectedText = text);
      }
    });
  }

  Future<void> _saveHighlight(String colorName) async {
    final selection = _selection;
    if (selection == null) return;
    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    if (ranges.any((range) => range.pageNumber != ranges.first.pageNumber)) {
      _showMessage('Phase 0 原型仅验证单页标注；跨页标注留到 Phase 3。');
      return;
    }
    final range = ranges.first;
    final pageText = range.pageText.fullText;
    final rects = range
        .enumerateFragmentBoundingRects()
        .map((fragment) => PdfRectData(
              fragment.bounds.left,
              fragment.bounds.top,
              fragment.bounds.right,
              fragment.bounds.bottom,
            ))
        .toList();
    final anchor = ReadingAnchor(
      format: BookFormat.pdf,
      quote: range.text,
      page: range.pageNumber,
      pageStart: range.start,
      pageEnd: range.end,
      contextBefore: pageText.substring(
        math.max(0, range.start - 40),
        range.start,
      ),
      contextAfter: pageText.substring(
        range.end,
        math.min(pageText.length, range.end + 40),
      ),
      pdfRects: rects,
      textHash: Anchoring.textHash(pageText),
      color: colorName,
    );
    setState(() => _anchors.insert(0, anchor));
    await Phase0Store.instance.writeJson(
      _storeNameFor(_asset),
      _anchors.map((item) => item.toJson()).toList(),
    );
    await selection.clearTextSelection();
    if (!mounted) return;
    setState(() => _selectedText = '');
    _showMessage('已保存高亮与 ${rects.length} 个页面矩形');
  }

  Future<void> _runProbe() async {
    if (!_controller.isReady) return;
    setState(() => _busy = true);
    final pages = _controller.document.pages;
    final page = pages.length > 1 ? pages[1] : pages.first;
    final text = await page.loadStructuredText(ensureLoaded: true);
    const marker = 'MOYE-PHASE0-ANCHOR';
    final start = text.fullText.indexOf(marker);
    if (start < 0) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _probeResult = _hasTextLayer == false
            ? '当前样本没有文字层：扫描型分支符合预期。\n页面渲染仍可用，OCR 不在 Phase 0 范围内。'
            : '未找到测试标记；请确认当前样本是 sample.pdf。';
      });
      return;
    }
    final range = text.getRangeFromAB(start, start + marker.length - 1);
    final rects = range.enumerateFragmentBoundingRects().toList();
    await _controller.goToPage(pageNumber: page.pageNumber);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final selection = PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(text, range.start),
      PdfTextSelectionPoint(text, range.end - 1),
    );
    await _controller.textSelectionDelegate
        .setTextSelectionPointRange(selection);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final selected =
        await _controller.textSelectionDelegate.getSelectedTextRanges();
    _selection = _controller.textSelectionDelegate;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectedText = selected.map((item) => item.text).join();
      _probeResult = 'PDFium 文字几何验证\n'
          '页码: ${range.pageNumber}\n'
          '字符偏移: ${range.start}..${range.end}\n'
          '文本: ${range.text}\n'
          '矩形数量: ${rects.length}\n'
          '首个矩形: ${range.bounds}\n'
          '选区回读: ${selected.map((item) => item.text).join(' | ')}\n'
          '选区范围: ${selected.map((item) => '${item.start}..${item.end}').join(' | ')}';
    });
  }

  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final anchor in _anchors) {
      if (anchor.page != page.pageNumber) continue;
      final paint = Paint()
        ..color = _colorFor(anchor.color).withValues(alpha: 0.34)
        ..style = PaintingStyle.fill;
      for (final raw in anchor.pdfRects) {
        final rect = PdfRect(raw.left, raw.top, raw.right, raw.bottom)
            .toRectInDocument(page: page, pageRect: pageRect);
        canvas.drawRect(rect, paint);
      }
    }
  }

  Color _colorFor(String? name) => switch (name) {
        'blue' => const Color(0xFF7CB7D8),
        'rose' => const Color(0xFFE39C92),
        'green' => const Color(0xFF84BE9B),
        _ => const Color(0xFFF1CC67),
      };

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        return Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: PdfViewer.asset(
                          _asset,
                          key: ValueKey(_asset),
                          controller: _controller,
                          params: PdfViewerParams(
                            margin: 14,
                            backgroundColor: theme.brightness == Brightness.dark
                                ? const Color(0xFF202A25)
                                : const Color(0xFFE7ECE7),
                            onDocumentLoadFinished: (_, success) {
                              if (success) _onDocumentLoaded();
                            },
                            onPageChanged: (page) {
                              if (mounted) setState(() => _currentPage = page);
                            },
                            textSelectionParams: PdfTextSelectionParams(
                              enabled: true,
                              onTextSelectionChange: _onSelectionChanged,
                            ),
                            pagePaintCallbacks: [_paintHighlights],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (wide && _showDetails)
                    SizedBox(
                      width: 300,
                      child: _DetailsPanel(
                        theme: theme,
                        pageCount: _pageCount,
                        currentPage: _currentPage,
                        hasTextLayer: _hasTextLayer,
                        anchors: _anchors,
                        probeResult: _probeResult,
                        busy: _busy,
                        onProbe: _runProbe,
                        onSwitchText: () => _switchAsset(_textPdf),
                        onSwitchScanned: () => _switchAsset(_scannedPdf),
                        textSelected: _asset == _textPdf,
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: _StatusPill(
                hasTextLayer: _hasTextLayer,
                pageCount: _pageCount,
                asset: _asset,
              ),
            ),
            if (!wide)
              Positioned(
                right: 16,
                top: 16,
                child: IconButton.filledTonal(
                  key: const Key('pdf-details-button'),
                  tooltip: '查看验证详情',
                  onPressed: () => _showMobileDetails(context),
                  icon: const Icon(Icons.science_outlined),
                ),
              ),
            if (_selectedText.trim().isNotEmpty)
              Positioned(
                left: 20,
                right: wide ? 320 : 20,
                bottom: 18,
                child: _SelectionToolbar(
                  text: _selectedText,
                  onHighlight: _saveHighlight,
                ),
              ),
            Positioned(
              left: 20,
              bottom: _selectedText.trim().isEmpty ? 18 : 106,
              right: wide ? 320 : 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _PageBar(
                  page: _currentPage,
                  pageCount: _pageCount,
                  onPrevious: _currentPage == null || _currentPage! <= 1
                      ? null
                      : () => _controller.goToPage(pageNumber: _currentPage! - 1),
                  onNext: _currentPage == null || _currentPage! >= _pageCount
                      ? null
                      : () => _controller.goToPage(pageNumber: _currentPage! + 1),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMobileDetails(BuildContext context) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        child: _DetailsPanel(
          theme: theme,
          pageCount: _pageCount,
          currentPage: _currentPage,
          hasTextLayer: _hasTextLayer,
          anchors: _anchors,
          probeResult: _probeResult,
          busy: _busy,
          onProbe: () async {
            await _runProbe();
            if (context.mounted) Navigator.pop(context);
          },
          onSwitchText: () {
            _switchAsset(_textPdf);
            Navigator.pop(context);
          },
          onSwitchScanned: () {
            _switchAsset(_scannedPdf);
            Navigator.pop(context);
          },
          textSelected: _asset == _textPdf,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.hasTextLayer,
    required this.pageCount,
    required this.asset,
  });

  final bool? hasTextLayer;
  final int pageCount;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = hasTextLayer == null
        ? '正在读取 PDFium…'
        : hasTextLayer!
            ? '文字层可用（抽样） · $pageCount 页'
            : '未检测到文字层（前3页） · $pageCount 页';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasTextLayer == false ? MoyeColors.amber : MoyeColors.pine,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            key: const Key('pdf-type-label'),
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int? page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Text(
            '${page ?? '—'} / ${pageCount == 0 ? '—' : pageCount}',
            key: const Key('pdf-page-label'),
            style: theme.textTheme.labelMedium,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.text, required this.onHighlight});

  final String text;
  final ValueChanged<String> onHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            for (final entry in const {
              'yellow': Color(0xFFF1CC67),
              'blue': Color(0xFF7CB7D8),
              'rose': Color(0xFFE39C92),
              'green': Color(0xFF84BE9B),
            }.entries)
              IconButton(
                tooltip: '${entry.key} 高亮',
                visualDensity: VisualDensity.compact,
                onPressed: () => onHighlight(entry.key),
                icon: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.theme,
    required this.pageCount,
    required this.currentPage,
    required this.hasTextLayer,
    required this.anchors,
    required this.probeResult,
    required this.busy,
    required this.onProbe,
    required this.onSwitchText,
    required this.onSwitchScanned,
    required this.textSelected,
  });

  final ThemeData theme;
  final int pageCount;
  final int? currentPage;
  final bool? hasTextLayer;
  final List<ReadingAnchor> anchors;
  final String? probeResult;
  final bool busy;
  final VoidCallback onProbe;
  final VoidCallback onSwitchText;
  final VoidCallback onSwitchScanned;
  final bool textSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      child: ListView(
        children: [
          Text('PDF / 技术验证', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '验证 PDFium 渲染、文字层识别、字符矩形与自定义高亮。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('文本型')),
              ButtonSegment(value: false, label: Text('扫描型')),
            ],
            selected: {textSelected},
            onSelectionChanged: (value) {
              value.first ? onSwitchText() : onSwitchScanned();
            },
          ),
          const SizedBox(height: 14),
          _InfoRow(label: '页面数', value: '$pageCount'),
          _InfoRow(label: '当前页', value: '${currentPage ?? '—'}'),
          _InfoRow(
            label: '文字层',
            value: hasTextLayer == null ? '读取中' : (hasTextLayer! ? '可用' : '缺失（预期）'),
          ),
          _InfoRow(label: '已保存高亮', value: '${anchors.length}'),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('pdf-probe-button'),
            onPressed: busy ? null : onProbe,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.straighten_rounded, size: 18),
            label: const Text('验证文字坐标'),
          ),
          if (probeResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                probeResult!,
                key: const Key('pdf-probe-result'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  height: 1.55,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text('标注锚点', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (anchors.isEmpty)
            Text(
              '选择页面文字后，点击底部颜色保存。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            )
          else
            for (final anchor in anchors.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anchor.quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'p.${anchor.page} · ${anchor.pageStart}..${anchor.pageEnd} · ${anchor.pdfRects.length} rects',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Text(value, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
