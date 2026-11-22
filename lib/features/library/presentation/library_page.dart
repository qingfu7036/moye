import 'dart:async';

import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/models/book.dart';
import '../data/book_picker.dart';
import '../data/library_repository.dart';
import 'widgets/book_details_panel.dart';
import 'widgets/library_results.dart';
import 'widgets/library_toolbar.dart';

enum _DeleteBookChoice { cancel, keepAnnotations, deleteAll }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _selectedBookId;
  bool _gridMode = true;
  bool _importing = false;
  final ValueNotifier<bool> _deleting = ValueNotifier<bool>(false);
  String? _importProgress;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _deleting.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      ref.read(libraryFilterProvider.notifier).setQuery(value);
    });
  }

  Future<void> _importBooks() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _importProgress = '选择文件…';
    });
    final outcomes = <ImportOutcome>[];
    try {
      final files = await ref.read(bookPickerProvider).pickBooks();
      if (!mounted || files.isEmpty) return;
      for (var i = 0; i < files.length; i++) {
        if (!mounted) break;
        setState(() => _importProgress = '${i + 1} / ${files.length}');
        final picked = files[i];
        try {
          outcomes.add(
            await ref
                .read(libraryRepositoryProvider)
                .importStream(
                  sourceName: picked.name,
                  source: picked.openStream(),
                ),
          );
        } catch (error) {
          outcomes.add(
            ImportOutcome(
              kind: ImportOutcomeKind.failed,
              sourceName: picked.name,
              message: '导入失败：$error',
            ),
          );
        }
      }
      if (!mounted) return;
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(storageStatsProvider);
      final imported = outcomes
          .where((outcome) => outcome.kind == ImportOutcomeKind.imported)
          .toList();
      if (imported.length == 1) {
        _selectedBookId = imported.single.book?.id;
      }
      _showImportSummary(outcomes);
    } catch (error) {
      if (mounted) _message('无法选择文件：$error');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importProgress = null;
        });
      }
    }
  }

  void _showImportSummary(List<ImportOutcome> outcomes) {
    final imported = outcomes
        .where((outcome) => outcome.kind == ImportOutcomeKind.imported)
        .length;
    final duplicates = outcomes
        .where((outcome) => outcome.kind == ImportOutcomeKind.duplicate)
        .length;
    final unsupported = outcomes
        .where((outcome) => outcome.kind == ImportOutcomeKind.unsupported)
        .length;
    final failed = outcomes
        .where((outcome) => outcome.kind == ImportOutcomeKind.failed)
        .length;
    final parts = <String>[
      if (imported > 0) '已导入 $imported 本',
      if (duplicates > 0) '$duplicates 本重复',
      if (unsupported > 0) '$unsupported 个格式不支持',
      if (failed > 0) '$failed 个失败',
    ];
    if (parts.isEmpty) parts.add('没有导入任何书籍');
    final firstError = outcomes
        .where((outcome) => outcome.kind == ImportOutcomeKind.failed)
        .map((outcome) => outcome.message)
        .firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${parts.join(' · ')}${firstError == null ? '' : '\n$firstError'}',
          key: const Key('library-import-summary'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _updateStatus(Book book, BookStatus status) async {
    if (status == book.status) return;
    try {
      await ref.read(libraryRepositoryProvider).updateStatus(book.id, status);
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(storageStatsProvider);
      _message('已将《${book.title}》设为“${status.label}”');
    } catch (error) {
      _message('更新阅读状态失败：$error');
    }
  }

  Future<bool> _deleteBook(Book book) async {
    if (_deleting.value) return false;
    final counts = await ref
        .read(libraryRepositoryProvider)
        .relatedDataCounts(book.id);
    if (!mounted) return false;
    final hasAnnotations = counts.annotations > 0;
    final relatedWarning = counts.annotations == 0 && counts.bookmarks == 0
        ? '本书没有区域标记或书签。'
        : '本书有 ${counts.annotations} 条区域标记和 '
              '${counts.bookmarks} 个书签。';
    final choice = await showDialog<_DeleteBookChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从书库删除？'),
        content: Text(
          '将删除《${book.title}》的数据库记录和复制到书库的文件。原始导入文件不受影响。\n\n'
          '$relatedWarning\n\n'
          '${hasAnnotations ? '选择“保留标记”可把区域标记留在知识仓库，书签仍会删除。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteBookChoice.cancel),
            child: const Text('取消'),
          ),
          if (hasAnnotations)
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, _DeleteBookChoice.keepAnnotations),
              child: const Text('保留标记并删书'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _DeleteBookChoice.deleteAll),
            style: FilledButton.styleFrom(backgroundColor: MoyeColors.rose),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _DeleteBookChoice.cancel || !mounted) {
      return false;
    }
    final keepAnnotations = choice == _DeleteBookChoice.keepAnnotations;
    _deleting.value = true;
    var success = false;
    try {
      await ref
          .read(libraryRepositoryProvider)
          .deleteBook(book.id, keepAnnotations: keepAnnotations);
      _selectedBookId = null;
      ref.invalidate(libraryBooksProvider);
      ref.invalidate(storageStatsProvider);
      _message(
        keepAnnotations ? '已删除《${book.title}》，区域标记已保留' : '已删除《${book.title}》',
      );
      success = true;
    } catch (error) {
      _message('删除失败：$error');
    } finally {
      if (mounted) _deleting.value = false;
    }
    return success;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(coverBackfillProvider);
    final booksAsync = ref.watch(libraryBooksProvider);
    final filter = ref.watch(libraryFilterProvider);
    final books = booksAsync.asData?.value ?? const <Book>[];
    Book? selectedBook;
    for (final book in books) {
      if (book.id == _selectedBookId) selectedBook = book;
    }
    final filterActive = filter.query.isNotEmpty || filter.status != null;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          LibraryToolbar(
            bookCount: books.length,
            filter: filter,
            searchController: _searchController,
            importing: _importing,
            importProgress: _importProgress,
            gridMode: _gridMode,
            onImport: _importBooks,
            onQueryChanged: _onQueryChanged,
            onStatusChanged: (status) =>
                ref.read(libraryFilterProvider.notifier).setStatus(status),
            onSortChanged: (sort) =>
                ref.read(libraryFilterProvider.notifier).setSort(sort),
            onViewChanged: () => setState(() => _gridMode = !_gridMode),
            onRefresh: () {
              ref.invalidate(libraryBooksProvider);
              ref.invalidate(storageStatsProvider);
            },
            onClearFilters: _clearFilters,
          ),
          if (booksAsync.isLoading && booksAsync.hasValue)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (booksAsync.isLoading && !booksAsync.hasValue) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (booksAsync.hasError && !booksAsync.hasValue) {
                  return _LibraryError(
                    error: booksAsync.error,
                    onRetry: () => ref.invalidate(libraryBooksProvider),
                  );
                }
                final wide = constraints.maxWidth >= 1050;
                final results = LibraryResults(
                  books: books,
                  filterActive: filterActive,
                  gridMode: _gridMode,
                  selectedBookId: _selectedBookId,
                  onTap: (book) => _openBook(book, wide),
                  onClearFilters: _clearFilters,
                  onImport: _importBooks,
                );
                if (!wide || selectedBook == null) return results;
                return Row(
                  children: [
                    Expanded(child: results),
                    SizedBox(
                      width: 338,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _deleting,
                        builder: (context, deleting, child) => BookDetailsPanel(
                          book: selectedBook!,
                          deleting: deleting,
                          onRead:
                              (selectedBook.format == BookFormat.pdf ||
                                  selectedBook.format == BookFormat.epub)
                              ? () => _openReader(selectedBook!)
                              : null,
                          onOpenAnnotations:
                              (selectedBook.format == BookFormat.pdf ||
                                  selectedBook.format == BookFormat.epub)
                              ? () => context.push(
                                  '/book/${selectedBook!.id}/annotations',
                                )
                              : null,
                          onStatusChanged: (status) =>
                              _updateStatus(selectedBook!, status),
                          onDelete: () => _deleteBook(selectedBook!),
                          onClose: () => setState(() => _selectedBookId = null),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReader(Book book) async {
    final path = switch (book.format) {
      BookFormat.pdf => '/reader/${book.id}',
      BookFormat.epub => '/reader/epub/${book.id}',
      _ => null,
    };
    if (path == null) return;
    await context.push(path);
    if (!mounted) return;
    // The reader updates last_opened_at and progress in SQLite. Refresh the
    // list so the details panel/timestamps do not stay stale after returning.
    ref.invalidate(libraryBooksProvider);
    ref.invalidate(storageStatsProvider);
  }

  void _openBook(Book book, bool wide) {
    if (wide) {
      setState(() => _selectedBookId = book.id);
    } else {
      _showBookSheet(book.id);
    }
  }

  void _showBookSheet(String bookId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.92,
        child: Consumer(
          builder: (context, ref, child) {
            final async = ref.watch(libraryBooksProvider);
            final books = async.asData?.value ?? const <Book>[];
            Book? current;
            for (final book in books) {
              if (book.id == bookId) current = book;
            }
            if (current == null) {
              return const Center(child: Text('这本书已不在当前书库中'));
            }
            return ValueListenableBuilder<bool>(
              valueListenable: _deleting,
              builder: (context, deleting, child) => BookDetailsPanel(
                book: current!,
                deleting: deleting,
                onRead:
                    (current.format == BookFormat.pdf ||
                        current.format == BookFormat.epub)
                    ? () async {
                        Navigator.pop(sheetContext);
                        await _openReader(current!);
                      }
                    : null,
                onOpenAnnotations:
                    (current.format == BookFormat.pdf ||
                        current.format == BookFormat.epub)
                    ? () {
                        Navigator.pop(sheetContext);
                        context.push('/book/${current!.id}/annotations');
                      }
                    : null,
                onClose: () => Navigator.pop(sheetContext),
                onStatusChanged: (status) => _updateStatus(current!, status),
                onDelete: () async {
                  final deleted = await _deleteBook(current!);
                  if (deleted && sheetContext.mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    final notifier = ref.read(libraryFilterProvider.notifier);
    notifier.setQuery('');
    notifier.setStatus(null);
    notifier.setSort(BookSort.recentlyAdded);
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 38,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text('书库读取失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
