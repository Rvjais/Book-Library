import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/formatting.dart';
import '../../../data/library_repository.dart';
import '../../../data/models.dart';
import '../../common/app_sheet.dart';

Future<Bookmark?> showBookmarksSheet(
  BuildContext context, {
  required Book book,
  required LibraryRepository repo,
  required VoidCallback onChanged,
  required int Function(Bookmark bookmark) pageFor,
}) {
  return showAppSheet<Bookmark>(
    context: context,
    builder: (_) => _BookmarksSheet(
      book: book,
      repo: repo,
      onChanged: onChanged,
      pageFor: pageFor,
    ),
  );
}

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.book,
    required this.repo,
    required this.onChanged,
    required this.pageFor,
  });

  final Book book;
  final LibraryRepository repo;
  final VoidCallback onChanged;
  final int Function(Bookmark bookmark) pageFor;

  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  List<Bookmark>? _bookmarks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bookmarks = await widget.repo.bookmarksFor(widget.book.id);
    if (!mounted) return;
    setState(() => _bookmarks = bookmarks);
  }

  Future<void> _editNote(Bookmark bookmark) async {
    final controller = TextEditingController(text: bookmark.note);
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bookmark note'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'A thought, a quote, a reminder…',
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
              child: const Text('Save note'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (note == null || !mounted) return;

    await widget.repo.updateBookmarkNote(bookmark, note);
    if (!mounted) return;
    setState(() {
      _bookmarks = [
        for (final item in _bookmarks ?? const <Bookmark>[])
          if (item.id == bookmark.id) item.copyWith(note: note) else item,
      ];
    });
    widget.onChanged();
  }

  Future<void> _delete(Bookmark bookmark) async {
    await widget.repo.deleteBookmark(bookmark.id);
    if (!mounted) return;
    setState(() {
      _bookmarks = [
        for (final item in _bookmarks ?? const <Bookmark>[])
          if (item.id != bookmark.id) item,
      ];
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookmarks = _bookmarks;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          title: 'Bookmarks',
          subtitle: bookmarks == null
              ? 'Loading saved places…'
              : '${bookmarks.length} saved '
                  '${bookmarks.length == 1 ? 'place' : 'places'} in this book',
        ),
        Flexible(
          child: bookmarks == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 44),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                )
              : bookmarks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(30, 12, 30, 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_border_rounded,
                            size: 40,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.55),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No bookmarks yet',
                            style: serifStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap the ribbon in the reader to save your place.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                      itemCount: bookmarks.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.18),
                      ),
                      itemBuilder: (context, index) {
                        final bookmark = bookmarks[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 8,
                            right: 0,
                            top: 2,
                            bottom: 2,
                          ),
                          leading: const Icon(
                            Icons.bookmark_rounded,
                            color: AppColors.brass,
                            size: 20,
                          ),
                          title: Text(
                            bookmark.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: serifStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              'Page ${widget.pageFor(bookmark) + 1}  ·  '
                              '${formatShortDate(bookmark.createdAt)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Bookmark options',
                            icon: const Icon(Icons.more_vert_rounded, size: 19),
                            onSelected: (value) {
                              if (value == 'note') {
                                _editNote(bookmark);
                              } else if (value == 'delete') {
                                _delete(bookmark);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'note',
                                child: Text('Edit note'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete bookmark'),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(bookmark),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
