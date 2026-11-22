import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/models/annotation.dart';

class AllAnnotationsPage extends ConsumerStatefulWidget {
  const AllAnnotationsPage({super.key});

  @override
  ConsumerState<AllAnnotationsPage> createState() => _AllAnnotationsPageState();
}

class _AllAnnotationsPageState extends ConsumerState<AllAnnotationsPage> {
  final TextEditingController _search = TextEditingController();
  List<AnnotationWithBook> _items = const [];
  Timer? _debounce;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_scheduleLoad);
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search
      ..removeListener(_scheduleLoad)
      ..dispose();
    super.dispose();
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ref
          .read(libraryRepositoryProvider)
          .listAllAnnotations(query: _search.text);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _delete(AnnotationWithBook item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条标记？'),
        content: const Text('标记和截图会从本书仓库中移除，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(libraryRepositoryProvider)
        .deleteAnnotation(item.annotation.id);
    if (!mounted) return;
    setState(() {
      _items = _items
          .where((entry) => entry.annotation.id != item.annotation.id)
          .toList();
    });
  }

  Future<void> _show(AnnotationWithBook item) async {
    final annotation = item.annotation;
    final image = annotation.imagePath == null
        ? null
        : ref
              .read(appServicesProvider)
              .paths
              .resolveRelative(annotation.imagePath!);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.bookTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null && image.existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(image, width: 360, fit: BoxFit.contain),
                ),
              const SizedBox(height: 12),
              Text(
                _locationLabel(annotation),
                style: Theme.of(dialogContext).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(
                annotation.note.isEmpty ? '（无备注）' : annotation.note,
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('yyyy-MM-dd HH:mm')
                    .format(annotation.createdAt.toLocal()),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('知识仓库', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  '所有书籍的区域标记与备注；按备注或原文搜索。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('all-annotations-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: '搜索所有书的标记与备注',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('读取知识仓库失败：$_error'),
            )
          else if (_items.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _search.text.trim().isEmpty ? '还没有区域标记。' : '没有匹配的标记。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _AnnotationCard(
                  item: _items[index],
                  onTap: () => unawaited(_show(_items[index])),
                  onDelete: () => unawaited(_delete(_items[index])),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final AnnotationWithBook item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final annotation = item.annotation;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.crop_free_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.bookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _locationLabel(annotation),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      annotation.note.isEmpty ? '（无备注）' : annotation.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除标记',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _locationLabel(RegionAnnotation annotation) {
  if (annotation.pageNumber != null) return '第 ${annotation.pageNumber} 页';
  if (annotation.chapterIndex != null) {
    return '第 ${annotation.chapterIndex! + 1} 章 · '
        '第 ${(annotation.blockIndex ?? 0) + 1} 段';
  }
  return '标记';
}
