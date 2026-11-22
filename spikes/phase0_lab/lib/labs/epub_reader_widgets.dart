import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/reading_anchor.dart';
import '../engines/epub/epub_document.dart';

class ReaderPalette {
  const ReaderPalette({
    required this.name,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.panel,
    required this.divider,
  });

  final String name;
  final Color background;
  final Color foreground;
  final Color muted;
  final Color panel;
  final Color divider;
}

const readerPalettes = [
  ReaderPalette(
    name: '雾纸',
    background: Color(0xFFF2F6F1),
    foreground: Color(0xFF202A24),
    muted: Color(0xFF63716A),
    panel: Color(0xFFFFFFFF),
    divider: Color(0xFFDDE6DF),
  ),
  ReaderPalette(
    name: '暖页',
    background: Color(0xFFF1EBDD),
    foreground: Color(0xFF2C271E),
    muted: Color(0xFF786C59),
    panel: Color(0xFFF8F3E8),
    divider: Color(0xFFE2D7C3),
  ),
  ReaderPalette(
    name: '夜读',
    background: Color(0xFF121815),
    foreground: Color(0xFFDDE6E0),
    muted: Color(0xFF8B9A91),
    panel: Color(0xFF1B231F),
    divider: Color(0xFF2C3831),
  ),
];

class EpubHeader extends StatelessWidget {
  const EpubHeader({
    super.key,
    required this.book,
    required this.chapter,
    required this.chapterIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.palette,
    required this.onChapter,
    required this.onFontDown,
    required this.onFontUp,
    required this.onLineHeight,
    required this.onCyclePalette,
    required this.cfi,
    required this.annotationCount,
  });

  final EpubDocument book;
  final EpubChapter chapter;
  final int chapterIndex;
  final double fontSize;
  final double lineHeight;
  final ReaderPalette palette;
  final ValueChanged<int> onChapter;
  final VoidCallback? onFontDown;
  final VoidCallback? onFontUp;
  final ValueChanged<double> onLineHeight;
  final VoidCallback onCyclePalette;
  final String cfi;
  final int annotationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: palette.panel,
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          final identity = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.foreground.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'EPUB 3',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      key: const Key('epub-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: palette.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${book.author} · ${book.chapters.length} 章 · ${book.resourceCount} 个资源',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final controls = Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<int>(
                tooltip: '章节目录',
                onSelected: onChapter,
                itemBuilder: (context) => [
                  for (var i = 0; i < book.chapters.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Text(book.chapters[i].title),
                    ),
                ],
                child: _ControlChip(
                  icon: Icons.format_list_bulleted_rounded,
                  label: chapter.title,
                  palette: palette,
                ),
              ),
              _ControlGroup(
                palette: palette,
                children: [
                  IconButton(
                    tooltip: '缩小字号',
                    onPressed: onFontDown,
                    icon: const Icon(Icons.text_decrease_rounded, size: 19),
                  ),
                  Text(
                    fontSize.toStringAsFixed(0),
                    key: const Key('epub-font-size'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.foreground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    tooltip: '放大字号',
                    key: const Key('epub-font-increase'),
                    onPressed: onFontUp,
                    icon: const Icon(Icons.text_increase_rounded, size: 19),
                  ),
                ],
              ),
              PopupMenuButton<double>(
                tooltip: '行距',
                initialValue: lineHeight,
                onSelected: onLineHeight,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 1.5, child: Text('紧凑行距 1.5')),
                  PopupMenuItem(value: 1.8, child: Text('舒适行距 1.8')),
                  PopupMenuItem(value: 2.1, child: Text('宽松行距 2.1')),
                ],
                child: _ControlChip(
                  icon: Icons.format_line_spacing_rounded,
                  label: lineHeight.toStringAsFixed(1),
                  palette: palette,
                ),
              ),
              IconButton(
                tooltip: '切换阅读主题',
                onPressed: onCyclePalette,
                icon: Icon(
                  Icons.contrast_rounded,
                  size: 19,
                  color: palette.foreground,
                ),
              ),
            ],
          );
          if (wide) {
            return Row(
              children: [
                Flexible(child: identity),
                const Spacer(),
                controls,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 8), controls],
          );
        },
      ),
    );
  }
}

class EpubSelectionBar extends StatelessWidget {
  const EpubSelectionBar({
    super.key,
    required this.text,
    required this.palette,
    required this.onSave,
  });

  final String text;
  final ReaderPalette palette;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: palette.panel,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('epub-save-annotation'),
                onPressed: onSave,
                icon: const Icon(Icons.border_color_outlined, size: 17),
                label: const Text('保存高亮'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EpubBlockView extends StatelessWidget {
  const EpubBlockView({
    super.key,
    required this.block,
    required this.spans,
    required this.style,
    required this.palette,
    required this.isListItem,
  });

  final EpubBlock block;
  final List<InlineSpan> spans;
  final TextStyle style;
  final ReaderPalette palette;
  final bool isListItem;

  @override
  Widget build(BuildContext context) {
    if (block.kind == EpubBlockKind.image) {
      final bytes = block.imageBytes;
      if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes,
                height: 260,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (block.imageAlt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  block.imageAlt,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.muted,
                      ),
                ),
              ),
          ],
        ),
      );
    }
    final rich = Text.rich(TextSpan(children: spans, style: style));
    if (!isListItem) {
      return Padding(
        padding: EdgeInsets.only(bottom: block.kind == EpubBlockKind.heading1 ? 18 : 12),
        child: rich,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Text('•', style: style.copyWith(color: palette.muted)),
          ),
          Expanded(child: rich),
        ],
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: palette.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: palette.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.foreground,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.palette, required this.children});

  final ReaderPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

List<InlineSpan> buildEpubSpans(
  EpubBlock block,
  List<ReadingAnchor> annotations,
  int spineIndex,
  int blockIndex,
  Color highlight,
) {
  final text = block.text;
  if (text.isEmpty) return const [TextSpan(text: '')];
  final relevant = annotations
      .where((anchor) =>
          anchor.spineIndex == spineIndex && anchor.blockIndex == blockIndex)
      .toList();
  if (relevant.isEmpty) return [TextSpan(text: text)];
  relevant.sort((a, b) => (a.pageStart ?? 0).compareTo(b.pageStart ?? 0));
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final anchor in relevant) {
    final start = (anchor.pageStart ?? 0).clamp(0, text.length);
    final end = (anchor.pageEnd ?? start).clamp(start, text.length);
    if (start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, start)));
    }
    children.add(TextSpan(
      text: text.substring(start, end),
      style: TextStyle(backgroundColor: highlight.withValues(alpha: 0.38)),
    ));
    cursor = end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return children.isEmpty ? [TextSpan(text: text)] : children;
}

double clampReaderFont(double value) => value.clamp(14, 32).toDouble();

double clampLineHeight(double value) => value.clamp(1.4, 2.2).toDouble();

int nextPaletteIndex(int current) => (current + 1) % readerPalettes.length;

String compactCfi(String cfi) {
  final start = math.max(0, cfi.length - 52);
  return cfi.length <= 52 ? cfi : '…${cfi.substring(start)}';
}
