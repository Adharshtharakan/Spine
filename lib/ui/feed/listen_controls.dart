import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../services/audio/playback_snapshot.dart';
import '../sharing/story_share_button.dart';
import '../widgets/tap_scale.dart';

/// Transport for Listen mode.
///
/// The play control is the centre of gravity: a large thin ring, the way a
/// player looks when it isn't pretending to be a toolbar. Time sits under the
/// scrubber, share sits opposite it at the edge.
class ListenControls extends StatelessWidget {
  const ListenControls({
    super.key,
    required this.accent,
    required this.snapshot,
    required this.onTogglePlay,
    required this.onSeekFraction,
    required this.onShare,
    this.compact = false,
  });

  final Color accent;
  final PlaybackSnapshot snapshot;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeekFraction;

  /// Opens the story-share sheet for the idea on screen.
  final VoidCallback onShare;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Scrubber(
          fraction: snapshot.fraction,
          accent: accent,
          onSeek: onSeekFraction,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Text(
                      _clock(snapshot.position),
                      style: SpineText.label.copyWith(
                        color: SpineColors.onInk(0.62),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (snapshot.isSimulated)
                      Text(
                        'PREVIEW',
                        style: SpineText.labelSmall.copyWith(
                          color: SpineColors.brassDim,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Text(
              _clock(snapshot.duration),
              style: SpineText.label.copyWith(color: SpineColors.onInk(0.34)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: SizedBox.shrink()),
            _PlayButton(accent: accent, snapshot: snapshot, onTap: onTogglePlay),
            // Mirrors where Read mode puts it, so switching modes doesn't
            // move the control out from under the reader's thumb.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: StoryShareButton(onTap: onShare, compact: compact),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _clock(Duration value) {
    final total = value.inSeconds;
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.fraction,
    required this.accent,
    required this.onSeek,
  });

  final double fraction;
  final Color accent;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekTo(double dx) =>
            onSeek((dx / constraints.maxWidth).clamp(0.0, 1.0));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition.dx),
          child: Padding(
            // The line is too thin to hit; the padding gives it a real target
            // without changing how it looks.
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 4,
                child: ColoredBox(
                  color: SpineColors.surface,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(color: accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.accent,
    required this.snapshot,
    required this.onTap,
  });

  final Color accent;
  final PlaybackSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      scale: 0.93,
      semanticLabel: snapshot.isPlaying ? 'Pause' : 'Play',
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withValues(alpha: 0.14),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
        ),
        child: snapshot.isLoading
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              )
            : Icon(
                snapshot.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 30,
                color: SpineColors.parchment,
              ),
      ),
    );
  }
}
