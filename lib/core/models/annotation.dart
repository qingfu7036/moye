class RegionAnnotation {
  const RegionAnnotation({
    required this.id,
    required this.bookId,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.note,
    required this.createdAt,
    this.pageNumber,
    this.chapterIndex,
    this.blockIndex,
    this.quote = '',
    this.imagePath,
    this.color = 'yellow',
  });

  final String id;
  final String? bookId;
  final int? pageNumber;
  final int? chapterIndex;
  final int? blockIndex;

  /// Normalized rectangle (0..1) relative to the visible reader content.
  final double left;
  final double top;
  final double width;
  final double height;
  final String note;
  final String quote;
  final String? imagePath;
  final String color;
  final DateTime createdAt;
}

class AnnotationWithBook {
  const AnnotationWithBook({required this.annotation, required this.bookTitle});

  final RegionAnnotation annotation;
  final String bookTitle;
}
