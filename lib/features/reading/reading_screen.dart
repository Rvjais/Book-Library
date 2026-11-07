import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/formatting.dart';
import '../../data/library_repository.dart';
import '../../data/models.dart';
import '../library/widgets/book_cover_view.dart';
import '../reader/open_book.dart';

class ReadingScreen extends StatelessWidget {
  const ReadingScreen({super.key, required this.onBrowseLibrary});

  final VoidCallback onBrowseLibrary;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LibraryRepository>();
    final theme = Theme.of(context);
    final inProgress = repo.inProgress;
    final finished = repo.books
        .where((book) => book.isFinished)
        .toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surface,
                    theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                Text(
                  'Reading',
                  style: serifStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  repo.bookCount == 0
                      ? 'Your personal reading room.'
                      : '${repo.readingCount} in progress  ·  '
                          '${repo.finishedCount} finished',
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (repo.bookCount == 0)
                  _EmptyReading(onBrowse: onBrowseLibrary)
                else ...[
                  if (inProgress.isNotEmpty)
                    _ContinueCard(
                      book: inProgress.first,
                      onTap: () => _open(context, inProgress.first),
                    )
                  else
                    _IdleCard(
                      hasBooks: repo.bookCount > 0,
                      onBrowse: onBrowseLibrary,
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          value: '${repo.readingCount}',
                          label: 'In progress',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          value: '${repo.finishedCount}',
                          label: 'Finished',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          value:
                              '${repo.books.where((b) => b.isFavorite).length}',
                          label: 'Favourites',
                        ),
                      ),
                    ],
                  ),
                  if (inProgress.length > 1) ...[
                    const SizedBox(height: 26),
                    const _SectionTitle('Also in progress'),
                    const SizedBox(height: 10),
                    for (final book in inProgress.skip(1))
                      _ReadingRow(
                        book: book,
                        onTap: () => _open(context, book),
                      ),
                  ],
                  if (finished.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const _SectionTitle('Finished'),
                    const SizedBox(height: 10),
                    for (final book in finished.take(8))
                      _ReadingRow(
                        book: book,
                        finished: true,
                        onTap: () => _open(context, book),
                      ),
                  ],
                  if (inProgress.length == 1 && finished.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: Text(
                        'The books you are reading will gather here, '
                        'with your progress kept safely on this device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Book book) {
    unawaited(openBook(context, book));
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF57371F), Color(0xFF3B2413)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fade(AppColors.brass, 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCoverView(book: book, width: 80, height: 116),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'CONTINUE READING',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppColors.brass,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serifStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFF7EBD4),
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        book.author.isEmpty ? book.format.label : book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: const Color(0xFFD9C6A6).withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: book.progress.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.14),
                                color: AppColors.brass,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatPercent(book.progress),
                            style: const TextStyle(
                              fontSize: 10,
                              fontFeatures: [
                                FontFeature.tabularFigures(),
                              ],
                              color: Color(0xFFF3E8D2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            size: 17,
                            color: Color(0xFFF3E8D2),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Resume',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF3E8D2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'page ${book.readingPosition.page + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              color: const Color(0xFFD9C6A6)
                                  .withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.hasBooks, required this.onBrowse});

  final bool hasBooks;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.nightlight_round,
            size: 28,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            'Nothing open right now',
            style: serifStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasBooks
                ? 'Choose a book from your shelves to start reading.'
                : 'Add a few books, then pick one up.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.auto_stories_outlined, size: 18),
            label: const Text('Browse the library'),
          ),
        ],
      ),
    );
  }
}

class _EmptyReading extends StatelessWidget {
  const _EmptyReading({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 52,
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 18),
          Text(
            'No books yet',
            textAlign: TextAlign.center,
            style: serifStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Add PDF and EPUB books in the Library tab.\n'
            'Everything is stored privately on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onBrowse,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Go to library'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: serifStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.book,
    required this.onTap,
    this.finished = false,
  });

  final Book book;
  final VoidCallback onTap;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                BookCoverView(book: book, width: 44, height: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: serifStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        book.author.isEmpty ? book.format.label : book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: book.progress.clamp(0.0, 1.0),
                                minHeight: 3,
                                backgroundColor: theme.colorScheme.outline
                                    .withValues(alpha: 0.25),
                                color: finished
                                    ? AppColors.forest
                                    : AppColors.brass,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            finished ? 'Finished' : formatPercent(book.progress),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  finished
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  size: 19,
                  color: finished
                      ? AppColors.forest
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
