import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../engines/pdf_engine.dart';

class PdfPageView extends StatefulWidget {
  const PdfPageView({
    super.key,
    required this.engine,
    required this.pageIndex,
    this.safeInsets = EdgeInsets.zero,
  });

  final PdfReaderEngine engine;
  final int pageIndex;
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

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFFEFB),
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
                    style: const TextStyle(color: Color(0xFF6B5B48), fontSize: 13),
                  ),
                ),
              );
            }
            final image = snapshot.data;
            if (image == null) {
              return const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF8A6A45),
                  ),
                ),
              );
            }
            return RawImage(
              image: image,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.medium,
            );
          },
        ),
      ),
    );
  }
}
