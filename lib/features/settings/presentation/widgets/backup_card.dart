import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../app/providers.dart';
import '../../../../core/backup/backup_service.dart';

class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key});

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  bool _busy = false;
  String? _message;

  Future<void> _export() async {
    final services = ref.read(appServicesProvider);
    final directoryPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 .moye 备份保存位置',
    );
    if (directoryPath == null || !mounted) return;
    final destination = File(
      p.join(directoryPath, 'MOYE-backup-${_backupStamp()}.moye'),
    );
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await BackupService(
        paths: services.paths,
        database: services.database,
      ).exportTo(destination);
      if (!mounted) return;
      setState(() {
        _message =
            '已导出 ${result.fileCount} 个文件，'
            '${formatBytes(result.totalBytes)}：${result.file.path}';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择 .moye 备份',
      type: FileType.any,
    );
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复整个书库？'),
        content: const Text(
          '恢复会替换当前数据库、书籍、封面和标记附件。\n\n'
          '程序会先完整校验备份文件，校验通过后需要重启墨页才会替换；'
          '当前数据会保留在 backups/pre-restore-* 目录中。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('校验并准备恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    File? temporarySource;
    try {
      final services = ref.read(appServicesProvider);
      final source = await _materializePickedFile(
        picked,
        services.paths.cacheDir,
      );
      if (picked.path == null) temporarySource = source;
      final preview = await BackupService(
        paths: services.paths,
        database: services.database,
      ).prepareRestore(source);
      if (!mounted) return;
      setState(() {
        _message =
            '备份已校验：${preview.manifest.bookCount} 本，'
            '数据库 v${preview.manifest.schemaVersion}。'
            '请关闭并重新启动墨页完成恢复；当前书库尚未被替换。';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '恢复准备失败：$error');
    } finally {
      if (temporarySource != null) {
        try {
          await temporarySource.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _materializePickedFile(
    PlatformFile picked,
    Directory cacheDir,
  ) async {
    final path = picked.path;
    if (path != null) return File(path);
    final target = File(
      p.join(
        cacheDir.path,
        'restore-source-${DateTime.now().microsecondsSinceEpoch}.moye',
      ),
    );
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    try {
      await for (final chunk in picked.readAsByteStream()) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return target;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = BackupService.hasPendingRestore(
      ref.read(appServicesProvider).paths,
    );
    return Card(
      key: const Key('settings-backup-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('备份与恢复', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '导出一个可跨 Windows / Android 迁移的 .moye 文件，'
              '包含数据库、书籍、封面、标记截图和设置。',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.65,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 10),
              Text(
                '检测到一个已校验的待恢复包。关闭并重新启动墨页后完成恢复。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('export-backup-button'),
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('导出 .moye 备份'),
                ),
                OutlinedButton.icon(
                  key: const Key('restore-backup-button'),
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('从 .moye 恢复'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                _message!,
                key: const Key('backup-message'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _backupStamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
