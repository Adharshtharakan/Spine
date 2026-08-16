import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../data/models/book.dart';
import '../../data/models/idea.dart';
import '../../data/models/story_template.dart';
import '../../services/sharing/story_typography.dart';

/// The rendered Story: one idea, its book, and Spine's own mark — laid out at
/// exact export size so `StoryCardRenderer` can capture it pixel for pixel.
///
/// This widget is never shown on screen. It's mounted off-screen purely to be
/// painted into an image — see `StoryCardRenderer`.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.idea,
    required this.book,
    required this.template,
  });

  final Idea idea;
  final Book book;
  final StoryTemplate template;

  /// Instagram/Facebook Stories are 1080x1920 (9:16) — the export pipeline
  /// captures at pixelRatio 1 against this exact logical size, so this
  /// constant *is* the output resolution, not just a layout hint.
  static const size = Size(1080, 1920);

  @override
  Widget build(BuildContext context) {
    final split = SplitTitle.of(idea.title);

    return SizedBox.fromSize(
      size: size,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Background(template: template),
            const Positioned(top: 108, left: 0, right: 0, child: _Wordmark()),
            const Positioned(top: 96, right: 88, child: _BookmarkGlyph()),
            Positioned(
              left: 96,
              right: 96,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: split.body,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w600,
                              fontSize: 64,
                              height: 1.18,
                              letterSpacing: -1,
                              color: template.mainTitleColor,
                            ),
                          ),
                          TextSpan(
                            text: split.dot,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w600,
                              fontSize: 64,
                              height: 1.18,
                              color: template.terminalDotColor,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 52),
                    Text(
                      book.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                        letterSpacing: 3,
                        color: template.bookTitleColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      book.author.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontWeight: FontWeight.w500,
                        fontSize: 19,
                        letterSpacing: 2,
                        color: template.authorColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 128, child: _Footer()),
          ],
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.template});

  final StoryTemplate template;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      template.backgroundAsset,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // Defensive only: `tool/generate_story_templates.py` ships a real file
      // for every template, so this path shouldn't run in practice.
      errorBuilder: (context, error, stack) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [template.mainTitleColor.withValues(alpha: 0.4), SpineColors.ink],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'S P I N E',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w500,
          fontSize: 30,
          letterSpacing: 6,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BookmarkGlyph extends StatelessWidget {
  const _BookmarkGlyph();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/story/bookmark.png',
      width: 70,
      height: 160,
      // See `tool/generate_story_templates.py` — a real bookmark.png ships,
      // so this is a defensive fallback rather than the primary path.
      errorBuilder: (context, error, stack) => const CustomPaint(
        size: Size(70, 160),
        painter: _RibbonPainter(color: Color(0xFFD0A13B)),
      ),
    );
  }
}

/// Vector fallback for the bookmark glyph — a body with a notch cut from its
/// bottom, matching the shape `generate_story_templates.py` rasterises.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bodyBottom = size.height * 0.82;
    final notch = size.height * 0.16;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bodyBottom)
      ..lineTo(size.width / 2, bodyBottom - notch)
      ..lineTo(0, bodyBottom)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_stories_outlined, size: 30, color: Colors.white70),
        SizedBox(height: 12),
        Text(
          'BOOKS, DISTILLED.\nIDEAS, RETAINED.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'IBMPlexMono',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            letterSpacing: 1.6,
            height: 1.5,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
