import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_services.dart';
import '../core/models/book.dart';
import '../features/library/data/library_repository.dart';

final appServicesProvider = Provider<AppServices>(
  (ref) =>
      throw StateError('appServicesProvider must be overridden at startup'),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => ref.watch(appServicesProvider).library,
);

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
      LibraryFilterNotifier.new,
    );

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => const LibraryFilter();

  void setQuery(String query) {
    if (state.query == query) return;
    state = state.copyWith(query: query);
  }

  void setStatus(BookStatus? status) {
    if (state.status == status) return;
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
  }

  void setSort(BookSort sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }
}

final libraryBooksProvider = FutureProvider<List<Book>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return ref.watch(libraryRepositoryProvider).listBooks(filter);
});

final storageStatsProvider = FutureProvider<StorageStats>((ref) {
  return ref.watch(libraryRepositoryProvider).storageStats();
});

/// Generates covers for books that were imported before cover extraction was
/// added. It runs after the library is visible and refreshes the list once.
final coverBackfillProvider = FutureProvider<void>((ref) async {
  final created = await ref
      .read(libraryRepositoryProvider)
      .backfillMissingCovers();
  if (created > 0) {
    ref.invalidate(libraryBooksProvider);
  }
});
