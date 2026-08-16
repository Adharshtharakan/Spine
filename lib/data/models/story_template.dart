import 'package:flutter/material.dart';

/// One of the visual treatments a story card can use.
///
/// Background art lives in `assets/story/`; the colours here are chosen to
/// stay legible against that specific background, which is why a template
/// bundles both rather than letting them vary independently. Six ship —
/// see `tool/generate_story_templates.py` for how the placeholder art was
/// made, and its docstring for how to replace it with final designs.
class StoryTemplate {
  const StoryTemplate({
    required this.id,
    required this.backgroundAsset,
    required this.mainTitleColor,
    required this.terminalDotColor,
    required this.bookTitleColor,
    required this.authorColor,
  });

  final int id;
  final String backgroundAsset;

  /// Colour of the idea title, apart from its terminal period.
  final Color mainTitleColor;

  /// Colour of the terminal period on the idea title — always the brand gold,
  /// kept as a per-template field rather than a constant so a future template
  /// with a different accent isn't forced to use brass.
  final Color terminalDotColor;

  final Color bookTitleColor;
  final Color authorColor;
}

abstract final class StoryTemplates {
  static const _gold = Color(0xFFD0A13B);
  static const _white = Colors.white;

  static const all = <StoryTemplate>[
    StoryTemplate(
      id: 1,
      backgroundAsset: 'assets/story/image1.png',
      mainTitleColor: Color(0xFF134071),
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
    StoryTemplate(
      id: 2,
      backgroundAsset: 'assets/story/image2.png',
      mainTitleColor: Color(0xFF152D12),
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
    StoryTemplate(
      id: 3,
      backgroundAsset: 'assets/story/image3.png',
      mainTitleColor: Color(0xFF02182E),
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
    StoryTemplate(
      id: 4,
      backgroundAsset: 'assets/story/image4.png',
      mainTitleColor: _white,
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
    StoryTemplate(
      id: 5,
      backgroundAsset: 'assets/story/image5.png',
      mainTitleColor: _white,
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
    StoryTemplate(
      id: 6,
      backgroundAsset: 'assets/story/image6.png',
      mainTitleColor: _white,
      terminalDotColor: _gold,
      bookTitleColor: _gold,
      authorColor: _white,
    ),
  ];

  /// Picks a template deterministically from an idea's id, so resharing the
  /// same idea — or two readers sharing it independently — always produces
  /// the same card rather than a random one each time.
  static StoryTemplate forIdea(String ideaId) => all[_hash(ideaId) % all.length];

  /// FNV-1a — small, stable across platforms and releases, matching the hash
  /// `DailyPicker` already uses for the same reason.
  static int _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
