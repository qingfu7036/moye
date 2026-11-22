import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers.dart';
import '../../../../core/models/bookmark.dart';

Future<void> showBookmarksSheet({
  required BuildContext context,
  required String bookId,
  required String currentLabel,
  required Future<void> Function() onAddCurrent,
  required void Function(Bookmark bookmark) onJump,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _BookmarksSheet(
      bookId: bookId,
      currentLabel: currentLabel,
      onAddCurrent: onAddCurrent,
      onJump: onJump,
    ),
  );
}

class _BookmarksSheet extends ConsumerStatefulWidget {
  const _BookmarksSheet({
    required this.bookId,
    required this.currentLabel,
    required this.onAddCurrent,
    required this.onJump,
  });

  final String bookId;
  final String currentLabel;
  final Future<void> Function() onAddCurrent;
  final void Function(Bookmark bookmark) onJump;

  @override
  ConsumerState<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends ConsumerState<_BookmarksSheet> {
  List<Bookmark> _bookmarks = const [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bookmarks = await ref
          .read(libraryRepositoryProvider)
          .listBookmarks(widget.bookId);
      if (!mounted) return;
      setState(() {
        _bookmarks = bookmarks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await widget.onAddCurrent();
      await _load();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(Bookmark bookmark) async {
    await ref.read(libraryRepositoryProvider).deleteBookmark(bookmark.id);
    if (!mounted) return;
    setState(
      () => _bookmarks = _bookmarks.where((b) => b.id != bookmark.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 12, 4),
            child: Row(
              children: [
                Text('书签', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  key: const Key('bookmark-add-current'),
                  onPressed: _adding ? null : _add,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text('添加${widget.currentLabel}'),
                ),
                IconButton(
                  tooltip: '关闭书签',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: Text(
                '还没有书签。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                itemCount: _bookmarks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final bookmark = _bookmarks[index];
                  return ListTile(
                    leading: const Icon(Icons.bookmark_rounded),
                    title: Text(
                      bookmark.label.isEmpty
                          ? bookmark.locationLabel
                          : bookmark.label,
                    ),
                    subtitle: Text(
                      '${bookmark.locationLabel} · '
                      '${DateFormat('yyyy-MM-dd HH:mm').format(bookmark.createdAt.toLocal())}',
                    ),
                    onTap: () {
                      widget.onJump(bookmark);
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      tooltip: '删除书签',
                      onPressed: () => unawaited(_delete(bookmark)),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
