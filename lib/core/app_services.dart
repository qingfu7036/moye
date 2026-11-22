import 'backup/backup_service.dart';
import 'database/library_database.dart';
import 'storage/app_paths.dart';
import 'storage/book_file_store.dart';
import '../features/library/data/library_repository.dart';

class AppServices {
  AppServices({
    required this.paths,
    required this.database,
    required this.library,
  });

  final AppPaths paths;
  final LibraryDatabase database;
  final LibraryRepository library;

  static Future<AppServices> bootstrap() async {
    final paths = await AppPaths.create();
    // A backup restore is staged while the app is running and applied here,
    // before SQLite opens the database. This keeps the active library safe.
    try {
      await BackupService.recoverInterruptedRestore(paths);
      await BackupService.applyPendingRestore(paths);
    } catch (_) {
      // Keep the existing library; the pending package stays for a retry.
    }
    final database = LibraryDatabase.open(paths.databaseFile);
    final files = BookFileStore(paths);
    final library = LibraryRepository(
      database: database,
      paths: paths,
      files: files,
    );
    // Recover a crash between file quarantine and the database delete before
    // the first library query runs.
    try {
      await library.reconcileQuarantine();
    } catch (_) {
      // Never block startup on a best-effort recovery pass.
    }
    return AppServices(paths: paths, database: database, library: library);
  }

  void dispose() {
    database.close();
  }
}
