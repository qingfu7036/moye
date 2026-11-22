import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';
import '../storage/app_paths.dart';

/// Extracts a real cover from the book itself and stores a normalized JPEG.
///
/// This deliberately does not use the title's first character as artwork. If
/// the format has no extractable cover, the caller keeps [Book.coverPath] null
/// and the UI renders a full-title fallback instead.
class BookCoverExtractor {
  const BookCoverExtractor();

  Future<String?> extract({
    required File file,
    required BookFormat format,
    required String bookId,
    required AppPaths paths,
  }) async {
    try {
      final bytes = switch (format) {
        BookFormat.pdf => await _pdfFirstPage(file, paths),
        BookFormat.epub => await _epubCover(file),
        BookFormat.docx => await _docxFirstImage(file),
        BookFormat.doc || BookFormat.txt || BookFormat.markdown => null,
      };
      if (bytes == null || bytes.isEmpty) return null;
      return await _saveJpeg(bytes, bookId, paths);
    } catch (_) {
      // A malformed or encrypted book must still import; it simply gets the
      // generated fallback cover in the library.
      return null;
    }
  }

  Future<Uint8List?> _pdfFirstPage(File file, AppPaths paths) async {
    Pdfrx.cacheDirectoryPath ??= paths.cacheDir.path;
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(file.path);
    try {
      if (document.pages.isEmpty) return null;
      final page = document.pages.first;
      if (page.width <= 0 || page.height <= 0) return null;
      const targetWidth = 640.0;
      final targetHeight = targetWidth * page.height / page.width;
      final rendered = await page.render(
        fullWidth: targetWidth,
        fullHeight: targetHeight,
      );
      if (rendered == null) return null;
      try {
        final raster = image.Image.fromBytes(
          width: rendered.width,
          height: rendered.height,
          bytes: rendered.pixels.buffer,
          order: image.ChannelOrder.bgra,
        );
        return Uint8List.fromList(image.encodeJpg(raster, quality: 84));
      } finally {
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }

  Future<Uint8List?> _epubCover(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final files = _archiveFiles(archive);
    final container = files['META-INF/container.xml'];
    if (container == null) return null;
    final containerXml = _parseXml(container.readBytes()!);
    final rootfile = containerXml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null) return null;
    final opf = files[_normalise(opfPath)];
    if (opf == null) return null;
    final document = _parseXml(opf.readBytes()!);

    final manifest = <String, XmlElement>{};
    for (final item in document.descendants.whereType<XmlElement>()) {
      if (item.name.local != 'item') continue;
      final id = item.getAttribute('id');
      if (id != null) manifest[id] = item;
    }

    XmlElement? coverItem;
    for (final item in manifest.values) {
      final properties = item.getAttribute('properties') ?? '';
      if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
        coverItem = item;
        break;
      }
    }
    coverItem ??= _epub2CoverItem(document, manifest);
    coverItem ??= _guideCoverItem(document, manifest);

    final href = coverItem?.getAttribute('href');
    if (href == null || href.isEmpty) return null;
    final mediaType = coverItem?.getAttribute('media-type') ?? '';
    if (!_isRasterImage(mediaType, href)) return null;
    final coverPath = p.posix.normalize(
      p.posix.join(p.posix.dirname(_normalise(opfPath)), href),
    );
    return files[coverPath]?.readBytes();
  }

  XmlElement? _epub2CoverItem(
    XmlDocument document,
    Map<String, XmlElement> manifest,
  ) {
    for (final meta in document.descendants.whereType<XmlElement>()) {
      if (meta.name.local != 'meta') continue;
      if (meta.getAttribute('name') != 'cover') continue;
      final id = meta.getAttribute('content');
      if (id != null) return manifest[id];
    }
    return null;
  }

  XmlElement? _guideCoverItem(
    XmlDocument document,
    Map<String, XmlElement> manifest,
  ) {
    for (final reference in document.descendants.whereType<XmlElement>()) {
      if (reference.name.local != 'reference') continue;
      if (reference.getAttribute('type') != 'cover') continue;
      final href = reference.getAttribute('href');
      if (href == null) continue;
      for (final item in manifest.values) {
        if (item.getAttribute('href') == href) return item;
      }
    }
    return null;
  }

  Future<Uint8List?> _docxFirstImage(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final candidates = <ArchiveFile>[];
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (!name.startsWith('word/media/')) continue;
      if (!_isRasterImage('', name)) continue;
      candidates.add(entry);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.name.compareTo(b.name));
    return candidates.first.readBytes();
  }

  Future<String?> _saveJpeg(
    Uint8List bytes,
    String bookId,
    AppPaths paths,
  ) async {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = _fit(decoded, maxWidth: 640, maxHeight: 960);
    final jpeg = Uint8List.fromList(image.encodeJpg(resized, quality: 84));
    final cover = File(p.join(paths.coversDir.path, '$bookId.jpg'));
    await cover.writeAsBytes(jpeg, flush: true);
    return 'covers/$bookId.jpg';
  }

  image.Image _fit(
    image.Image source, {
    required int maxWidth,
    required int maxHeight,
  }) {
    final scale = math.min(
      1.0,
      math.min(maxWidth / source.width, maxHeight / source.height),
    );
    if (scale >= 1.0) return source;
    return image.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: image.Interpolation.average,
    );
  }

  bool _isRasterImage(String mediaType, String fileName) {
    final type = mediaType.toLowerCase();
    final extension = p.extension(fileName).toLowerCase();
    if (type.startsWith('image/')) {
      return !type.contains('svg');
    }
    return const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(extension);
  }

  Map<String, ArchiveFile> _archiveFiles(Archive archive) {
    final result = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) result[_normalise(file.name)] = file;
    }
    return result;
  }

  XmlDocument _parseXml(List<int> bytes) {
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  }

  String _normalise(String value) =>
      p.posix.normalize(value.replaceAll('\\', '/'));
}
