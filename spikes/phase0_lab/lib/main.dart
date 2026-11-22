import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/app_shell.dart';
import 'app/moye_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const MoyePhase0App());
}

class MoyePhase0App extends StatelessWidget {
  const MoyePhase0App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨页 Phase 0',
      debugShowCheckedModeBanner: false,
      theme: moyeTheme(Brightness.light),
      darkTheme: moyeTheme(Brightness.dark),
      themeMode: ThemeMode.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}
