import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/book.dart';
import 'book_card.dart';

class BookDetailsPanel extends StatelessWidget {
  const BookDetailsPanel({
    super.key,
    required this.book,
    required this.onStatusChanged,
    required this.onDelete,
    this.onRead,
    this.onOpenAnnotations,
    this.onClose,
    this.deleting = false,
  });

  final Book book;
  final ValueChanged<BookStatus> onStatusChanged;
  final VoidCallback onDelete;
  final VoidCallback? onRead;
  final VoidCallback? onOpenAnnotations;
  final VoidCallback? onClose;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('book-details'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
            child: Row(
              children: [
                Text('书籍信息', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    tooltip: '关闭',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: [
                Center(
                  child: SizedBox(
                    width: 142,
                    height: 190,
                    child: BookCover(book: book),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  book.title,
                  key: const Key('details-title'),
                  style: theme.textTheme.titleLarge?.copyWith(height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  book.author.isEmpty ? '未知作者' : book.author,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FormatBadge(format: book.format),
                    const SizedBox(width: 7),
                    StatusBadge(status: book.status),
                  ],
                ),
                if (onRead != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('open-reader-button'),
                      onPressed: deleting ? null : onRead,
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: const Text('开始阅读'),
                    ),
                  ),
                ],
                if (onOpenAnnotations != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('open-annotations-button'),
                      onPressed: deleting ? null : onOpenAnnotations,
                      icon: const Icon(Icons.crop_free_rounded, size: 18),
                      label: const Text('本书标记与备注'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text('阅读状态', style: theme.textTheme.labelLarge),
                const SizedBox(height: 7),
                InputDecorator(
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<BookStatus>(
                      key: ValueKey('status-${book.id}'),
                      value: book.status,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final status in BookStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (status) {
                        if (status != null) onStatusChanged(status);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '阅读状态由你手动设置；打开阅读器只更新最近阅读时间，不会自动改状态。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _SectionTitle('文件'),
                _InfoRow(label: '格式', value: book.format.label),
                _InfoRow(label: '大小', value: _formatSize(book.fileSize)),
                _InfoRow(label: '原始文件名', value: book.originalFileName),
                _InfoRow(label: '书库路径', value: book.relativePath),
                _InfoRow(
                  label: '文件哈希',
                  value: '${book.fileHash.substring(0, 12)}…',
                  mono: true,
                ),
                _InfoRow(
                  label: '元数据来源',
                  value: _metadataLabel(book.metadataSource),
                ),
                _InfoRow(label: '导入时间', value: formatDate(book.addedAt)),
                if (book.lastOpenedAt != null)
                  _InfoRow(
                    label: '最近阅读',
                    value: formatDate(book.lastOpenedAt!),
                  ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 17,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '阅读器将在 Phase 2 接入。当前阶段只验证书库、文件归档与阅读状态。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.68),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: deleting ? null : onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MoyeColors.rose,
                    side: BorderSide(
                      color: MoyeColors.rose.withValues(alpha: 0.5),
                    ),
                  ),
                  icon: deleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('从书库删除'),
                ),
                const SizedBox(height: 6),
                Text(
                  '删除会移除数据库记录、书籍文件，以及本书的区域标记和书签。',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _metadataLabel(String source) {
    return switch (source) {
      'epub_opf' => 'EPUB OPF',
      'docx_core' => 'DOCX 核心属性',
      _ => '文件名',
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? 'Consolas' : null,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
