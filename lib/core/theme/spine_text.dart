import 'package:flutter/material.dart';

import 'spine_colors.dart';

/// Spine's three typefaces, mirroring the prototype:
///   Fraunces  — titles and idea headings (editorial serif)
///   Inter     — body copy
///   IBM Plex  — labels, metadata, chips (the "library card" voice)
abstract final class SpineText {
  static const serif = 'Fraunces';
  static const sans = 'Inter';
  static const mono = 'IBMPlexMono';

  // ---- Display / editorial -------------------------------------------------

  /// Book title on the cover panel.
  static const bookTitle = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    height: 1.15,
    letterSpacing: -0.2,
  );

  /// The "Spine" wordmark.
  static const wordmark = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    letterSpacing: 0.2,
    color: SpineColors.parchment,
  );

  /// Idea heading.
  static const ideaHeading = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 19,
    height: 1.2,
    color: SpineColors.parchment,
  );

  /// Section heading on the secondary tabs.
  static const sectionTitle = TextStyle(
    fontFamily: serif,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    color: SpineColors.parchment,
  );

  // ---- Body ----------------------------------------------------------------

  /// Idea body copy.
  static final ideaBody = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    height: 1.55,
    color: SpineColors.onInk(0.82),
  );

  static const author = TextStyle(
    fontFamily: sans,
    fontWeight: FontWeight.w500,
    fontSize: 13,
  );

  static final secondary = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    height: 1.5,
    color: SpineColors.onInk(0.7),
  );

  // ---- Mono labels ---------------------------------------------------------

  /// Chips, tab labels, counters. Always rendered in caps by the widgets.
  static const label = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 0.6,
  );

  static const labelSmall = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 9,
    letterSpacing: 0.5,
  );

  static const labelMedium = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    letterSpacing: 0.6,
  );

  static const meta = TextStyle(
    fontFamily: mono,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    letterSpacing: 0.5,
  );
}
