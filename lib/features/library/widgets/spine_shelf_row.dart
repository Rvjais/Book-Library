import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../data/models.dart';
import 'wood_background.dart';

/// Width of one spine, scaling realistically with the book's total page count.
/// Thin pamphlets/short books are slender (~22-26px), while thick tomes
/// expand up to ~46px, with subtle title-based variation for books with unknown page count.
double spineWidthFor(Book book) {
  if (book.pageCount > 0) {
    // 1 to 50 pages -> ~22px
    // 300 pages -> ~29px
    // 600 pages -> ~36px
    // 1000+ pages -> ~45px
    final pages = book.pageCount.clamp(1, 1500);
    final width = 22.0 + (pages / 1500.0) * 24.0;
    return width.clamp(22.0, 46.0);
  }
  final hash = book.title.hashCode & 0x7fffffff;
  return 24.0 + (hash % 11);
}

/// The small gap between neighbouring spines.
const double spineGap = 2.0;

/// A board of the bookcase where the books stand shoulder to shoulder and only
/// their spines are visible, like a packed home library.
class SpineShelfRow extends StatelessWidget {
  const SpineShelfRow({
    super.key,
    required this.books,
    required this.maxHeight,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Book> books;
  final double maxHeight;
  final ValueChanged<Book> onOpen;
  final ValueChanged<Book> onLongPress;

  static const double _plankHeight = 24;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: maxHeight + _plankHeight,
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
            left: 5,
            right: 5,
            top: 0,
            bottom: 13,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final book in books)
                  Padding(
                    padding: const EdgeInsets.only(right: spineGap),
                    child: _SpineBook(
                      book: book,
                      maxHeight: maxHeight,
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

class _SpineBook extends StatefulWidget {
  const _SpineBook({
    required this.book,
    required this.maxHeight,
    required this.onTap,
    required this.onLongPress,
  });

  final Book book;
  final double maxHeight;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_SpineBook> createState() => _SpineBookState();
}

class _SpineBookState extends State<_SpineBook> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  /// Spines vary in height and thickness like a real, hand-built shelf.
  double get _height {
    final hash = widget.book.title.hashCode & 0x7fffffff;
    return widget.maxHeight * (0.80 + (hash % 19) / 100);
  }

  double get _tilt {
    final hash = widget.book.title.hashCode & 0x7fffffff;
    if (hash % 7 != 0) return 0;
    return (hash.isEven ? 1 : -1) * 0.028;
  }

  @override
  Widget build(BuildContext context) {
    final width = spineWidthFor(widget.book);
    final height = _height;
    final palette = _paletteFor(widget.book);
    final light = ThemeData.estimateBrightnessForColor(palette.first) ==
        Brightness.light;
    final ink = light ? const Color(0xFF3B2B1B) : const Color(0xFFF6EBD8);
    final accent = light
        ? const Color(0xFF6B4A28).withValues(alpha: 0.55)
        : AppColors.brass.withValues(alpha: 0.75);

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
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: Transform.rotate(
          angle: _tilt,
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Contact shadow on the wooden board.
                Positioned(
                  left: 2,
                  right: 2,
                  bottom: -2,
                  height: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.62),
                          blurRadius: 5,
                          spreadRadius: 0.5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1.6),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: palette,
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.34),
                        width: 0.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.42),
                          blurRadius: 6,
                          offset: const Offset(1.5, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Rounded spine edge: a dark crease then a light ridge.
                        Positioned(
                          left: 1.4,
                          top: 0,
                          bottom: 0,
                          width: 1,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.28),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          top: 0,
                          bottom: 0,
                          width: 1.2,
                          child: ColoredBox(
                            color: Colors.white.withValues(alpha: 0.13),
                          ),
                        ),

                        // Decorative bands near the head and tail.
                        Positioned(
                          top: 7,
                          left: 3,
                          right: 3,
                          height: 1,
                          child: ColoredBox(color: accent),
                        ),
                        Positioned(
                          top: 10,
                          left: 3,
                          right: 3,
                          height: 0.7,
                          child: ColoredBox(
                            color: accent.withValues(alpha: 0.55),
                          ),
                        ),
                        Positioned(
                          bottom: 8,
                          left: 3,
                          right: 3,
                          height: 1,
                          child: ColoredBox(color: accent),
                        ),

                        // Title and author run down the spine.
                        Positioned.fill(
                          child: ClipRect(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 1,
                                vertical: 15,
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      RotatedBox(
                                        quarterTurns: 1,
                                        child: SizedBox(
                                          width: height * 0.58,
                                          child: Text(
                                            widget.book.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: serifStyle(
                                              fontSize: width >= 30 ? 9.0 : 8.2,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.2,
                                              color: ink,
                                            ).copyWith(
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black.withValues(
                                                    alpha: light ? 0.12 : 0.45,
                                                  ),
                                                  blurRadius: 2,
                                                  offset: const Offset(0, 0.6),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (width >= 31) ...[
                                        const SizedBox(width: 1),
                                        RotatedBox(
                                          quarterTurns: 1,
                                          child: SizedBox(
                                            width: height * 0.26,
                                            child: Text(
                                              widget.book.author.isEmpty
                                                  ? widget.book.format.label
                                                  : widget.book.author,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 7.0,
                                                letterSpacing: 0.15,
                                                color: ink.withValues(alpha: 0.72),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Reading progress running up the outer edge.
                        if (widget.book.hasStarted)
                          Positioned(
                            right: 1.6,
                            top: 12,
                            bottom: 12,
                            width: 2,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor:
                                    widget.book.progress.clamp(0.0, 1.0),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppColors.brass.withValues(
                                      alpha: light ? 0.95 : 0.9,
                                    ),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (widget.book.isFavorite)
                          Positioned(
                            top: 2,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Icon(
                                Icons.star_rounded,
                                size: 6.5,
                                color: ink.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<List<Color>> _spinePalettes = [
    [Color(0xFF8E3033), Color(0xFF5A171A)],
    [Color(0xFF2F6C73), Color(0xFF173F45)],
    [Color(0xFFB5832F), Color(0xFF7A5316)],
    [Color(0xFF33506F), Color(0xFF1A2D43)],
    [Color(0xFF6D4B7A), Color(0xFF3E2749)],
    [Color(0xFF3E5C4A), Color(0xFF22382C)],
    [Color(0xFFA45A35), Color(0xFF66331B)],
    [Color(0xFFCBB99B), Color(0xFFA38A68)],
    [Color(0xFF52684E), Color(0xFF2D3F2B)],
    [Color(0xFF4B5663), Color(0xFF2A323B)],
    [Color(0xFF7C6A3F), Color(0xFF4E4022)],
    [Color(0xFF8A6F52), Color(0xFF57402A)],
  ];

  List<Color> _paletteFor(Book book) {
    final hash = book.title.hashCode & 0x7fffffff;
    return _spinePalettes[hash % _spinePalettes.length];
  }
}
