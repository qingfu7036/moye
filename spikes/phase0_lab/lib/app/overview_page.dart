import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'moye_theme.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.onOpenLab});

  final ValueChanged<int> onOpenLab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hero(dark: dark),
              const SizedBox(height: 26),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final cards = [
                    _LabCard(
                      index: 1,
                      eyebrow: 'READING / PDF',
                      title: 'PDF 文字层与坐标',
                      body: 'PDFium 渲染、文字选择、字符矩形、文本型/扫描型识别。',
                      icon: Icons.picture_as_pdf_outlined,
                      accent: MoyeColors.rose,
                      onTap: () => onOpenLab(1),
                    ),
                    _LabCard(
                      index: 2,
                      eyebrow: 'READING / EPUB',
                      title: 'EPUB3 重排与 CFI',
                      body: '章节解析、CFI 锚点、文字选择、字号重排与位置恢复。',
                      icon: Icons.auto_stories_outlined,
                      accent: MoyeColors.pine,
                      onTap: () => onOpenLab(2),
                    ),
                    _LabCard(
                      index: 3,
                      eyebrow: 'READING / DOCX',
                      title: 'DOCX 结构定位',
                      body: '标题、段落、列表、表格、图片、超链接与段落路径。',
                      icon: Icons.description_outlined,
                      accent: MoyeColors.sky,
                      onTap: () => onOpenLab(3),
                    ),
                    _LabCard(
                      index: 4,
                      eyebrow: 'SPEECH / LOCAL TTS',
                      title: '系统语音与句级同步',
                      body: '真实系统声音枚举、语速、暂停恢复和逐句回调高亮。',
                      icon: Icons.graphic_eq_rounded,
                      accent: MoyeColors.amber,
                      onTap: () => onOpenLab(4),
                    ),
                  ];
                  if (!wide) {
                    return Column(
                      children: [
                        for (final card in cards) ...[
                          card,
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.05,
                    children: cards,
                  );
                },
              ),
              const SizedBox(height: 26),
              _EnvironmentCard(dark: dark),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B2A23) : const Color(0xFF1E332A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -56,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFB6CCBD).withValues(alpha: 0.18),
                  width: 34,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6C77F),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '墨',
                      style: TextStyle(
                        color: Color(0xFF1E332A),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'MOYE / PHASE 0',
                    style: TextStyle(
                      color: Color(0xFFB6CCBD),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                '把阅读，变成\n可以带走的记忆。',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: const Color(0xFFF4F6F2),
                  height: 1.18,
                  fontSize: 38,
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 620,
                child: Text(
                  '这是技术风险验证实验室，不是 V1 产品界面。PDF、EPUB、DOCX 与本地 TTS 都在真实文件上跑通后，才进入 Phase 1。',
                  style: TextStyle(
                    color: Color(0xFFB6CCBD),
                    height: 1.7,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HeroTag(label: 'Flutter 3.47.9'),
                  _HeroTag(label: '本地优先'),
                  _HeroTag(label: 'Windows / Android'),
                  _HeroTag(label: '真实样书'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD8E4DC),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({
    required this.index,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final int index;
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.32),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                eyebrow,
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('运行平台', Platform.operatingSystem),
      ('系统版本', Platform.operatingSystemVersion),
      ('构建模式', kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')),
      ('Dart 运行时', Platform.version.split(' ').first),
      ('应用目录', Platform.resolvedExecutable),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('运行环境', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  'PHASE 0 / DIAGNOSTICS',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final row in rows) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      row.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
