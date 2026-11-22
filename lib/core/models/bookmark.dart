class Bookmark {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.pageNumber,
    required this.chapterIndex,
    required this.blockIndex,
    required this.pageOffset,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final int? pageNumber;
  final int? chapterIndex;
  final int? blockIndex;
  final double pageOffset;
  final String label;
  final DateTime createdAt;

  String get locationLabel {
    if (pageNumber != null) return '第 $pageNumber 页';
    if (chapterIndex != null) {
      final block = blockIndex == null ? '' : ' · 第 ${blockIndex! + 1} 段';
      return '第 ${chapterIndex! + 1} 章$block';
    }
    return '书签';
  }
}
