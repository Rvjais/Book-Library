import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
