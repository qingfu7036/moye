import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as image;

import '../../../../core/models/annotation.dart';

/// A screenshot-like rectangular selection layer used by both readers.
///
/// The child is wrapped in a RepaintBoundary so the selected region can be
/// cropped without including the floating controls or the note dialog.
class RegionMarkLayer extends StatefulWidget {
  const RegionMarkLayer({
    super.key,
    required this.boundaryKey,
    required this.child,
    required this.marking,
    required this.annotations,
    required this.onSelected,
    required this.onAnnotationTap,
    required this.onCancel,
  });

  final GlobalKey boundaryKey;
  final Widget child;
  final bool marking;
  final List<RegionAnnotation> annotations;
  final ValueChanged<Rect> onSelected;
  final ValueChanged<RegionAnnotation> onAnnotationTap;
  final VoidCallback onCancel;

  @override
  State<RegionMarkLayer> createState() => _RegionMarkLayerState();
}

class _RegionMarkLayerState extends State<RegionMarkLayer> {
  Offset? _start;
  Offset? _end;

  Rect? get _selection {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final selection = _selection;
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(key: widget.boundaryKey, child: widget.child),
            if (!widget.marking)
              for (final annotation in widget.annotations)
                _marker(annotation, size),
            if (widget.marking)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    setState(() {
                      _start = details.localPosition;
                      _end = details.localPosition;
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() => _end = details.localPosition);
                  },
                  onPanEnd: (_) {
                    final rect = _selection;
                    if (rect == null || rect.width < 12 || rect.height < 12) {
                      setState(() {
                        _start = null;
                        _end = null;
                      });
                      return;
                    }
                    final normalized = Rect.fromLTWH(
                      (rect.left / size.width).clamp(0.0, 1.0),
                      (rect.top / size.height).clamp(0.0, 1.0),
                      (rect.width / size.width).clamp(0.0, 1.0),
                      (rect.height / size.height).clamp(0.0, 1.0),
                    );
                    setState(() {
                      _start = null;
                      _end = null;
                    });
                    widget.onSelected(normalized);
                  },
                  child: Stack(
                    children: [
                      Container(color: Colors.black.withValues(alpha: 0.12)),
                      if (selection != null)
                        Positioned.fromRect(
                          rect: selection,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.18),
                              border: Border.all(color: Colors.amber, width: 2),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.crop_free_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 7),
                                  const Text(
                                    '拖动框选要标记的区域',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: widget.onCancel,
                                    child: const Text(
                                      '取消',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _marker(RegionAnnotation annotation, Size size) {
    final left = annotation.left * size.width;
    final top = annotation.top * size.height;
    final width = annotation.width * size.width;
    final height = annotation.height * size.height;
    if (width < 4 || height < 4) return const SizedBox.shrink();
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        key: Key('annotation-marker-${annotation.id}'),
        onTap: () => widget.onAnnotationTap(annotation),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.16),
            border: Border.all(
              color: Colors.amber.shade700.withValues(alpha: 0.9),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.topRight,
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.amber,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notes_rounded,
              size: 10,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// Crops the selected visible region into a PNG. Returns null when the current
/// platform cannot capture the reader surface; the annotation is still saved.
Future<Uint8List?> captureRegion(
  GlobalKey boundaryKey,
  Rect normalizedSelection, {
  double pixelRatio = 2,
}) async {
  try {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final boundary = object;
    final full = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await full.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final decoded = image.decodePng(byteData.buffer.asUint8List());
    if (decoded == null) return null;
    final left = (normalizedSelection.left * decoded.width).round();
    final top = (normalizedSelection.top * decoded.height).round();
    final width = (normalizedSelection.width * decoded.width).round();
    final height = (normalizedSelection.height * decoded.height).round();
    if (width < 1 || height < 1) return null;
    final crop = image.copyCrop(
      decoded,
      x: left.clamp(0, decoded.width - 1),
      y: top.clamp(0, decoded.height - 1),
      width: width.clamp(1, decoded.width - left.clamp(0, decoded.width - 1)),
      height: height.clamp(
        1,
        decoded.height - top.clamp(0, decoded.height - 1),
      ),
    );
    return Uint8List.fromList(image.encodePng(crop));
  } catch (_) {
    return null;
  }
}

/// Small note editor shared by PDF/EPUB marker flows.
Future<String?> showAnnotationNoteDialog(
  BuildContext context, {
  Uint8List? imageBytes,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NoteEditorDialog(imageBytes: imageBytes),
  );
}

class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.imageBytes});

  final Uint8List? imageBytes;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = widget.imageBytes;
    return AlertDialog(
      title: const Text('给这个标记写备注'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageBytes != null && imageBytes.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  imageBytes,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
            if (imageBytes != null && imageBytes.isNotEmpty)
              const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '例如：这里解释了…… / 这段很重要 / 待查资料',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '备注可以为空；保存后会出现在本书的标记仓库中。',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('保存标记'),
        ),
      ],
    );
  }
}
