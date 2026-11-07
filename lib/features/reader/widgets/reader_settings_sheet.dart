import 'package:flutter/material.dart';

import '../../../data/reader_settings.dart';
import '../../common/app_sheet.dart';
import '../../settings/widgets/reader_settings_panel.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context,
  ReaderSettings settings,
  ValueChanged<ReaderSettings> onChanged,
) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) {
      var current = settings;
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(
                title: 'Reading settings',
                subtitle: 'Changes apply to this book right away.',
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: ReaderSettingsPanel(
                    settings: current,
                    onChanged: (value) {
                      setSheetState(() => current = value);
                      onChanged(value);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
