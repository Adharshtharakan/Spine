import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../services/audio/playback_snapshot.dart';
import '../widgets/tap_scale.dart';

/// Transport for Listen mode: scrubber, elapsed time, play/pause, share.
class ListenControls extends StatelessWidget {
  const ListenControls({
    super.key,
    required this.accent,
    required this.snapshot,
    required this.onTogglePlay,
    required this.onSeekFraction,
    required this.shareText,
  });

  final Color accent;
  final PlaybackSnapshot snapshot;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeekFraction;
  final String shareText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
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
              // Scales down rather than wrapping or clipping: on a narrow
              // phone with large system type this line must still read.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        '${_clock(snapshot.position)} / ${_clock(snapshot.duration)}',
                        style: SpineText.label.copyWith(
                          color: SpineColors.parchmentDim,
                        ),
                      ),
                      if (snapshot.isSimulated) ...[
                        const SizedBox(width: 8),
                        Text(
                          'PREVIEW',
                          style: SpineText.labelSmall.copyWith(
                            color: SpineColors.brassDim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _PlayButton(
                accent: accent,
                snapshot: snapshot,
                onTap: onTogglePlay,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TapScale(
                    semanticLabel: 'Share this idea',
                    onTap: () => _share(context),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.ios_share,
                        size: 17,
                        color: SpineColors.parchmentDim,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpineColors.inkCard,
          content: Text(
            'Copied to clipboard',
            style: SpineText.label.copyWith(color: SpineColors.parchment),
          ),
        ),
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
            // A 3px line is too thin to hit; the padding gives it a real target
            // without changing how it looks.
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 3,
                child: ColoredBox(
                  color: SpineColors.line,
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
      semanticLabel: snapshot.isPlaying ? 'Pause' : 'Play',
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        child: snapshot.isLoading
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(SpineColors.ink),
                ),
              )
            : Icon(
                snapshot.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 20,
                color: SpineColors.ink,
              ),
      ),
    );
  }
}
