import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import 'editor_motion.dart';

class PreviewAttachment extends StatefulWidget {
  const PreviewAttachment({
    super.key,
    required this.readImage,
    required this.noteId,
    required this.reference,
    required this.alt,
    required this.placeholder,
  });

  final Future<Uint8List?> Function(String noteId, String reference) readImage;
  final String noteId;
  final String reference;
  final String? alt;
  final Widget placeholder;

  @override
  State<PreviewAttachment> createState() => _PreviewAttachmentState();
}

class _PreviewAttachmentState extends State<PreviewAttachment> {
  late Future<Uint8List?> _bytes;
  bool _showInk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PreviewAttachment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId ||
        oldWidget.reference != widget.reference ||
        oldWidget.readImage != widget.readImage) {
      _load();
    }
  }

  void _load() {
    _showInk = false;
    _bytes = widget.readImage(widget.noteId, widget.reference);
  }

  Future<void> _showFullImage(Uint8List bytes) => showDialog<void>(
    context: context,
    animationStyle: EditorMotion.dialog(context),
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final alt = widget.alt;
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width - 40,
          height: size.height - 40,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        alt == null || alt.isEmpty ? 'Imagen original' : alt,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar imagen',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: InteractiveViewer(
                  maxScale: 6,
                  trackpadScrollCausesScale: true,
                  child: SizedBox.expand(
                    child: Image.memory(
                      bytes,
                      semanticLabel: alt,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Center(child: widget.placeholder),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done || bytes == null) {
        return widget.placeholder;
      }
      final original = Image.memory(
        bytes,
        semanticLabel: widget.alt,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => widget.placeholder,
      );
      final style = FolioStyle.of(context);
      if (!style.isRetro) return original;

      final paper = Theme.of(context).colorScheme.surface;
      return Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: Container(
          decoration: style.panel(paper, lift: 4),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showInk)
                _InkPrint(
                  bytes: bytes,
                  paper: paper,
                  ink: style.ink,
                  alt: widget.alt,
                  fallback: original,
                )
              else
                original,
              Material(
                color: paper,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('Original')),
                          ButtonSegment(value: true, label: Text('Tramado')),
                        ],
                        selected: {_showInk},
                        onSelectionChanged: (values) =>
                            setState(() => _showInk = values.single),
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(fontSize: 11),
                          ),
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ampliar original',
                        onPressed: () => _showFullImage(bytes),
                        icon: const Icon(Icons.zoom_in, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InkPrint extends StatefulWidget {
  const _InkPrint({
    required this.bytes,
    required this.paper,
    required this.ink,
    required this.alt,
    required this.fallback,
  });

  final Uint8List bytes;
  final Color paper;
  final Color ink;
  final String? alt;
  final Widget fallback;

  @override
  State<_InkPrint> createState() => _InkPrintState();
}

typedef _Print = ({ui.Image image, double scale});

class _InkPrintState extends State<_InkPrint> {
  _Print? _print;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(_InkPrint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.paper != widget.paper ||
        oldWidget.ink != widget.ink) {
      _print?.image.dispose();
      _print = null;
      _render();
    }
  }

  Future<void> _render() async {
    final revision = ++_revision;
    final _Print? print;
    try {
      print = await _makePrint(
        widget.bytes,
        ink: widget.ink.toARGB32(),
        paper: widget.paper.toARGB32(),
      );
    } catch (_) {
      return; // The ordinary image remains available if processing fails.
    }
    if (print == null) return;
    if (!mounted || revision != _revision) {
      print.image.dispose();
      return;
    }
    setState(() => _print = print);
  }

  @override
  void dispose() {
    _print?.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final print = _print;
    if (print == null) return widget.fallback;
    return Semantics(
      image: true,
      label: widget.alt,
      child: RawImage(
        image: print.image,
        scale: print.scale,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
      ),
    );
  }
}

Future<_Print?> _makePrint(
  Uint8List bytes, {
  required int ink,
  required int paper,
}) async {
  const maxDimension = 1200;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: width >= height && width > maxDimension
          ? maxDimension
          : null,
      targetHeight: height > width && height > maxDimension
          ? maxDimension
          : null,
    );
    if (codec.frameCount != 1) return null;
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    final pixels = await compute(_dither, (
      rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: image.width,
      height: image.height,
      ink: ink,
      paper: paper,
    ));
    return (
      image: await _imageFromPixels(pixels, image.width, image.height),
      scale: image.width / width,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _imageFromPixels(
  Uint8List pixels,
  int width,
  int height,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec();
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Uint8List _dither(
  ({Uint8List rgba, int width, int height, int ink, int paper}) source,
) {
  // A Bayer grid turns midtones into dots while keeping highlights and shadows solid.
  const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
  final pixels = source.rgba;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final i = (y * source.width + x) * 4;
      // The decoded RGB channels are premultiplied. Composite them on white.
      final luma =
          (54 * pixels[i] + 183 * pixels[i + 1] + 19 * pixels[i + 2]) / 256 +
          255 -
          pixels[i + 3];
      final threshold = (bayer[(y & 3) * 4 + (x & 3)] + 0.5) * 16;
      // Keep dark UI backgrounds solid and reserve the grid for midtones.
      final lightness = (luma - 48) * (255 / (222 - 48));
      final tone = lightness < threshold ? source.ink : source.paper;
      pixels[i] = (tone >> 16) & 0xff;
      pixels[i + 1] = (tone >> 8) & 0xff;
      pixels[i + 2] = tone & 0xff;
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}
