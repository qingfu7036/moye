import 'package:path/path.dart' as p;

enum BookFormat {
  pdf('PDF'),
  epub('EPUB'),
  docx('DOCX'),
  doc('DOC'),
  txt('TXT'),
  markdown('Markdown');

  const BookFormat(this.label);

  final String label;

  bool get isReadingSupported => this != BookFormat.doc;

  static BookFormat? fromFileName(String name) {
    final extension = p.extension(name).toLowerCase();
    return switch (extension) {
      '.pdf' => BookFormat.pdf,
      '.epub' => BookFormat.epub,
      '.docx' => BookFormat.docx,
      '.doc' => BookFormat.doc,
      '.txt' => BookFormat.txt,
      '.md' || '.markdown' => BookFormat.markdown,
      _ => null,
    };
  }

  static BookFormat fromStorage(String value) => BookFormat.values.firstWhere(
        (format) => format.name == value,
        orElse: () => BookFormat.txt,
      );
}

enum BookStatus {
  notStarted('未开始'),
  reading('正在阅读'),
  paused('暂时搁置'),
  finished('已读完'),
  reread('以后再读');

  const BookStatus(this.label);

  final String label;

  static BookStatus fromStorage(String value) => BookStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => BookStatus.notStarted,
      );
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.originalFileName,
    required this.relativePath,
    required this.fileHash,
    required this.fileSize,
    required this.status,
    required this.addedAt,
    required this.updatedAt,
    required this.metadataSource,
    this.coverPath,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String author;
  final BookFormat format;
  final String originalFileName;
  final String relativePath;
  final String fileHash;
  final int fileSize;
  final String? coverPath;
  final BookStatus status;
  final DateTime addedAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final String metadataSource;

  Book copyWith({
    String? title,
    String? author,
    BookStatus? status,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format,
      originalFileName: originalFileName,
      relativePath: relativePath,
      fileHash: fileHash,
      fileSize: fileSize,
      coverPath: coverPath,
      status: status ?? this.status,
      addedAt: addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      metadataSource: metadataSource,
    );
  }
}

enum BookSort {
  recentlyAdded('最近导入'),
  title('书名'),
  recentlyOpened('最近阅读');

  const BookSort(this.label);

  final String label;
}

class LibraryFilter {
  const LibraryFilter({
    this.query = '',
    this.status,
    this.sort = BookSort.recentlyAdded,
  });

  final String query;
  final BookStatus? status;
  final BookSort sort;

  bool get isDefault =>
      query.isEmpty && status == null && sort == BookSort.recentlyAdded;

  LibraryFilter copyWith({
    String? query,
    BookStatus? status,
    bool clearStatus = false,
    BookSort? sort,
  }) {
    return LibraryFilter(
      query: query ?? this.query,
      status: clearStatus ? null : (status ?? this.status),
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      other.query == query &&
      other.status == status &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, status, sort);
}

class StorageStats {
  const StorageStats({
    required this.bookCount,
    required this.totalBookBytes,
    required this.databaseVersion,
    required this.dataRoot,
  });

  final int bookCount;
  final int totalBookBytes;
  final int databaseVersion;
  final String dataRoot;
}
