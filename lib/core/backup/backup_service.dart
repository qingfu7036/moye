import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../database/library_database.dart';
import '../database/migrations.dart';
import '../storage/app_paths.dart';

const moyeBackupFormat = 'moye-backup';
const moyeBackupVersion = 1;
const moyeAppVersion = '1.4.0+8';

class BackupException implements Exception {
  const BackupException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'BackupException: $message'
      : 'BackupException: $message ($cause)';
}

class BackupFileEntry {
  const BackupFileEntry({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;

  Map<String, Object> toJson() => {
    'path': path,
    'sha256': sha256,
    'size': size,
  };

  factory BackupFileEntry.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final hash = json['sha256'];
    final size = json['size'];
    if (path is! String || hash is! String || size is! num) {
      throw const BackupException('备份清单中的文件条目格式错误');
    }
    return BackupFileEntry(path: path, sha256: hash, size: size.toInt());
  }
}

class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.bookCount,
    required this.files,
  });

  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final int bookCount;
  final List<BackupFileEntry> files;

  Map<String, Object> toJson() => {
    'format': moyeBackupFormat,
    'version': moyeBackupVersion,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'bookCount': bookCount,
    'files': [for (final file in files) file.toJson()],
  };

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    if (json['format'] != moyeBackupFormat) {
      throw const BackupException('不是墨页备份文件');
    }
    final version = json['version'];
    if (version is! num || version.toInt() != moyeBackupVersion) {
      throw BackupException('不支持的备份格式版本：$version');
    }
    final schema = json['schemaVersion'];
    if (schema is! num || schema.toInt() <= 0) {
      throw const BackupException('备份数据库版本无效');
    }
    final createdAtValue = json['createdAt'];
    final createdAt = createdAtValue is String
        ? DateTime.tryParse(createdAtValue)?.toUtc()
        : null;
    if (createdAt == null) {
      throw const BackupException('备份创建时间无效');
    }
    final filesValue = json['files'];
    if (filesValue is! List) {
      throw const BackupException('备份文件清单缺失');
    }
    final files = <BackupFileEntry>[];
    for (final item in filesValue) {
      if (item is! Map) {
        throw const BackupException('备份文件清单格式错误');
      }
      files.add(BackupFileEntry.fromJson(Map<String, Object?>.from(item)));
    }
    if (files.isEmpty) {
      throw const BackupException('备份文件清单为空');
    }
    return BackupManifest(
      appVersion: json['appVersion'] is String
          ? json['appVersion'] as String
          : 'unknown',
      schemaVersion: schema.toInt(),
      createdAt: createdAt,
      bookCount: (json['bookCount'] as num?)?.toInt() ?? 0,
      files: files,
    );
  }
}

class BackupExportResult {
  const BackupExportResult({
    required this.file,
    required this.fileCount,
    required this.totalBytes,
  });

  final File file;
  final int fileCount;
  final int totalBytes;
}

class BackupRestorePreview {
  const BackupRestorePreview({
    required this.source,
    required this.manifest,
    required this.stagingDirectory,
  });

  final File source;
  final BackupManifest manifest;
  final Directory stagingDirectory;
}

class BackupApplyResult {
  const BackupApplyResult({
    required this.safetyDirectory,
    required this.bookCount,
  });

  final Directory safetyDirectory;
  final int bookCount;
}

class BackupService {
  BackupService({required this.paths, required this.database});

  final AppPaths paths;
  final LibraryDatabase database;

  static const _fileRoots = ['books', 'covers', 'attachments'];

  Future<BackupExportResult> exportTo(File destination) async {
    if (await destination.exists()) {
      throw BackupException('目标文件已存在：${destination.path}');
    }
    await destination.parent.create(recursive: true);

    final work = await Directory(
      p.join(paths.cacheDir.path, 'backup-work-${_stamp()}'),
    ).create(recursive: true);
    final part = File('${destination.path}.part');
    try {
      final databaseSnapshot = File(
        p.join(work.path, 'database', 'library.db'),
      );
      await databaseSnapshot.parent.create(recursive: true);
      await _snapshotDatabase(databaseSnapshot);

      final files = <File>[];
      files.add(databaseSnapshot);
      for (final name in _fileRoots) {
        final directory = Directory(p.join(paths.root.path, name));
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && !_isTransientFile(entity)) {
            files.add(entity);
          }
        }
      }
      String archivePathFor(File file) => identical(file, databaseSnapshot)
          ? 'database/library.db'
          : paths.relativeFor(file);
      files.sort((a, b) => archivePathFor(a).compareTo(archivePathFor(b)));

