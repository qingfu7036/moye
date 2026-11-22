class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.pageNumber,
    required this.percent,
    required this.updatedAt,
    this.pageOffset = 0,
    this.anchorJson,
  });

  final String bookId;
  final int pageNumber;
  final double percent;
  final double pageOffset;
  final DateTime updatedAt;
  final String? anchorJson;
}
