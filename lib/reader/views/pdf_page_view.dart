import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/reader_settings.dart';
import '../engines/pdf_engine.dart';

class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.engine,
    required this.pageIndex,
    required this.settings,
    this.safeInsets = EdgeInsets.zero,
  });

  final PdfReaderEngine engine;
  final int pageIndex;
  final ReaderSettings settings;
  final EdgeInsets safeInsets;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  late Future<ui.Image> _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.engine != widget.engine) {
      _load();
    }
  }

  void _load() {
    _image = widget.engine.imageFor(widget.pageIndex);
    widget.engine.prefetch(widget.pageIndex);
  }

  Widget _buildThemedImage(ui.Image image) {
    final raw = RawImage(
      image: image,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
    );

    final theme = widget.settings.theme;
    switch (theme) {
      case ReaderTheme.light:
        // Default paper look: multiply slightly with warm paper tint
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            widget.settings.palette.page,
            BlendMode.multiply,
          ),
          child: raw,
        );

      case ReaderTheme.sepia:
        // Sepia tint: invert colors don't apply, multiply page color over white/grayscale document
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            widget.settings.palette.page,
            BlendMode.multiply,
          ),
          child: raw,
        );

      case ReaderTheme.dark:
        // Invert luminance (negate RGB) + multiply night palette color for comfortable reading
        const invertMatrix = <double>[
          -1.0, 0, 0, 0, 255, // red
          0, -1.0, 0, 0, 255, // green
          0, 0, -1.0, 0, 255, // blue
          0, 0, 0, 1.0, 0, // alpha
        ];
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(invertMatrix),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFFE8DFD0),
              BlendMode.modulate,
            ),
            child: raw,
          ),
        );

      case ReaderTheme.black:
        // Pure black OLED theme: invert so white PDF becomes true dark mode
        const invertMatrix = <double>[
          -1.0, 0, 0, 0, 255,
          0, -1.0, 0, 0, 255,
          0, 0, -1.0, 0, 255,
          0, 0, 0, 1.0, 0,
        ];
        return ColorFiltered(
          colorFilter: const ColorFilter.matrix(invertMatrix),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFFD6CFC7),
              BlendMode.modulate,
            ),
            child: raw,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.settings.palette;
    return ColoredBox(
      color: palette.page,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.safeInsets.left + 8,
          widget.safeInsets.top + 8,
          widget.safeInsets.right + 8,
          widget.safeInsets.bottom + 8,
        ),
        child: FutureBuilder<ui.Image>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'This page could not be rendered.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
              );
            }
            final image = snapshot.data;
            if (image == null) {
              return Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
              );
            }
            return _buildThemedImage(image);
          },
        ),
      ),
    );
  }
}
