import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';

class BookMetadata {
  const BookMetadata({
    required this.title,
    required this.author,
    required this.source,
  });

  final String title;
  final String author;
  final String source;
}

/// Extracts the small metadata subset needed by the Phase 1 library.
///
/// PDF metadata extraction is deferred to the Phase 2 engine integration; PDF
/// books still get a useful title from the original file name and can be
/// renamed by the user in a later phase.
class BookMetadataExtractor {
  const BookMetadataExtractor();

  Future<BookMetadata> extract({
    required File file,
    required BookFormat format,
    required String fallbackTitle,
  }) async {
    final fallback = _normaliseTitle(fallbackTitle);
    try {
      switch (format) {
        case BookFormat.epub:
          final metadata = await _epubMetadata(file);
          return BookMetadata(
            title: metadata.$1 ?? fallback,
            author: metadata.$2 ?? '',
            source: metadata.$1 == null ? 'file_name' : 'epub_opf',
          );
        case BookFormat.docx:
          final metadata = await _docxMetadata(file);
          return BookMetadata(
            title: metadata.$1 ?? fallback,
            author: metadata.$2 ?? '',
            source: metadata.$1 == null ? 'file_name' : 'docx_core',
          );
        case BookFormat.pdf:
        case BookFormat.doc:
        case BookFormat.txt:
        case BookFormat.markdown:
          return BookMetadata(
            title: fallback,
            author: '',
            source: 'file_name',
          );
      }
    } catch (_) {
      return BookMetadata(title: fallback, author: '', source: 'file_name');
    }
  }

  Future<(String?, String?)> _epubMetadata(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final files = _archiveFiles(archive);
    final container = files['META-INF/container.xml'];
    if (container == null) return (null, null);
    final containerXml = _parseXml(container.readBytes()!);
    final rootfile = containerXml
        .descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null) return (null, null);
    final opf = files[_normalise(opfPath)];
    if (opf == null) return (null, null);
    final document = _parseXml(opf.readBytes()!);
    final metadata = document
        .descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'metadata')
        .firstOrNull;
    return (
      _textOf(metadata, 'title'),
      _textOf(metadata, 'creator'),
    );
  }

  Future<(String?, String?)> _docxMetadata(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final core = _archiveFiles(archive)['docProps/core.xml'];
    if (core == null) return (null, null);
    final document = _parseXml(core.readBytes()!);
    return (
      _textOf(document, 'title'),
      _textOf(document, 'creator'),
    );
  }

  static Map<String, ArchiveFile> _archiveFiles(Archive archive) {
    final result = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) result[_normalise(file.name)] = file;
    }
    return result;
  }

  static XmlDocument _parseXml(List<int> bytes) {
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  }

  static String? _textOf(XmlNode? parent, String localName) {
    if (parent == null) return null;
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) {
        final text = element.innerText.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  static String _normalise(String value) =>
      p.posix.normalize(value.replaceAll('\\', '/'));

  static String _normaliseTitle(String value) {
    final title = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return title.isEmpty ? '未命名书籍' : title;
  }
}
