import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/models/book.dart';
import 'book_card.dart';

class LibraryResults extends StatelessWidget {
  const LibraryResults({
    super.key,
    required this.books,
    required this.filterActive,
    required this.gridMode,
    required this.selectedBookId,
    required this.onTap,
    required this.onClearFilters,
    required this.onImport,
  });

  final List<Book> books;
  final bool filterActive;
  final bool gridMode;
  final String? selectedBookId;
  final ValueChanged<Book> onTap;
  final VoidCallback onClearFilters;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return filterActive
          ? _NoResults(onClear: onClearFilters)
          : _EmptyLibrary(onImport: onImport);
    }
    if (gridMode) {
      return GridView.builder(
        key: const Key('library-grid'),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 218,
          mainAxisExtent: 334,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          return BookCard(
            key: Key('book-card-${book.id}'),
            book: book,
            selected: book.id == selectedBookId,
            onTap: () => onTap(book),
          );
        },
      );
    }
    return ListView.separated(
      key: const Key('library-list'),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
      itemCount: books.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final book = books[index];
        return BookCard(
          key: Key('book-card-${book.id}'),
          book: book,
          selected: book.id == selectedBookId,
          listMode: true,
          onTap: () => onTap(book),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('library-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: MoyeColors.pineSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  size: 36,
                  color: MoyeColors.pine,
                ),
              ),
              const SizedBox(height: 20),
              Text('书库还是空的', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '导入 PDF、EPUB、DOCX、DOC、TXT 或 Markdown。书籍会复制到应用私有目录，原文件移动或删除不会影响书库。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('empty-import-button'),
                onPressed: onImport,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('导入第一本书'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('library-no-results'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 36,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text('没有匹配的书籍', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '换一个关键词，或重置阅读状态/排序筛选。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onClear,
            child: const Text('重置筛选'),
          ),
        ],
      ),
    );
  }
}
