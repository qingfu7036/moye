import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'migrations.dart';

class DatabaseException implements Exception {
  const DatabaseException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? 'DatabaseException: $message' : 'DatabaseException: $message ($cause)';
}

class LibraryDatabase {
  LibraryDatabase._(this.raw);

  final Database raw;

  int get schemaVersion {
    final result = raw.select('PRAGMA user_version');
    return result.first.columnAt(0) as int? ?? 0;
  }

  static LibraryDatabase open(File file) {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(file.path);
    return _prepare(db);
  }

  static LibraryDatabase inMemory() {
    return _prepare(sqlite3.openInMemory());
  }

  static LibraryDatabase _prepare(Database db) {
    try {
      db.execute('PRAGMA foreign_keys = ON');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
      final database = LibraryDatabase._(db);
      database._migrate();
      return database;
    } catch (error) {
      db.close();
      throw DatabaseException('数据库初始化失败', error);
    }
  }

  void _migrate() {
    final current = schemaVersion;
    if (current > librarySchemaVersion) {
      throw DatabaseException(
        '数据库版本 $current 高于应用支持版本 $librarySchemaVersion，已停止打开以防止损坏。',
      );
    }
    if (current == librarySchemaVersion) return;

    raw.execute('BEGIN IMMEDIATE');
    try {
      for (var version = current + 1;
          version <= librarySchemaVersion;
          version++) {
        final statements = libraryMigrations[version];
        if (statements == null) {
          throw DatabaseException('缺少数据库迁移 $version');
        }
        for (final statement in statements) {
          raw.execute(statement);
        }
      }
      raw.execute('PRAGMA user_version = $librarySchemaVersion');
      raw.execute('COMMIT');
    } catch (error) {
      raw.execute('ROLLBACK');
      throw DatabaseException('数据库迁移失败', error);
    }
  }

  T transaction<T>(T Function() action) {
    raw.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => raw.close();
}
