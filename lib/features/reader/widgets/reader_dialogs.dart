import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../reader/engines/pdf_engine.dart';

Future<int?> showPageJumpDialog(
  BuildContext context, {
  required int pageCount,
  required int currentPage,
}) async {
  final controller = TextEditingController(text: '${currentPage + 1}');
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) {
      void submit() {
        final value = int.tryParse(controller.text.trim());
        if (value == null) return;
        final page = (value - 1).clamp(0, pageCount - 1);
        Navigator.of(dialogContext).pop(page);
      }

      return AlertDialog(
        title: const Text('Go to page'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: 'Page',
                helperText: 'Between 1 and $pageCount',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submit,
            child: const Text('Go'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

Future<void> showPdfZoom(
  BuildContext context, {
  required PdfReaderEngine engine,
  required int pageIndex,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false,
    builder: (_) => _PdfZoomOverlay(engine: engine, pageIndex: pageIndex),
  );
}

class _PdfZoomOverlay extends StatelessWidget {
  const _PdfZoomOverlay({required this.engine, required this.pageIndex});

  final PdfReaderEngine engine;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<ui.Image>(
              future: engine.imageFor(pageIndex),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'This page could not be rendered.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                final image = snapshot.data;
                if (image == null) {
                  return const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.brass,
                      ),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 6,
                      boundaryMargin: const EdgeInsets.all(60),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: RawImage(
                          image: image,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Close',
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  'Page ${pageIndex + 1}  ·  pinch to zoom',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    letterSpacing: 0.4,
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
