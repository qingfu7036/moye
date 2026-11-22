import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/models/book.dart';
import 'widgets/backup_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(storageStatsProvider);
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('设置', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  '本地书库、PDF/EPUB 阅读和区域标记已可用；这里可以导出或恢复完整书库。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 20),
                statsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text('读取存储信息失败：$error'),
                    ),
                  ),
                  data: (stats) => _StorageCard(stats: stats),
                ),
                const SizedBox(height: 14),
                const BackupCard(),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text('本地优先', style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '书籍、数据库和后续的标注/笔记都保存在应用私有目录。V1 不包含自动云同步；跨设备迁移将在 Phase 5 通过 .moye 备份包完成。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.65,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MoyeColors.amber.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 17,
                                color: Color(0xFF88631F),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '建议定期导出 .moye 备份。恢复包会先完整校验，重启后才会替换当前书库。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6F551F),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'MOYE 墨页 · $moyeAppVersion · Flutter 3.47.9',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('settings-storage-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('应用数据', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    onPressed: () => _openDataFolder(stats.dataRoot),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('打开目录'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(label: '书籍', value: '${stats.bookCount} 本'),
                ),
                Expanded(
                  child: _Metric(
                    label: '书籍占用',
                    value: _formatBytes(stats.totalBookBytes),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: '数据库版本',
                    value: 'v${stats.databaseVersion}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('数据目录', style: theme.textTheme.labelLarge),
            const SizedBox(height: 5),
            SelectableText(
              stats.dataRoot,
              key: const Key('settings-data-root'),
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '目录结构：database / books / covers / attachments / cache / backups / logs',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDataFolder(String path) async {
    if (!Platform.isWindows) return;
    await Process.start('explorer.exe', [
      path,
    ], mode: ProcessStartMode.detached);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 3),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
