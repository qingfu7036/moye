import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the application-private directory layout.
///
/// The database stores paths relative to [root], never absolute paths. This is
/// what makes a library portable across Windows and Android.
class AppPaths {
  AppPaths._(this.root);

  final Directory root;

  Directory get databaseDir => Directory(p.join(root.path, 'database'));
  Directory get booksDir => Directory(p.join(root.path, 'books'));
  Directory get coversDir => Directory(p.join(root.path, 'covers'));
  Directory get attachmentsDir => Directory(p.join(root.path, 'attachments'));
  Directory get cacheDir => Directory(p.join(root.path, 'cache'));
  Directory get trashDir => Directory(p.join(cacheDir.path, 'trash'));
  Directory get backupsDir => Directory(p.join(root.path, 'backups'));
  Directory get logsDir => Directory(p.join(root.path, 'logs'));

  File get databaseFile => File(p.join(databaseDir.path, 'library.db'));

  static Future<AppPaths> create() async {
    final support = await getApplicationSupportDirectory();
    // path_provider already returns an app-specific directory. On Windows its
    // basename may already be `moye`; avoid creating a redundant moye/moye.
    final alreadyNamedMoye =
        p.basename(support.path).toLowerCase() == 'moye';
    final root = alreadyNamedMoye
        ? support
        : Directory(p.join(support.path, 'moye'));
    final paths = AppPaths._(root);
    await paths.ensureLayout();
    return paths;
  }

  /// Test/CI entry point. The caller owns [root] and must keep it private.
  static Future<AppPaths> forRoot(Directory root) async {
    final paths = AppPaths._(root);
    await paths.ensureLayout();
    return paths;
  }

  Future<void> ensureLayout() async {
    for (final directory in [
      root,
      databaseDir,
      booksDir,
      coversDir,
      attachmentsDir,
      cacheDir,
      trashDir,
      backupsDir,
      logsDir,
    ]) {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }
  }

  /// Converts a database-relative POSIX path to a safe absolute file.
  ///
  /// Rejects absolute paths, `..` traversal and paths that canonicalize outside
  /// the application root.
  File resolveRelative(String relativePath) {
    if (relativePath.trim().isEmpty) {
      throw ArgumentError.value(relativePath, 'relativePath', 'empty path');
    }
    final normalized = relativePath.replaceAll('\\', '/');
    if (p.posix.isAbsolute(normalized) || normalized.split('/').contains('..')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'unsafe path');
    }
    final candidate = File(p.joinAll([root.path, ...normalized.split('/')]));
    final rootPath = p.canonicalize(root.path);
    final candidatePath = p.canonicalize(candidate.path);
    if (candidatePath != rootPath && !p.isWithin(rootPath, candidatePath)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'outside root');
    }
    return candidate;
  }

  String relativeFor(File file) {
    final relative = p.relative(file.path, from: root.path);
    return relative.replaceAll('\\', '/');
  }
}
