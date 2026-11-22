import 'package:flutter/material.dart';

import '../labs/docx_lab.dart';
import '../labs/epub_lab.dart';
import '../labs/pdf_lab.dart';
import '../labs/tts_lab.dart';
import 'overview_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    _Destination(Icons.grid_view_rounded, '概览'),
    _Destination(Icons.picture_as_pdf_outlined, 'PDF'),
    _Destination(Icons.auto_stories_outlined, 'EPUB'),
    _Destination(Icons.description_outlined, 'DOCX'),
    _Destination(Icons.graphic_eq_rounded, '语音'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewPage(onOpenLab: (index) => setState(() => _index = index)),
      const PdfLab(),
      const EpubLab(),
      const DocxLab(),
      const TtsLab(),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 18,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '墨',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('墨页', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'PHASE 0',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (MediaQuery.sizeOf(context).width > 900)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(
                child: Text(
                  '阅读引擎 · 本地 TTS · 定位锚点技术验证',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          if (desktop) {
            return Row(
              children: [
                NavigationRail(
                  extended: constraints.maxWidth >= 1160,
                  minExtendedWidth: 178,
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: constraints.maxWidth >= 1160
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  groupAlignment: -0.82,
                  leading: const SizedBox(height: 8),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(
                          destination.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: Text(
                          destination.label,
                          key: Key('nav-${destination.label}'),
                        ),
                      ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(
                  child: ClipRect(
                    child: IndexedStack(index: _index, children: pages),
                  ),
                ),
              ],
            );
          }
          return IndexedStack(index: _index, children: pages);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 820
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(
                      destination.icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: destination.label,
                    key: Key('nav-${destination.label}'),
                  ),
              ],
            ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}

class _Destination {
  const _Destination(this.icon, this.label);

  final IconData icon;
  final String label;
}
