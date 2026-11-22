import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/moye_theme.dart';
import '../engines/tts/tts_service.dart';

class TtsLab extends StatefulWidget {
  const TtsLab({super.key});

  @override
  State<TtsLab> createState() => _TtsLabState();
}

class _TtsLabState extends State<TtsLab> {
  final TtsService _service = TtsService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final data = await rootBundle.loadString('assets/fixtures/tts_sample.txt');
    await _service.initialize();
    await _service.loadText(data);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final content = Column(
              children: [
                _Header(service: _service),
                if (_service.error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MoyeColors.rose.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '系统 TTS 初始化失败：${_service.error}',
                      style: const TextStyle(color: MoyeColors.rose),
                    ),
                  ),
                Expanded(child: _SentenceList(service: _service)),
                _PlaybackBar(service: _service),
              ],
            );
            if (!wide) {
              return Column(
                children: [
                  Expanded(child: content),
                  _LogPanel(service: _service, height: 150),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: content),
                SizedBox(
                  width: 330,
                  child: _LogPanel(service: _service),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.service});

  final TtsService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MoyeColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'LOCAL TTS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: const Color(0xFF88631F),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '系统语音 · 句子级同步',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '${service.voices.length} 个可用声音',
                key: const Key('tts-voice-count'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '依次提交句子，利用引擎完成回调推进；不伪造单词级时间戳。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TtsVoice>(
                  key: const Key('tts-voice-select'),
                  initialValue: service.selectedVoice,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '系统声音',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    if (voice != null) service.selectVoice(voice);
                  },
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      value: service.rate,
                      min: 0.25,
                      max: 0.75,
                      divisions: 10,
                      label: '${(service.rate * 2).toStringAsFixed(1)}×',
                      onChanged: service.setRate,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SentenceList extends StatelessWidget {
  const _SentenceList({required this.service});

  final TtsService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (service.sentences.isEmpty) {
      return Center(
        child: Text('没有可朗读的句子', style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      itemCount: service.sentences.length,
      separatorBuilder: (context, index) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final sentence = service.sentences[index];
        final active = index == service.currentIndex;
        return Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.09)
              : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: Key('tts-sentence-$index'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => service.jumpTo(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.55)
                      : scheme.outlineVariant,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: active ? scheme.onPrimary : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sentence.text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.55,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaybackBar extends StatelessWidget {
  const _PlaybackBar({required this.service});

  final TtsService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final playing = service.state == TtsPlaybackState.playing;
    final paused = service.state == TtsPlaybackState.paused;
    final canUse = service.initialized && service.sentences.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            key: const Key('tts-play'),
            onPressed: !canUse
                ? null
                : playing
                    ? service.pause
                    : service.play,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 20,
            ),
            label: Text(playing ? '暂停' : (paused ? '继续' : '朗读')),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('tts-stop'),
            tooltip: '停止',
            onPressed: service.state == TtsPlaybackState.idle
                ? null
                : service.stop,
            icon: const Icon(Icons.stop_rounded),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '上一句',
            onPressed: service.currentIndex <= 0
                ? null
                : () => service.jumpTo(service.currentIndex - 1),
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton(
            tooltip: '下一句',
            onPressed: service.currentIndex < 0 ||
                    service.currentIndex >= service.sentences.length - 1
                ? null
                : () => service.jumpTo(service.currentIndex + 1),
            icon: const Icon(Icons.skip_next_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _stateLabel(service),
              key: const Key('tts-state'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(TtsService service) {
    return switch (service.state) {
      TtsPlaybackState.playing =>
        '正在朗读第 ${service.currentIndex + 1} / ${service.sentences.length} 句',
      TtsPlaybackState.paused => '已暂停 · 当前句保持不变',
      TtsPlaybackState.idle => service.currentIndex < 0
          ? '待播放 · 点击句子可从该句开始'
          : '已定位到第 ${service.currentIndex + 1} 句',
    };
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.service, this.height});

  final TtsService service;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: height == null
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text('引擎回调', style: theme.textTheme.labelLarge),
                const Spacer(),
                Text(
                  '实时',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: scheme.outlineVariant),
          Expanded(
            child: service.logs.isEmpty
                ? Center(
                    child: Text(
                      '等待 TTS 事件…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                    itemCount: service.logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        service.logs[index],
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 11,
                          height: 1.35,
                          color: scheme.onSurface.withValues(alpha: 0.67),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
