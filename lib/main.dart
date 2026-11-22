import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/moye_app.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'core/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Covers and inline EPUB images go through Flutter's global image cache.
  // Keep the desktop footprint predictable instead of using the 100 MB default.
  PaintingBinding.instance.imageCache
    ..maximumSize = 80
    ..maximumSizeBytes = 48 * 1024 * 1024;
  try {
    // PDFium is initialized lazily by cover extraction or the PDF reader.
    // Keeping it out of the library-only startup path avoids paying its
    // native-memory cost until a PDF is actually needed.
    final services = await AppServices.bootstrap();
    runApp(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: const MoyeApp(),
      ),
    );
  } catch (error, stack) {
    runApp(MoyeBootFailure(error: error, stack: stack));
  }
}

class MoyeBootFailure extends StatelessWidget {
  const MoyeBootFailure({super.key, required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: moyeTheme(Brightness.light),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      '墨页启动失败',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('数据库或应用目录无法打开。为避免损坏数据，应用已停止启动。'),
                    const SizedBox(height: 18),
                    SelectableText(
                      '$error\n\n$stack',
                      style: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
