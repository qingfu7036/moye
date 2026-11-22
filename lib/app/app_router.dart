import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/annotations/presentation/all_annotations_page.dart';
import '../features/annotations/presentation/book_annotations_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/reader/presentation/epub_reader_page.dart';
import '../features/reader/presentation/pdf_reader_page.dart';
import '../features/settings/presentation/settings_page.dart';
import 'app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/reader/:bookId',
        builder: (context, state) =>
            PdfReaderPage(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(
        path: '/reader/epub/:bookId',
        builder: (context, state) =>
            EpubReaderPage(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(
        path: '/book/:bookId/annotations',
        builder: (context, state) =>
            BookAnnotationsPage(bookId: state.pathParameters['bookId']!),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            path: '/annotations',
            builder: (context, state) => const AllAnnotationsPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});
