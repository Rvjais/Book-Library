import 'package:flutter/material.dart';

import '../../../data/reader_settings.dart';
import '../../common/app_sheet.dart';
import '../../settings/widgets/reader_settings_panel.dart';

Future<void> showReaderSettingsSheet(
  BuildContext context,
  ReaderSettings settings,
  ValueChanged<ReaderSettings> onChanged, {
  bool isPdf = false,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) => _ReaderSettingsSheet(
      initialSettings: settings,
      onChanged: onChanged,
      isPdf: isPdf,
    ),
  );
}

class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({
    required this.initialSettings,
    required this.onChanged,
    required this.isPdf,
  });

  final ReaderSettings initialSettings;
  final ValueChanged<ReaderSettings> onChanged;
  final bool isPdf;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late ReaderSettings _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialSettings;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeader(
          title: 'Reading settings',
          subtitle: 'Applied right away, and remembered for every book.',
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: ReaderSettingsPanel(
              settings: _current,
              isPdf: widget.isPdf,
              onChanged: (value) {
                setState(() => _current = value);
                widget.onChanged(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}
