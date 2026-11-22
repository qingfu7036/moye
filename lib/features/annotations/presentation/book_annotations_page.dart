import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/models/annotation.dart';
import '../../../core/models/book.dart';

/// The per-book annotation warehouse. Region screenshots, notes and their
/// book/page/chapter anchors are kept together and searchable by note text.
class BookAnnotationsPage extends ConsumerStatefulWidget {
  const BookAnnotationsPage({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookAnnotationsPage> createState() =>
      _BookAnnotationsPageState();
}

class _BookAnnotationsPageState extends ConsumerState<BookAnnotationsPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  Book? _book;
  List<RegionAnnotation> _annotations = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([String query = '']) async {
    setState(() => _loading = true);
    try {
      final repository = ref.read(libraryRepositoryProvider);
      final book = await repository.findById(widget.bookId);
      final annotations = await repository.listAnnotations(
        widget.bookId,
        query: query,
      );
      if (!mounted) return;
      setState(() {
        _book = book;
        _annotations = annotations;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _load(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回书库',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本书仓库'),
            if (_book != null)
              Text(
                _book!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: TextField(
              key: const Key('annotation-search'),
              controller: _search,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: '搜索备注或摘录',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _search.clear();
                          _onSearch('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText('读取标记失败：$_error'),
        ),
      );
    }
    if (_annotations.isEmpty) {
      return Center(
        key: const Key('annotations-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.crop_free_rounded,
              size: 36,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 10),
            Text(
              _search.text.trim().isEmpty ? '这本书还没有标记' : '没有匹配的标记',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '打开 PDF/EPUB 阅读器，点击右下角框选按钮，拖一个长方形并写备注。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      key: const Key('annotations-list'),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      itemCount: _annotations.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final annotation = _annotations[index];
        final imageFile = annotation.imagePath == null
            ? null
            : ref
                  .read(appServicesProvider)
                  .paths
                  .resolveRelative(annotation.imagePath!);
        return _AnnotationCard(
          annotation: annotation,
          imageFile: imageFile,
          onTap: () => _showDetail(annotation),
        );
      },
    );
  }

  Future<void> _showDetail(RegionAnnotation annotation) async {
    final image = annotation.imagePath == null
        ? null
        : ref
              .read(appServicesProvider)
              .paths
              .resolveRelative(annotation.imagePath!);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_locationLabel(annotation)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null && image.existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(image, width: 340, fit: BoxFit.contain),
                ),
              const SizedBox(height: 12),
              SelectableText(
                annotation.note.isEmpty ? '（无备注）' : annotation.note,
              ),
              if (annotation.quote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '原文：${annotation.quote}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _locationLabel(RegionAnnotation annotation) {
    if (annotation.pageNumber != null) {
      return '第 ${annotation.pageNumber} 页';
    }
    if (annotation.chapterIndex != null) {
      return '第 ${annotation.chapterIndex! + 1} 章';
    }
    return '区域标记';
  }
}

class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({
    required this.annotation,
    required this.onTap,
    this.imageFile,
  });

  final RegionAnnotation annotation;
  final VoidCallback onTap;
  final File? imageFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = imageFile;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 72,
                child: file != null && file.existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(file, fit: BoxFit.cover),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.crop_free_rounded,
                          color: Colors.amber,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      annotation.note.isEmpty ? '（无备注）' : annotation.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${annotation.pageNumber != null ? '第 ${annotation.pageNumber} 页' : '第 ${(annotation.chapterIndex ?? 0) + 1} 章'}'
                      ' · ${DateFormat('yyyy-MM-dd HH:mm').format(annotation.createdAt.toLocal())}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
