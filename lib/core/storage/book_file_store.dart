import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import 'app_paths.dart';

class StoredBookFile {
  const StoredBookFile({
    required this.relativePath,
    required this.absolutePath,
    required this.sha256,
    required this.size,
  });

  final String relativePath;
  final String absolutePath;
  final String sha256;
  final int size;
}

class QuarantinedFile {
  const QuarantinedFile({
    required this.originalRelativePath,
    required this.trashRelativePath,
  });

  final String originalRelativePath;
  final String trashRelativePath;
}

class BookFileStore {
  BookFileStore(this.paths);

  final AppPaths paths;

  String extensionFor(BookFormat format) {
    return switch (format) {
      BookFormat.pdf => '.pdf',
      BookFormat.epub => '.epub',
      BookFormat.docx => '.docx',
      BookFormat.doc => '.doc',
      BookFormat.txt => '.txt',
      BookFormat.markdown => '.md',
    };
  }

  Future<StoredBookFile> copyIntoLibrary({
    required Stream<List<int>> source,
    required String id,
    required BookFormat format,
  }) async {
    final extension = extensionFor(format);
    final temp = File(p.join(paths.booksDir.path, '.import-$id.part'));
    final destination =
        File(p.join(paths.booksDir.path, '$id$extension'));
    var size = 0;
    IOSink? sink;
    try {
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      sink = temp.openWrite(mode: FileMode.writeOnly);
      await for (final chunk in source) {
        size += chunk.length;
        sink.add(chunk);
        hasher.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
      final digest = digestSink.value;
      if (digest == null) {
        throw StateError('SHA-256 计算未产生结果');
      }
      await temp.rename(destination.path);
      return StoredBookFile(
        relativePath: 'books/$id$extension',
        absolutePath: destination.path,
        sha256: digest.toString(),
        size: size,
      );
    } catch (error, stack) {
      await _closeQuietly(sink);
      await _deleteQuietly(temp);
      await _deleteQuietly(destination);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> deleteRelative(String relativePath) async {
    final file = paths.resolveRelative(relativePath);
    if (await file.exists()) await file.delete();
  }

  Future<void> _closeQuietly(IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {
      // Keep the original import error; a broken sink must not mask it.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The cleanup pass will handle a locked temp file.
    }
  }

  /// Moves the book file out of `books/` before a database delete. If the
  /// database transaction fails, [restore] puts it back.
  Future<QuarantinedFile> quarantine(String relativePath, String bookId) async {
    final source = paths.resolveRelative(relativePath);
    if (!await source.exists()) {
      return QuarantinedFile(
        originalRelativePath: relativePath,
        trashRelativePath: 'cache/trash/$bookId${p.extension(relativePath)}',
      );
    }
    final trashRelative =
        'cache/trash/$bookId${p.extension(relativePath)}';
    final trash = paths.resolveRelative(trashRelative);
    if (await trash.exists()) await trash.delete();
    await source.rename(trash.path);
    return QuarantinedFile(
      originalRelativePath: relativePath,
      trashRelativePath: trashRelative,
    );
  }

  Future<void> restore(QuarantinedFile quarantined) async {
    final source = paths.resolveRelative(quarantined.trashRelativePath);
    if (!await source.exists()) return;
    final destination =
        paths.resolveRelative(quarantined.originalRelativePath);
    if (await destination.exists()) await destination.delete();
    await source.rename(destination.path);
  }

  Future<void> purge(QuarantinedFile quarantined) async {
    await deleteRelative(quarantined.trashRelativePath);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
