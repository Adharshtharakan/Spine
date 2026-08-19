import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/idea.dart';
import '../../services/reading/sentences.dart';
import '../widgets/tap_scale.dart';

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
    this.compact = false,
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

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: _IdeaText(
        key: ValueKey(idea.id),
        idea: idea,
        index: index,
        total: total,
        saved: saved,
        onToggleSave: onToggleSave,
        highlights: highlights,
        onToggleHighlight: onToggleHighlight,
        compact: compact,
      ),
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
    required this.compact,
  });

  final Idea idea;
  final int index;
  final int total;
  final bool saved;
  final VoidCallback onToggleSave;
  final List<String> highlights;
  final ValueChanged<String> onToggleHighlight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: Text(
                  'IDEA ${index + 1} OF $total',
                  style: SpineText.label.copyWith(
                    color: SpineColors.onInk(0.4),
                  ),
                ),
              ),
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
                        ? SpineColors.brass.withValues(alpha: 0.18)
                        : SpineColors.surfaceRaised,
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
                          color: saved
                              ? SpineColors.brass
                              : SpineColors.onInk(0.65),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saved ? 'SAVED' : 'SAVE',
                          style: SpineText.labelSmall.copyWith(
                            color: saved
                                ? SpineColors.brass
                                : SpineColors.onInk(0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 14),
          Text(
            idea.title,
            style: SpineText.ideaHeading.copyWith(fontSize: compact ? 22 : 25),
          ),
          SizedBox(height: compact ? 12 : 16),
          _Body(
            body: idea.body,
            highlights: highlights,
            onToggleHighlight: onToggleHighlight,
            compact: compact,
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
    required this.compact,
  });

  final String body;
  final List<String> highlights;
  final ValueChanged<String> onToggleHighlight;
  final bool compact;

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
    final sentences = Sentences.of(widget.body);
    final style = SpineText.ideaBody.copyWith(
      fontSize: widget.compact ? 14.5 : 15.5,
    );

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < sentences.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            _sentenceSpan(sentences[i], style),
          ],
        ],
      ),
    );
  }

  TextSpan _sentenceSpan(String sentence, TextStyle style) {
    final kept = widget.highlights.contains(sentence);

    return TextSpan(
      text: sentence,
      style: kept
          ? style.copyWith(
              color: SpineColors.parchment,
              backgroundColor: SpineColors.brass.withValues(alpha: 0.22),
            )
          : style,
      recognizer: _recogniserFor(sentence),
    );
  }
}
