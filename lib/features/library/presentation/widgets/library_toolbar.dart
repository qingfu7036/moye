import 'package:flutter/material.dart';

import '../../../../core/models/book.dart';

class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.bookCount,
    required this.filter,
    required this.searchController,
    required this.importing,
    required this.importProgress,
    required this.gridMode,
    required this.onImport,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onViewChanged,
    required this.onRefresh,
    required this.onClearFilters,
  });

  final int bookCount;
  final LibraryFilter filter;
  final TextEditingController searchController;
  final bool importing;
  final String? importProgress;
  final bool gridMode;
  final VoidCallback onImport;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<BookStatus?> onStatusChanged;
  final ValueChanged<BookSort> onSortChanged;
  final VoidCallback onViewChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '我的书库',
                          style: compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '$bookCount 本',
                            key: const Key('library-book-count'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '书籍文件已复制到应用私有目录；原始文件移动后不影响书库。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '刷新书库',
                visualDensity:
                    compact ? VisualDensity.compact : VisualDensity.standard,
                onPressed: importing ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
              const SizedBox(width: 2),
              FilledButton.icon(
                key: const Key('import-books-button'),
                style: compact
                    ? FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      )
                    : null,
                onPressed: importing ? null : onImport,
                icon: importing
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 19),
                label: Text(
                  importing
                      ? (importProgress ?? '导入中')
                      : (compact ? '导入' : '导入书籍'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('library-search'),
                  controller: searchController,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    hintText: '搜索书名或作者',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: filter.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<BookSort>(
                tooltip: '排序',
                initialValue: filter.sort,
                onSelected: onSortChanged,
                itemBuilder: (context) => [
                  for (final sort in BookSort.values)
                    PopupMenuItem(value: sort, child: Text(sort.label)),
                ],
                child: _ToolbarButton(
                  icon: Icons.sort_rounded,
                  label: filter.sort.label,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('library-view-toggle'),
                tooltip: gridMode ? '切换列表视图' : '切换网格视图',
                onPressed: onViewChanged,
                icon: Icon(
                  gridMode ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _StatusFilterChip(
                  label: '全部',
                  selected: filter.status == null,
                  onSelected: () => onStatusChanged(null),
                ),
                for (final status in BookStatus.values) ...[
                  const SizedBox(width: 6),
                  _StatusFilterChip(
                    label: status.label,
                    selected: filter.status == status,
                    onSelected: () => onStatusChanged(status),
                  ),
                ],
                if (!filter.isDefault) ...[
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: onClearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                    label: const Text('重置筛选'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 16),
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
