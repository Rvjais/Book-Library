import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../data/models.dart';

/// A cover standing on the shelf: real book 3D depth, layered pages block,
/// spine crease, ridge and light reflection.
class BookCoverView extends StatelessWidget {
  const BookCoverView({
    super.key,
    required this.book,
    required this.width,
    required this.height,
    this.radius = 2.5,
  });

  final Book book;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final coverWidth = width - 4.5;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Hardcover / back board depth shadow
          Positioned(
            left: 2,
            right: 0,
            top: 2,
            bottom: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius + 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 7,
                    offset: const Offset(2.5, 3),
                  ),
                ],
              ),
            ),
          ),

          // Layered paper page block peeking out on the right with page leaf texture
          Positioned(
            right: 0.5,
            top: 3,
            bottom: 3,
            child: Container(
              width: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFF3E9D2),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(1.5),
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFE5D5B8),
                    Color(0xFFF7EEDC),
                    Color(0xFFE2D0B0),
                    Color(0xFFF5EBD8),
                    Color(0xFFDCBFA0),
                  ],
                  stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                ),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.18),
                  width: 0.5,
                ),
              ),
            ),
          ),

          // Main Book Cover
          Positioned(
            left: 0,
            top: 0,
            width: coverWidth,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (book.coverPath.isNotEmpty)
                    Image.file(
                      File(book.coverPath),
                      fit: BoxFit.cover,
                      cacheWidth: (coverWidth * 3).round(),
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => GeneratedCover(book: book),
                    )
                  else
                    GeneratedCover(book: book),

                  // Real spine 3D curve: dark inner crease, light hinge highlight, outer gradient
                  // 1. Deep crease at the far left spine edge
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: coverWidth * 0.045,
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                  ),

                  // 2. Spine cylindrical volume shadow
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: coverWidth * 0.16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0.22),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 3. Book hinge groove (indented ridge on real books)
                  Positioned(
                    left: coverWidth * 0.14,
                    top: 0,
                    bottom: 0,
                    width: 1.2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0.22),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 4. Soft printed gloss / cloth texture sheen across the cover
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: coverWidth * 0.16),
                      child: SizedBox(
                        width: coverWidth * 0.25,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.16),
                                Colors.white.withValues(alpha: 0.04),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 5. Right cover edge highlight (mimicking edge bevel)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 0.9,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Reading progress hairline
                  if (book.hasStarted)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: book.progress.clamp(0.02, 1.0),
                        child: Container(
                          height: 2.4,
                          decoration: BoxDecoration(
                            color: AppColors.brass,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 2,
                                offset: const Offset(0, -0.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (book.isFavorite)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          size: 9.5,
                          color: AppColors.brass,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Typographic cover used when a book has no artwork.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.book});

  final Book book;

  static const List<List<Color>> _palettes = [
    [Color(0xFF3E5C4A), Color(0xFF22382C)],
    [Color(0xFF6E3B33), Color(0xFF3F1F1A)],
    [Color(0xFF31465F), Color(0xFF182532)],
    [Color(0xFF7A5A24), Color(0xFF493312)],
    [Color(0xFF5A3B64), Color(0xFF32203A)],
    [Color(0xFF2F5A5C), Color(0xFF173434)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[
      (book.title.hashCode & 0x7fffffff) % _palettes.length
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compact = height < 90;
        final titleLines = height < 70 ? 2 : (height < 110 ? 3 : 5);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(width * 0.09),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFF0E2C6).withValues(alpha: 0.32),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.16,
                  vertical: height * 0.10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title.toUpperCase(),
                      maxLines: titleLines,
                      overflow: TextOverflow.ellipsis,
                      style: serifStyle(
                        fontSize: (width * 0.115).clamp(8.0, 18.0),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF4E8D2),
                        height: 1.18,
                        letterSpacing: 0.4,
                      ),
                    ),
                    if (!compact) ...[
                      const Spacer(),
                      Container(
                        width: width * 0.22,
                        height: 1.2,
                        color: const Color(0xFFC9A66B).withValues(alpha: 0.8),
                      ),
                      SizedBox(height: height * 0.02),
                      Text(
                        book.author.isEmpty ? book.format.label : book.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: serifStyle(
                          fontSize: (width * 0.072).clamp(7.0, 11.0),
                          color:
                              const Color(0xFFE9D9BB).withValues(alpha: 0.85),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
