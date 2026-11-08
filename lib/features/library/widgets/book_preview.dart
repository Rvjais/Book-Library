import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/formatting.dart';
import '../../../data/models.dart';
import 'book_cover_view.dart';

/// What the reader chose in the book preview.
enum BookPreviewAction { read, more }

/// Opens the "zoomed in" view of a book from the shelf: the cover grows into
/// the centre of the screen and the book's details are shown around it.
Future<BookPreviewAction?> showBookPreview(BuildContext context, Book book) {
  return showGeneralDialog<BookPreviewAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close book preview',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _BookPreview(book: book);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.84, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class _BookPreview extends StatelessWidget {
  const _BookPreview({required this.book});

  final Book book;

  String get _readLabel {
    if (book.isFinished) return 'Read again';
    if (book.hasStarted) return 'Continue reading';
    return 'Read the book';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final description = (book.description ?? '').trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 430,
          maxHeight: screen.height * 0.86,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.brass.withValues(alpha: 0.30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The cover grows out of the shelf into the panel.
                          Center(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 22,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: BookCoverView(
                                book: book,
                                width: 132,
                                height: 196,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            book.title,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: serifStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              height: 1.17,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          if (book.author.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              book.author,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                letterSpacing: 0.2,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),

                          // Format, size and length at a glance.
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _MetaChip(
                                icon: book.isPdf
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.menu_book_outlined,
                                label: book.format.label,
                                accent: true,
                              ),
                              if (book.pageCount > 0)
                                _MetaChip(
                                  icon: Icons.layers_outlined,
                                  label: '${book.pageCount} pages',
                                ),
                              _MetaChip(
                                icon: Icons.data_usage_rounded,
                                label: formatBytes(book.fileSize),
                              ),
                              if (book.isFavorite)
                                const _MetaChip(
                                  icon: Icons.star_rounded,
                                  label: 'Favourite',
                                  accent: true,
                                ),
                              if (book.isFinished)
                                const _MetaChip(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Finished',
                                ),
                            ],
                          ),

                          if (book.hasStarted) ...[
                            const SizedBox(height: 18),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: book.progress.clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor: theme.colorScheme.outline
                                    .withValues(alpha: 0.25),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.brass,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${formatPercent(book.progress)} read'
                              '${book.pageCount > 0 ? ' · page ${book.readingPosition.page + 1} of ${book.pageCount}' : ''}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],

                          if (book.isPdf) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brass.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      AppColors.brass.withValues(alpha: 0.24),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 15,
                                    color: AppColors.brass,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'PDF pages are fixed images. Text search, '
                                      'contents and text highlights need the '
                                      'EPUB format.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        height: 1.35,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 18),
                          Text(
                            'ABOUT THIS BOOK',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.05,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description.isEmpty
                                ? 'No description was included in this file.'
                                : description,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.86),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),

                  // Actions stay pinned while the details scroll.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pop(BookPreviewAction.read),
                          icon: Icon(
                            book.isFinished
                                ? Icons.replay_rounded
                                : Icons.menu_book_rounded,
                          ),
                          label: Text(_readLabel),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context)
                              .pop(BookPreviewAction.more),
                          child: const Text('More options'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ? AppColors.brass : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.brass.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
