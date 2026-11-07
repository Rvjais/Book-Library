import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/formatting.dart';
import '../../../data/models.dart';
import 'book_cover_view.dart';
import 'wood_background.dart';

/// One board of the bookcase: dates above the covers, a wooden plank below.
class ShelfRow extends StatelessWidget {
  const ShelfRow({
    super.key,
    required this.books,
    required this.slotWidth,
    required this.coverWidth,
    required this.coverHeight,
    required this.showDates,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Book> books;
  final double slotWidth;
  final double coverWidth;
  final double coverHeight;
  final bool showDates;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onLongPress;

  static const double _dateHeight = 13;
  static const double _dateGap = 4;
  static const double _titleHeight = 30; // Height reserved for book title below
  static const double _titleGap = 4;
  static const double _plankHeight = 30;
  static const double _plankTop = 16;

  @override
  Widget build(BuildContext context) {
    final height = _dateHeight +
        _dateGap +
        coverHeight +
        _titleGap +
        _titleHeight +
        _plankHeight;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _plankHeight,
            child: RepaintBoundary(
              child: CustomPaint(painter: ShelfPlankPainter()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _plankTop,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final book in books)
                  SizedBox(
                    width: slotWidth,
                    child: _ShelfBook(
                      book: book,
                      coverWidth: coverWidth,
                      coverHeight: coverHeight,
                      showDate: showDates,
                      dateHeight: _dateHeight,
                      dateGap: _dateGap,
                      titleHeight: _titleHeight,
                      titleGap: _titleGap,
                      onTap: () => onOpen(book),
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        onLongPress(book);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfBook extends StatefulWidget {
  const _ShelfBook({
    required this.book,
    required this.coverWidth,
    required this.coverHeight,
    required this.showDate,
    required this.dateHeight,
    required this.dateGap,
    required this.titleHeight,
    required this.titleGap,
    required this.onTap,
    required this.onLongPress,
  });

  final Book book;
  final double coverWidth;
  final double coverHeight;
  final bool showDate;
  final double dateHeight;
  final double dateGap;
  final double titleHeight;
  final double titleGap;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_ShelfBook> createState() => _ShelfBookState();
}

class _ShelfBookState extends State<_ShelfBook> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: widget.dateHeight,
              child: Center(
                child: Text(
                  widget.showDate ? formatShelfDate(widget.book.shelfDate) : '',
                  maxLines: 1,
                  style: serifStyle(
                    fontSize: 9.5,
                    color: const Color(0xFFEBDABD).withValues(alpha: 0.88),
                    letterSpacing: 0.4,
                  ).copyWith(
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: widget.dateGap),
            // Stand-up realistic book container with drop contact shadow onto the wooden plank
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Floor contact shadow beneath the standing book
                Positioned(
                  bottom: -2,
                  left: 3,
                  right: 3,
                  height: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.70),
                          blurRadius: 5,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: widget.coverWidth,
                  height: widget.coverHeight,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.52),
                        blurRadius: 10,
                        offset: const Offset(1, 4),
                      ),
                    ],
                  ),
                  child: BookCoverView(
                    book: widget.book,
                    width: widget.coverWidth,
                    height: widget.coverHeight,
                  ),
                ),
              ],
            ),
            SizedBox(height: widget.titleGap),
            // Book title displayed below the book on the shelf
            SizedBox(
              height: widget.titleHeight,
              width: widget.coverWidth + 14,
              child: Center(
                child: Text(
                  widget.book.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: serifStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF6EBD8),
                    height: 1.15,
                  ).copyWith(
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.75),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
