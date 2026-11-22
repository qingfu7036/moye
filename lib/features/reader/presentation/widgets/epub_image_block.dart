import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Renders an EPUB image at the same content scale as the surrounding text.
///
/// Reflowable EPUBs do not have a fixed page to zoom. Scaling the image with
/// the text keeps the two visually consistent; when the scaled image is wider
/// than the reading column, it gets its own horizontal scroll area instead of
/// being clipped by the vertical reader.
class EpubImageBlock extends StatelessWidget {
  const EpubImageBlock({
    super.key,
    required this.bytes,
    required this.scale,
    this.onTap,
    this.scrollKey,
  });

  final Uint8List bytes;
  final double scale;
  final VoidCallback? onTap;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * scale;
          final oversized = width > constraints.maxWidth + 0.5;
          final image = Image.memory(
            bytes,
            width: width,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
          );
          final content = NotificationListener<ScrollNotification>(
            onNotification: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              key: scrollKey,
              scrollDirection: Axis.horizontal,
              primary: false,
              physics: oversized
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: oversized
                  ? image
                  : SizedBox(
                      width: constraints.maxWidth,
                      child: Center(child: image),
                    ),
            ),
          );
          if (onTap == null) return content;
          return Stack(
            children: [
              content,
              Positioned(
                top: 4,
                right: 4,
                child: IconButton.filledTonal(
                  tooltip: '全屏查看图片',
                  onPressed: onTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
