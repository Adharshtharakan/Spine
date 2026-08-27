import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/idea.dart';
import '../../services/reading/sentences.dart';
import '../widgets/tap_scale.dart';
import 'bookmark_ribbon.dart';

/// The idea itself: counter, heading, body.
///
/// Changing idea cross-fades and lifts slightly — the prototype's `ideaFade`.
class IdeaView extends StatelessWidget {
  const IdeaView({
    super.key,
    required this.idea,
    required this.index,
    required this.total,
    required this.saved,
    required this.onToggleSave,
    required this.highlights,
    required this.onToggleHighlight,
    required this.accent,
    this.compact = false,
    this.dense = false,
  });

  final Idea idea;
  final int index;
  final int total;

  /// Ideas are kept individually, not just whole books — the one line that
  /// struck you is usually smaller than the book it came from.
  final bool saved;
  final VoidCallback onToggleSave;

  /// Lines of this idea the reader has kept.
  final List<String> highlights;

  /// Long-pressing a sentence keeps or drops it.
  final ValueChanged<String> onToggleHighlight;

  /// The book's colour, used by the rule under the title.
  final Color accent;

  final bool compact;

  /// Set where the card carries a transport as well as the idea. Listen mode
  /// gives up roughly a fifth of the card to the scrubber and play control, and
  /// at Read's size the last line of the body is cut off — which reads worse
  /// than the empty space this sizing exists to remove.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // No transition of its own. PageTurn moves between ideas now, and a
    // cross-fade running inside the turning leaf put both ideas on screen at
    // once, flat, which read as no turn happening at all.
    return _IdeaText(
      key: ValueKey(idea.id),
      idea: idea,
      index: index,
      total: total,
      saved: saved,
      onToggleSave: onToggleSave,
      highlights: highlights,
      onToggleHighlight: onToggleHighlight,
      accent: accent,
      compact: compact,
      dense: dense,
    );
  }
}

class _IdeaText extends StatelessWidget {
  const _IdeaText({
    super.key,
    required this.idea,
    required this.index,
    required this.total,
    required this.saved,
    required this.onToggleSave,
    required this.highlights,
    required this.onToggleHighlight,
    required this.accent,
    required this.compact,
    required this.dense,
  });

  final Idea idea;
  final int index;
  final int total;
  final bool saved;
  final VoidCallback onToggleSave;
  final List<String> highlights;
  final ValueChanged<String> onToggleHighlight;
  final Color accent;
  final bool compact;
  final bool dense;

  /// The idea is the content of the card, so it should fill the room it has.
  ///
  /// Catalogue bodies run 87 to 154 characters — tight enough that this is
  /// really one size with a little give at the ends, rather than a layout that
  /// has to cope with anything. The old 15.5 left roughly a fifth of every card
  /// empty below the text, on every idea, because the surplus was constant.
  double get _bodySize {
    final base = switch (idea.body.length) {
      <= 110 => 18.5,
      <= 135 => 17.0,
      _ => 16.0,
    };
    return base - (compact ? 2.5 : 0) - (dense ? 3 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Scrolls only when the copy genuinely overflows — otherwise the vertical
    // drag belongs to the feed, not to this box.
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The counter lives on the bookmark now — printing it twice was
              // the same fact in two places.
              const Spacer(),
              // A real target, not a hairline glyph: this used to be an 18px
              // icon at 38% opacity, which readers could neither see nor hit.
              TapScale(
                onTap: onToggleSave,
                semanticLabel: saved ? 'Unsave this idea' : 'Save this idea',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: saved
                        ? palette.brass.withValues(alpha: 0.18)
                        : palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  // The caps label is decoration; the button's name comes from
                  // TapScale's semantics, and a Text child would otherwise
                  // swallow it.
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 15,
                          color: saved ? palette.brass : palette.onGround(0.65),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saved ? 'SAVED' : 'SAVE',
                          style: SpineText.labelSmall.copyWith(
                            color:
                                saved ? palette.brass : palette.onGround(0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact || dense ? 12 : 18),
          Text(
            idea.title,
            style: SpineText.ideaHeading.copyWith(
              fontSize: (compact ? 27 : 32) - (dense ? 5 : 0),
              height: 1.15,
            ),
          ),
          SizedBox(height: compact || dense ? 14 : 18),
          _Ornament(accent: accent),
          SizedBox(height: compact || dense ? 14 : 18),
          _Body(
            body: idea.body,
            highlights: highlights,
            onToggleHighlight: onToggleHighlight,
            fontSize: _bodySize,
          ),
        ],
      ),
    );
  }
}

/// The idea's prose, sentence by sentence, so a single line can be kept.
///
/// One [Text.rich] rather than a column of them: the sentences have to flow as
/// continuous paragraph text, and a widget per sentence would break the line
/// wrapping between them.
class _Body extends StatefulWidget {
  const _Body({
    required this.body,
    required this.highlights,
    required this.onToggleHighlight,
    required this.fontSize,
  });

  final String body;
  final List<String> highlights;
  final ValueChanged<String> onToggleHighlight;
  final double fontSize;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  /// One recogniser per sentence, kept across rebuilds and disposed with the
  /// card. Building them inline in the spans would leak one set per rebuild,
  /// and the body rebuilds on every highlight.
  final Map<String, LongPressGestureRecognizer> _recognisers = {};

  @override
  void dispose() {
    for (final recogniser in _recognisers.values) {
      recogniser.dispose();
    }
    super.dispose();
  }

  LongPressGestureRecognizer _recogniserFor(String sentence) {
    return _recognisers.putIfAbsent(
      sentence,
      () => LongPressGestureRecognizer()
        ..onLongPress = () => widget.onToggleHighlight(sentence),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sentences = Sentences.of(widget.body);
    final style = SpineText.ideaBody.copyWith(
      fontFamily: SpineText.serif,
      fontWeight: FontWeight.w400,
      fontSize: widget.fontSize,
      height: 1.55,
    );

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < sentences.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            _sentenceSpan(palette, sentences[i], style),
          ],
        ],
      ),
    );
  }

  TextSpan _sentenceSpan(
    SpinePalette palette,
    String sentence,
    TextStyle style,
  ) {
    final kept = widget.highlights.contains(sentence);

    return TextSpan(
      text: sentence,
      style: kept
          ? style.copyWith(
              color: palette.text,
              backgroundColor: palette.brass.withValues(alpha: 0.22),
            )
          : style,
      recognizer: _recogniserFor(sentence),
    );
  }
}

/// The rule between an idea's title and its body: a short line either side of
/// the same four-pointed star the bookmark uses. It is the one ornament in the
/// design, and it marks where the heading stops and the prose starts.
class _Ornament extends StatelessWidget {
  const _Ornament({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Container(
          width: 46,
          height: 1,
          color: accent.withValues(alpha: 0.5),
        );

    return Row(
      children: [
        rule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 11,
            height: 11,
            child: CustomPaint(painter: OrnamentStar(colour: accent)),
          ),
        ),
        rule(),
      ],
    );
  }
}
