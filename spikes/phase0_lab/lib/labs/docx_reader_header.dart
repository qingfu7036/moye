import 'package:flutter/material.dart';

import '../engines/docx/docx_document.dart';

class DocxReaderHeader extends StatelessWidget {
  const DocxReaderHeader({
    super.key,
    required this.document,
    required this.fontSize,
    required this.path,
    required this.annotationCount,
    required this.onFontDown,
    required this.onFontUp,
    required this.onProbe,
  });

  final DocxDocument document;
  final double fontSize;
  final String path;
  final int annotationCount;
  final VoidCallback? onFontDown;
  final VoidCallback? onFontUp;
  final VoidCallback onProbe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final identity = Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'DOCX',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.title,
                  key: const Key('docx-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${document.author} · ${document.blocks.length} 个内容块 · '
                  '${_count(document, DocxBlockKind.image)} 张图片 · '
                  '${_count(document, DocxBlockKind.table)} 个表格',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final controls = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '减小字号',
                visualDensity: VisualDensity.compact,
                onPressed: onFontDown,
                icon: const Icon(Icons.text_decrease_rounded, size: 18),
              ),
              Text('${fontSize.round()}', style: theme.textTheme.labelMedium),
              IconButton(
                tooltip: '增大字号',
                visualDensity: VisualDensity.compact,
                onPressed: onFontUp,
                icon: const Icon(Icons.text_increase_rounded, size: 18),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          key: const Key('docx-probe'),
          onPressed: onProbe,
          icon: const Icon(Icons.my_location_rounded, size: 16),
          label: const Text('定位验证'),
        ),
      ],
    );

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(18, 12, 16, 11),
      child: Column(
        children: [
          Row(children: [identity, const SizedBox(width: 12), controls]),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 14, color: scheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '当前段落路径  $path',
                  key: const Key('docx-path-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '$annotationCount 条标注',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _count(DocxDocument doc, DocxBlockKind kind) =>
      doc.blocks.where((block) => block.kind == kind).length;
}
