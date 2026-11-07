import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../common/app_sheet.dart';
import '../../../reader/engines/reader_engine.dart';

Future<int?> showTocSheet(
  BuildContext context, {
  required List<ReaderTocEntry> entries,
  required int currentPage,
}) {
  return showAppSheet<int>(
    context: context,
    builder: (_) => _TocSheet(entries: entries, currentPage: currentPage),
  );
}

class _TocSheet extends StatefulWidget {
  const _TocSheet({required this.entries, required this.currentPage});

  final List<ReaderTocEntry> entries;
  final int currentPage;

  @override
  State<_TocSheet> createState() => _TocSheetState();
}

class _TocSheetState extends State<_TocSheet> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  int get _activeIndex {
    var active = -1;
    for (var i = 0; i < widget.entries.length; i++) {
      if (widget.entries[i].pageIndex <= widget.currentPage) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _query.trim().isEmpty
        ? widget.entries
        : widget.entries
            .where((entry) =>
                entry.title.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList();
    final active = _activeIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: 'Contents',
          subtitle: widget.entries.isEmpty
              ? 'No chapters in this file'
              : '${widget.entries.length} chapters',
        ),
        if (widget.entries.length > 12)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _filter,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Find a chapter',
              ),
            ),
          ),
        Flexible(
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 44),
                  child: Text(
                    widget.entries.isEmpty
                        ? 'This file does not include a table of contents. '
                            'You can still turn pages or use the page slider.'
                        : 'No chapter matches “$_query”.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isActive =
                        _query.trim().isEmpty && index == active;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(
                        left: 16 + entry.level.clamp(0, 3) * 16.0,
                        right: 16,
                      ),
                      title: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serifStyle(
                          fontSize: 14.5,
                          fontWeight: isActive ? FontWeight.w600 : null,
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Page ${entry.pageIndex + 1}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.85),
                        ),
                      ),
                      trailing: isActive
                          ? Icon(
                              Icons.bookmark_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(entry.pageIndex),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
