import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/tts/tts_service.dart';

Future<void> showTtsSheet(BuildContext context, TtsService service) async {
  await service.initialize();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _TtsSheet(service: service),
  );
}

class _TtsSheet extends StatelessWidget {
  const _TtsSheet({required this.service});

  final TtsService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final sentence = service.currentSentence;
              final index = service.currentIndex;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('朗读', style: theme.textTheme.titleLarge),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭朗读',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '系统语音 · 逐句朗读',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (service.error != null)
                    Text(
                      'TTS 错误：${service.error}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (service.voices.isNotEmpty)
                    DropdownButtonFormField<TtsVoice>(
                      key: const Key('tts-voice-select'),
                      initialValue: service.selectedVoice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '声音',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        for (final voice in service.voices)
                          DropdownMenuItem(
                            value: voice,
                            child: Text(
                              voice.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (voice) {
                        if (voice != null) {
                          unawaited(service.selectVoice(voice));
                        }
                      },
                    )
                  else
                    Text('使用系统默认声音', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('语速', style: theme.textTheme.labelSmall),
                      const Spacer(),
                      Text(
                        '${(service.rate * 2).toStringAsFixed(1)}×',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('tts-rate-slider'),
                    value: service.rate,
                    min: 0.25,
                    max: 0.75,
                    divisions: 10,
                    label: '${(service.rate * 2).toStringAsFixed(1)}×',
                    onChanged: service.setRate,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 82),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      sentence?.text ?? '没有可朗读的文本',
                      key: const Key('tts-current-sentence'),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sentence == null
                        ? '未开始'
                        : '第 ${index + 1} / ${service.sentenceCount} 句'
                              ' · ${_stateLabel(service.state)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一句',
                        onPressed: service.sentenceCount == 0
                            ? null
                            : () => unawaited(
                                service.jumpTo((index <= 0 ? 0 : index - 1)),
                              ),
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      IconButton.filled(
                        tooltip: service.state == TtsPlaybackState.playing
                            ? '暂停朗读'
                            : '开始朗读',
                        onPressed: service.sentenceCount == 0
                            ? null
                            : () {
                                if (service.state == TtsPlaybackState.playing) {
                                  unawaited(service.pause());
                                } else {
                                  unawaited(service.play());
                                }
                              },
                        icon: Icon(
                          service.state == TtsPlaybackState.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '停止朗读',
                        onPressed: service.state == TtsPlaybackState.idle
                            ? null
                            : () => unawaited(service.stop()),
                        icon: const Icon(Icons.stop_rounded),
                      ),
                      IconButton(
                        tooltip: '下一句',
                        onPressed: service.sentenceCount == 0
                            ? null
                            : () => unawaited(
                                service.jumpTo(
                                  (index < 0 ? 0 : index + 1).clamp(
                                    0,
                                    service.sentenceCount - 1,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _stateLabel(TtsPlaybackState state) => switch (state) {
    TtsPlaybackState.idle => '未播放',
    TtsPlaybackState.playing => '朗读中',
    TtsPlaybackState.paused => '已暂停',
  };
}
