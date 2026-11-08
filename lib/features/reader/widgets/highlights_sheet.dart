import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/formatting.dart';
import '../../../data/library_repository.dart';
import '../../../data/models.dart';
import '../../common/app_sheet.dart';

Future<BookHighlight?> showHighlightsSheet(
  BuildContext context, {
  required Book book,
  required LibraryRepository repo,
  required VoidCallback onChanged,
  required int Function(BookHighlight highlight) pageFor,
}) {
  return showAppSheet<BookHighlight>(
    context: context,
    builder: (_) => _HighlightsSheet(
      book: book,
      repo: repo,
      onChanged: onChanged,
      pageFor: pageFor,
    ),
  );
}

class _HighlightsSheet extends StatefulWidget {
  const _HighlightsSheet({
    required this.book,
    required this.repo,
    required this.onChanged,
    required this.pageFor,
  });

  final Book book;
  final LibraryRepository repo;
  final VoidCallback onChanged;

  /// Resolves an anchor to the page it currently lives on, so the list keeps
  /// showing correct page numbers after re-pagination.
  final int Function(BookHighlight highlight) pageFor;

  @override
  State<_HighlightsSheet> createState() => _HighlightsSheetState();
}

class _HighlightsSheetState extends State<_HighlightsSheet> {
  List<BookHighlight>? _highlights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.repo.highlightsFor(widget.book.id);
    if (!mounted) return;
    setState(() => _highlights = list);
  }

  Future<void> _editNote(BookHighlight highlight) async {
    final controller = TextEditingController(text: highlight.note);
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Highlight note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add a thought or reminder…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (note == null) return;
    await widget.repo.updateHighlightNote(highlight, note);
    widget.onChanged();
    await _load();
  }

  Future<void> _delete(BookHighlight highlight) async {
    await widget.repo.deleteHighlight(highlight.id);
    widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final highlights = _highlights;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: 'Highlights',
          subtitle: highlights == null
              ? 'Loading…'
              : (highlights.isEmpty
                  ? 'No highlights yet'
                  : '${highlights.length} ${highlights.length == 1 ? 'highlight' : 'highlights'}'),
        ),
        if (highlights == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (highlights.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 36),
            child: Center(
              child: Text(
                'Long press and drag on any text or use "Add Highlight" to save memorable quotes.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: highlights.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final h = highlights[index];
                return Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pop(h),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Color(h.color),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '“${h.text}”',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: serifStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                if (h.note.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    h.note,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.brass,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Page ${widget.pageFor(h) + 1} · ${formatShortDate(h.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            tooltip: 'Edit note',
                            onPressed: () => unawaited(_editNote(h)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            tooltip: 'Delete',
                            onPressed: () => unawaited(_delete(h)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