      final entries = <BackupFileEntry>[];
      var totalBytes = 0;
      for (final file in files) {
        final relativePath = _safePath(archivePathFor(file));
        _checkAllowedBackupPath(relativePath);
        final hash = await _sha256(file);
        final size = await file.length();
        entries.add(
          BackupFileEntry(path: relativePath, sha256: hash, size: size),
        );
        totalBytes += size;
      }
      final manifest = BackupManifest(
        appVersion: moyeAppVersion,
        schemaVersion: database.schemaVersion,
        createdAt: DateTime.now().toUtc(),
        bookCount: _countBooks(),
        files: entries,
      );
      final manifestFile = File(p.join(work.path, 'manifest.json'));
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );

      final encoder = ZipFileEncoder();
      encoder.create(part.path, level: ZipFileEncoder.gzip);
      try {
        for (final entry in entries) {
          final file = entry.path == 'database/library.db'
              ? databaseSnapshot
              : paths.resolveRelative(entry.path);
          await encoder.addFile(file, entry.path);
        }
        await encoder.addFile(manifestFile, 'manifest.json');
      } finally {
        await encoder.close();
      }
      if (!await part.exists() || await part.length() == 0) {
        throw const BackupException('备份文件写入失败');
      }
      await part.rename(destination.path);
      return BackupExportResult(
        file: destination,
        fileCount: entries.length,
        totalBytes: totalBytes,
      );
    } catch (error, stack) {
      await _deleteQuietly(part);
      Error.throwWithStackTrace(error, stack);
    } finally {
      await _deleteDirectoryQuietly(work);
    }
  }

  /// Validates and extracts a backup into a staging directory. The active
  /// library is not touched until the next application start.
  Future<BackupRestorePreview> prepareRestore(File source) async {
    if (!await source.exists()) {
      throw BackupException('备份文件不存在：${source.path}');
    }
    final staging = Directory(p.join(paths.backupsDir.path, 'restore-pending'));
    await _deleteDirectoryQuietly(staging);
    await staging.create(recursive: true);

    InputFileStream? input;
    try {
      input = InputFileStream(source.path);
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final entriesByName = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        if (entry.isDirectory) continue;
        if (entry.isSymbolicLink) {
          throw BackupException('备份包含不安全的符号链接：${entry.name}');
        }
        final name = _safePath(entry.name);
        if (entriesByName.containsKey(name)) {
          throw BackupException('备份包含重复文件：$name');
        }
        entriesByName[name] = entry;
      }
      final manifestEntry = entriesByName['manifest.json'];
      if (manifestEntry == null) {
        throw const BackupException('备份缺少 manifest.json');
      }
      final manifestBytes = manifestEntry.readBytes();
      if (manifestBytes == null) {
        throw const BackupException('无法读取备份清单');
      }
      final decoded = jsonDecode(utf8.decode(manifestBytes));
      if (decoded is! Map) {
        throw const BackupException('备份清单格式错误');
      }
      final manifest = BackupManifest.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (manifest.schemaVersion > librarySchemaVersion) {
        throw BackupException(
          '备份数据库版本 ${manifest.schemaVersion} 高于当前应用版本 '
          '$librarySchemaVersion，请先升级墨页。',
        );
      }

      final seen = <String>{};
      for (final file in manifest.files) {
        final name = _safePath(file.path);
        _checkAllowedBackupPath(name);
        if (!seen.add(name)) {
          throw BackupException('备份文件清单包含重复路径：$name');
        }
        final archiveFile = entriesByName[name];
        if (archiveFile == null) {
          throw BackupException('备份缺少文件：$name');
        }
        final target = File(p.joinAll([staging.path, ...name.split('/')]));
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        try {
          archiveFile.writeContent(output);
          await output.close();
        } finally {
          archiveFile.closeSync();
        }
        final size = await target.length();
        if (size != file.size) {
          throw BackupException('备份文件大小校验失败：$name');
        }
        if (await _sha256(target) != file.sha256.toLowerCase()) {
          throw BackupException('备份文件哈希校验失败：$name');
        }
      }

      final databaseFile = File(p.join(staging.path, 'database', 'library.db'));
      if (!await databaseFile.exists()) {
        throw const BackupException('备份缺少 database/library.db');
      }
      await _validateStagedDatabase(
        databaseFile: databaseFile,
        staging: staging,
        manifest: manifest,
      );
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        flush: true,
      );
      return BackupRestorePreview(
        source: source,
        manifest: manifest,
        stagingDirectory: staging,
      );
    } catch (error, stack) {
      await _deleteDirectoryQuietly(staging);
      if (error is BackupException) {
        Error.throwWithStackTrace(error, stack);
      }
      Error.throwWithStackTrace(BackupException('备份文件无法读取或已损坏', error), stack);
    } finally {
      await input?.close();
    }
  }

  /// Rolls back a restore that was interrupted during the directory swap.
  /// The marker is written before any active directory is moved, so a crash
  /// can never leave the app without a recoverable copy.
  static Future<BackupApplyResult?> recoverInterruptedRestore(
    AppPaths paths,
  ) async {
    final marker = File(
      p.join(paths.backupsDir.path, 'restore-in-progress.json'),
    );
    if (!await marker.exists()) return null;
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map || decoded['safety'] is! String) {
      throw const BackupException('恢复中断标记格式错误');
    }
    final safetyName = decoded['safety'] as String;
    if (decoded['completed'] == true) {
      await _deleteDirectoryQuietly(
        Directory(p.join(paths.backupsDir.path, 'restore-pending')),
      );
      await marker.delete();
      return null;
    }
    if (p.basename(safetyName) != safetyName ||
        safetyName.contains('..') ||
        safetyName.contains('/') ||
        safetyName.contains(String.fromCharCode(92))) {
      throw const BackupException('恢复中断标记包含不安全路径');
    }
    final safety = Directory(p.join(paths.backupsDir.path, safetyName));
    if (!await safety.exists()) {
      throw const BackupException('恢复中断，但找不到还原保护目录');
    }
    var restored = 0;
    for (final name in [
      'trash',
      'database',
      'books',
      'covers',
      'attachments',
    ]) {
      final old = Directory(p.join(safety.path, name));
      if (!await old.exists()) continue;
      final target = name == 'trash'
          ? paths.trashDir
          : Directory(p.join(paths.root.path, name));
      await _deleteDirectoryQuietly(target);
      await target.parent.create(recursive: true);
      await old.rename(target.path);
      restored++;
    }
    await _deleteDirectoryQuietly(
      Directory(p.join(paths.backupsDir.path, 'restore-pending')),
    );
    await marker.delete();
    return BackupApplyResult(safetyDirectory: safety, bookCount: restored);
  }

  /// Applies a prepared restore before the database is opened. A copy of the
  /// current data is kept under `backups/pre-restore-<timestamp>` for rollback.
  static Future<BackupApplyResult?> applyPendingRestore(AppPaths paths) async {
    final staging = Directory(p.join(paths.backupsDir.path, 'restore-pending'));
    final manifestFile = File(p.join(staging.path, 'manifest.json'));
    final stagedDatabase = File(p.join(staging.path, 'database', 'library.db'));
    if (!await manifestFile.exists() || !await stagedDatabase.exists()) {
      return null;
    }

    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map) {
      throw const BackupException('待恢复清单格式错误');
    }
    final manifest = BackupManifest.fromJson(
      Map<String, Object?>.from(decoded),
    );
    if (manifest.schemaVersion > librarySchemaVersion) {
      throw BackupException(
        '待恢复数据库版本 ${manifest.schemaVersion} 高于当前应用版本 '
        '$librarySchemaVersion。',
      );
    }

    await _validateStagedPackage(staging, manifest);

    final stamp = _stamp();
    final safety = Directory(
      p.join(paths.backupsDir.path, 'pre-restore-$stamp'),
    );
    await safety.create(recursive: true);
    final marker = File(
      p.join(paths.backupsDir.path, 'restore-in-progress.json'),
    );
    await marker.writeAsString(
      jsonEncode({'safety': p.basename(safety.path)}),
      flush: true,
    );
    final movedOld = <String>[];
    final createdNew = <String>[];
    try {
      final oldTrash = paths.trashDir;
      if (await oldTrash.exists()) {
        await oldTrash.rename(p.join(safety.path, 'trash'));
        movedOld.add('trash');
      }
      for (final name in ['database', 'books', 'covers', 'attachments']) {
        final current = Directory(p.join(paths.root.path, name));
        if (await current.exists()) {
          await current.rename(p.join(safety.path, name));
          movedOld.add(name);
        }
        final staged = Directory(p.join(staging.path, name));
        final target = Directory(p.join(paths.root.path, name));
        if (await staged.exists()) {
          await staged.rename(target.path);
        } else {
          await target.create(recursive: true);
        }
        createdNew.add(name);
      }
      await paths.trashDir.create(recursive: true);
      await _deleteDirectoryQuietly(staging);
      await marker.writeAsString(
        jsonEncode({'safety': p.basename(safety.path), 'completed': true}),
        flush: true,
      );
      await marker.delete();
      return BackupApplyResult(
        safetyDirectory: safety,
        bookCount: manifest.bookCount,
      );
    } catch (error, stack) {
      // Restore the old directories if the swap fails halfway through.
      for (final name in createdNew.reversed) {
        await _deleteDirectoryQuietly(Directory(p.join(paths.root.path, name)));
      }
      for (final name in movedOld.reversed) {
        final source = Directory(p.join(safety.path, name));
        final target = name == 'trash'
            ? paths.trashDir
            : Directory(p.join(paths.root.path, name));
        if (await source.exists()) {
          await _deleteDirectoryQuietly(target);
          await source.rename(target.path);
        }
      }
      await marker.delete();
      Error.throwWithStackTrace(error, stack);
    }
  }

  static bool hasPendingRestore(AppPaths paths) {
    return File(
      p.join(paths.backupsDir.path, 'restore-pending', 'manifest.json'),
    ).existsSync();
  }

  Future<void> _snapshotDatabase(File destination) async {
    final target = sqlite3.open(destination.path);
    try {
      await database.raw.backup(target).drain<void>();
    } finally {
      target.close();
    }
  }

  int _countBooks() {
    final rows = database.raw.select('SELECT COUNT(*) AS count FROM books');
    return (rows.first['count'] as int?) ?? 0;
  }

  static Future<void> _validateStagedPackage(
    Directory staging,
    BackupManifest manifest,
  ) async {
    final seen = <String>{};
    for (final file in manifest.files) {
      final name = _safePath(file.path);
      _checkAllowedBackupPath(name);
      if (!seen.add(name)) {
        throw BackupException('备份文件清单包含重复路径：$name');
      }
      final target = File(p.joinAll([staging.path, ...name.split('/')]));
      if (!await target.exists()) {
        throw BackupException('备份缺少文件：$name');
      }
      final size = await target.length();
      if (size != file.size) {
        throw BackupException('备份文件大小校验失败：$name');
      }
      if (await _sha256(target) != file.sha256.toLowerCase()) {
        throw BackupException('备份文件哈希校验失败：$name');
      }
    }
    final databaseFile = File(p.join(staging.path, 'database', 'library.db'));
    if (!await databaseFile.exists()) {
      throw const BackupException('备份缺少 database/library.db');
    }
    await _validateStagedDatabase(
      databaseFile: databaseFile,
      staging: staging,
      manifest: manifest,
    );
  }

  static Future<void> _validateStagedDatabase({
    required File databaseFile,
    required Directory staging,
    required BackupManifest manifest,
  }) async {
    final db = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    try {
      final version =
          db.select('PRAGMA user_version').first.columnAt(0) as int? ?? 0;
      if (version != manifest.schemaVersion) {
        throw BackupException(
          '备份清单版本 $version 与数据库版本 ${manifest.schemaVersion} 不一致',
        );
      }
      final integrity = db.select('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.columnAt(0)?.toString().toLowerCase() != 'ok') {
        throw const BackupException('备份数据库完整性检查失败');
      }
      if (db.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw const BackupException('备份数据库外键检查失败');
      }

      final requiredPaths = <String>[
        for (final row in db.select('SELECT relative_path FROM books'))
          row['relative_path'] as String,
        for (final row in db.select(
          'SELECT cover_path FROM books WHERE cover_path IS NOT NULL',
        ))
          row['cover_path'] as String,
        for (final row in db.select(
          'SELECT image_path FROM annotations WHERE image_path IS NOT NULL',
        ))
          row['image_path'] as String,
      ];
      for (final relativePath in requiredPaths) {
        if (relativePath.trim().isEmpty) continue;
        final safe = _safePath(relativePath);
        _checkAllowedBackupPath(safe);
        final target = File(p.joinAll([staging.path, ...safe.split('/')]));
        if (!await target.exists()) {
          throw BackupException('备份缺少数据库引用的文件：$safe');
        }
      }
    } finally {
      db.close();
    }
  }

  static String _safePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        p.posix.isAbsolute(normalized) ||
        normalized.split('/').contains('..') ||
        normalized.contains('\u0000')) {
      throw BackupException('备份包含不安全路径：$value');
    }
    return p.posix.normalize(normalized);
  }

  static void _checkAllowedBackupPath(String path) {
    if (path == 'manifest.json' || path == 'database/library.db') return;
    if (_fileRoots.any((root) => path.startsWith('$root/'))) return;
    throw BackupException('备份包含不允许的路径：$path');
  }

  static bool _isTransientFile(File file) {
    final name = p.basename(file.path);
    return name.startsWith('.') || name.endsWith('.part');
  }

  static Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _deleteDirectoryQuietly(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  static String _stamp() {
    final now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
