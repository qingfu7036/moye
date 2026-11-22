import 'package:flutter/material.dart';

import '../core/reading_anchor.dart';
import '../engines/docx/docx_document.dart';

class DocxBlockView extends StatelessWidget {
  const DocxBlockView({
    super.key,
    required this.block,
    required this.blockIndex,
    required this.fontSize,
    required this.annotations,
    required this.highlightColor,
    required this.linkColor,
  });

  final DocxBlock block;
  final int blockIndex;
  final double fontSize;
  final List<ReadingAnchor> annotations;
  final Color highlightColor;
  final Color linkColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (block.kind == DocxBlockKind.image) {
      final bytes = block.image?.bytes;
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              height: 270,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => Text(
                '图片无法解码',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ),
      );
    }
    if (block.kind == DocxBlockKind.table) {
      return _DocxTable(
        block: block,
        fontSize: fontSize,
        scheme: scheme,
      );
    }

    final style = _styleFor(block.kind, scheme);
    final spans = _buildSpans(scheme);
    if (block.kind == DocxBlockKind.listItem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 9),
              child: Text('•', style: style.copyWith(color: scheme.primary)),
            ),
            Expanded(child: Text.rich(TextSpan(children: spans, style: style))),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: block.isHeading ? 18 : 6,
        bottom: block.isHeading ? 9 : 6,
      ),
      child: Text.rich(TextSpan(children: spans, style: style)),
    );
  }

  TextStyle _styleFor(DocxBlockKind kind, ColorScheme scheme) {
    final base = TextStyle(
      color: scheme.onSurface,
      fontSize: fontSize,
      height: 1.7,
    );
    return switch (kind) {
      DocxBlockKind.heading1 => base.copyWith(
          fontSize: fontSize + 12,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      DocxBlockKind.heading2 => base.copyWith(
          fontSize: fontSize + 8,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      DocxBlockKind.heading3 => base.copyWith(
          fontSize: fontSize + 5,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      DocxBlockKind.heading4 ||
      DocxBlockKind.heading5 ||
      DocxBlockKind.heading6 =>
        base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w600),
      DocxBlockKind.quote => base.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
      _ => base,
    };
  }

  List<InlineSpan> _buildSpans(ColorScheme scheme) {
    final text = block.text;
    if (text.isEmpty) return const [TextSpan(text: '')];
    final relevant = annotations
        .where((anchor) =>
            anchor.format == BookFormat.docx && anchor.blockIndex == blockIndex)
        .toList();
    if (relevant.isEmpty) {
      return _linkSpans(text, scheme);
    }
    relevant.sort((a, b) => (a.pageStart ?? 0).compareTo(b.pageStart ?? 0));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final anchor in relevant) {
      final start = (anchor.pageStart ?? 0).clamp(0, text.length).toInt();
      final end = (anchor.pageEnd ?? start).clamp(start, text.length).toInt();
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(TextSpan(
        text: text.substring(start, end),
        style: TextStyle(backgroundColor: highlightColor.withValues(alpha: 0.4)),
      ));
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  List<InlineSpan> _linkSpans(String text, ColorScheme scheme) {
    if (block.links.isEmpty) return [TextSpan(text: text)];
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in block.links) {
      if (link.text.isEmpty) continue;
      final index = text.indexOf(link.text, cursor);
      if (index < 0) continue;
      if (index > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, index)));
      }
      spans.add(TextSpan(
        text: link.text,
        style: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor.withValues(alpha: 0.5),
        ),
      ));
      cursor = index + link.text.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }
}

class _DocxTable extends StatelessWidget {
  const _DocxTable({
    required this.block,
    required this.fontSize,
    required this.scheme,
  });

  final DocxBlock block;
  final double fontSize;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final rows = block.table?.rows ?? const <List<String>>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.fold<int>(1, (max, row) => row.length > max ? row.length : max);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultColumnWidth: const FlexColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
          verticalInside: BorderSide(color: scheme.outlineVariant),
        ),
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex == 0
                    ? scheme.primary.withValues(alpha: 0.07)
                    : null,
              ),
              children: [
                for (var column = 0; column < columns; column++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(
                      column < rows[rowIndex].length ? rows[rowIndex][column] : '',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: fontSize - 1,
                        height: 1.45,
                        fontWeight: rowIndex == 0 ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class DocxSelectionBar extends StatelessWidget {
  const DocxSelectionBar({
    super.key,
    required this.text,
    required this.onSave,
  });

  final String text;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
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
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('docx-save-annotation'),
                onPressed: onSave,
                icon: const Icon(Icons.border_color_outlined, size: 17),
                label: const Text('保存标注'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
