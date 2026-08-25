import 'package:flutter/material.dart';


/// Spine's three typefaces, mirroring the prototype:
///   Fraunces  — titles and idea headings (editorial serif)
///   Inter     — body copy
///   IBM Plex  — labels, metadata, chips (the "library card" voice)
abstract final class SpineText {
  // These carry weight, size, spacing and family — never colour. Spine has two
  // modes, and a colour baked into a const style cannot follow the one being
  // read. Colour arrives from the theme's textTheme, or from the call site
  // where it needs to differ.

  static const serif = 'Fraunces';
  static const sans = 'Inter';
  static const mono = 'IBMPlexMono';

  // ---- Display / editorial -------------------------------------------------

  /// Book title. The largest thing on the screen by a wide margin — the type
  /// carries the card, so nothing else has to shout.
  static const bookTitle = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 38,
    height: 1.04,
    letterSpacing: -0.8,
  );

  /// The "Spine" wordmark — set wide, the way a masthead is.
  static const wordmark = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w500,
    fontSize: 19,
    letterSpacing: 3.4,
  );

  /// Idea heading.
  static const ideaHeading = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 25,
    height: 1.18,
    letterSpacing: -0.3,
  );

  /// Section heading on the secondary tabs.
  static const sectionTitle = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 17,
  );

  // ---- Body ----------------------------------------------------------------

  /// Idea body copy.
  static const ideaBody = TextStyle(
    fontFamily: sans,
    fontSize: 15.5,
    height: 1.62,
    letterSpacing: 0.05,
  );

  static const author = TextStyle(
    fontFamily: sans,
    fontWeight: FontWeight.w400,
    fontSize: 14.5,
  );

  static const secondary = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 1.5,
  );

  // ---- Mono labels ---------------------------------------------------------

  /// Chips, tab labels, counters. Always rendered in caps by the widgets, and
  /// tracked wide — at this size the letterspacing is what makes it read as a
  /// library card rather than as small text.
  static const label = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 1.4,
  );

  static const labelSmall = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 9,
    letterSpacing: 1.2,
  );

  static const labelMedium = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    letterSpacing: 1.3,
  );

  static const meta = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    letterSpacing: 0.5,
  );
}
