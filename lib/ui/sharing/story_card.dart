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

  static const bookmarkAsset = 'assets/story/bookmark.png';

  /// Decodes the card's images before anything tries to photograph it.
  ///
  /// [StoryCardRenderer] captures after a couple of frames, but a multi-megabyte
  /// background takes far longer than that to decode off the asset bundle, and
  /// a widget mid-decode paints nothing. The result was a card exported without
  /// its background — but only until the [ImageCache] happened to be warm, so
  /// it looked like a bug that "fixed itself" after a few shares.
  ///
  /// Failures are swallowed: a missing background should still export a card
  /// with the idea on it, which is the part worth sharing.
  static Future<void> precacheAssets(
    BuildContext context,
    StoryTemplate template,
  ) async {
    await Future.wait([
      for (final asset in [template.backgroundAsset, bookmarkAsset])
        precacheImage(AssetImage(asset), context).catchError(
          (Object error) => debugPrint('Spine: story asset $asset — $error'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final split = SplitTitle.of(idea.title);

    // Halo behind the title, in the opposite polarity to the text itself.
    // The background is a photograph, so a word can land on anything; this is
    // what keeps a dark title readable over shadow and a light one over sky.
    final halo = <Shadow>[
      Shadow(
        color: template.lightText
            ? Colors.black.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.7),
        blurRadius: 28,
      ),
    ];

    // The subtitles are gold and white on every template, so they always want
    // to be lifted off the photo the same way.
    final lift = <Shadow>[
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 18),
    ];

    return SizedBox.fromSize(
      size: size,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Background(template: template),
            _Scrim(template: template),
            Positioned(
              top: 108,
              left: 0,
              right: 0,
              child: _Wordmark(template: template),
            ),
            // Flush with the top edge: the ribbon hangs into the page from
            // above it, the way a bookmark actually sits in a book. Inset
            // from the right to the same 96 margin the text uses.
            const Positioned(top: 0, right: 96, child: _BookmarkGlyph()),
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
                              fontWeight: FontWeight.w800,
                              fontSize: 98,
                              height: 1.12,
                              letterSpacing: -1,
                              color: template.mainTitleColor,
                              shadows: halo,
                            ),
                          ),
                          TextSpan(
                            text: split.dot,
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontWeight: FontWeight.w800,
                              fontSize: 98,
                              height: 1.12,
                              color: template.terminalDotColor,
                              shadows: halo,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 56),
                    // Scaled down to fit rather than ellipsised: a truncated
                    // book title reads as a broken image once it's on
                    // someone's story, and titles run to 39 characters.
                    _Subtitle(
                      text: book.title.toUpperCase(),
                      size: 38,
                      weight: FontWeight.w700,
                      spacing: 4,
                      colour: template.bookTitleColor,
                      shadows: lift,
                    ),
                    const SizedBox(height: 18),
                    _Subtitle(
                      text: book.author.toUpperCase(),
                      size: 29,
                      weight: FontWeight.w600,
                      spacing: 2.5,
                      colour: template.authorColor,
                      shadows: lift,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 128,
              child: _Footer(template: template),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single line of secondary type, shrunk to fit rather than clipped.
///
/// [FittedBox] only scales down, so short titles keep the full size and only
/// the long ones give way — which is the behaviour you want when the output
/// is an image someone posts rather than a screen they can scroll.
class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.text,
    required this.size,
    required this.weight,
    required this.spacing,
    required this.colour,
    required this.shadows,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final double spacing;
  final Color colour;
  final List<Shadow> shadows;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: 'IBMPlexMono',
          fontWeight: weight,
          fontSize: size,
          letterSpacing: spacing,
          color: colour,
          shadows: shadows,
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

/// Grounds the bottom of the card so the footer sits on a readable field
/// rather than on whatever the photograph happens to be doing down there.
///
/// Only the bottom is veiled: both the wordmark and the bookmark live at the
/// top, and the bookmark's art is a solid dark ribbon that needs the
/// background left bright behind it to read as a silhouette.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.template});

  final StoryTemplate template;

  @override
  Widget build(BuildContext context) {
    final veil = template.lightText ? Colors.black : SpineColors.parchment;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            veil.withValues(alpha: template.lightText ? 0.72 : 0.8),
            veil.withValues(alpha: 0),
          ],
          stops: const [0, 0.38],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.template});

  final StoryTemplate template;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'S P I N E',
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w500,
          fontSize: 30,
          letterSpacing: 6,
          color: template.lightText ? Colors.white : SpineColors.ink,
          shadows: [
            Shadow(
              color: template.lightText
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.65),
              blurRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkGlyph extends StatelessWidget {
  const _BookmarkGlyph();

  static const _width = 65.0;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      StoryCard.bookmarkAsset,
      // Sized to the ribbon's own 1:2.99 proportions. The asset is trimmed
      // to its opaque bounds — any transparent margin left in the file gets
      // fitted along with the art and shrinks the visible ribbon.
      width: _width,
      height: _width * 2.99,
      fit: BoxFit.contain,
      // See `tool/generate_story_templates.py` — a real bookmark.png ships,
      // so this is a defensive fallback rather than the primary path.
      errorBuilder: (context, error, stack) => const CustomPaint(
        size: Size(_width, _width * 2.99),
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
  const _Footer({required this.template});

  final StoryTemplate template;

  @override
  Widget build(BuildContext context) {
    // Sits on the scrim, so it takes its polarity from the same place the
    // scrim does rather than assuming a dark card.
    final colour = template.lightText
        ? Colors.white.withValues(alpha: 0.78)
        : SpineColors.ink.withValues(alpha: 0.72);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_stories_outlined, size: 30, color: colour),
        const SizedBox(height: 12),
        Text(
          'BOOKS, DISTILLED.\nIDEAS, RETAINED.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'IBMPlexMono',
            fontWeight: FontWeight.w500,
            fontSize: 15,
            letterSpacing: 1.6,
            height: 1.5,
            color: colour,
          ),
        ),
      ],
    );
  }
}
