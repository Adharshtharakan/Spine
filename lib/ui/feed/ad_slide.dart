import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/feed_item.dart';
import '../../services/ads/ad_creative.dart';
import '../../services/ads/ad_provider.dart';
import '../widgets/spine_pill.dart';
import '../widgets/spine_top_bar.dart';
import '../widgets/tap_scale.dart';
import 'ambient_backdrop.dart';

/// A sponsored card between books.
///
/// Set in the same type as the rest of Spine, always labelled, and never
/// blocking: one swipe and the shelf continues. The creative arrives from
/// `AdProvider`, so replacing the placeholder with AdMob doesn't touch this
/// widget's place in the feed.
class AdSlide extends StatefulWidget {
  const AdSlide({
    super.key,
    required this.item,
    required this.provider,
    required this.isActive,
  });

  final AdFeedItem item;
  final AdProvider provider;
  final bool isActive;

  @override
  State<AdSlide> createState() => _AdSlideState();
}

class _AdSlideState extends State<AdSlide> {
  AdCreative? _creative;
  bool _impressionRecorded = false;

  @override
  void initState() {
    super.initState();
    _creative = widget.provider.creativeFor(widget.item);
    _maybeRecordImpression();
  }

  @override
  void didUpdateWidget(AdSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRecordImpression();
  }

  /// An impression counts when the card is the one on screen — not when the
  /// feed happens to have built it as a neighbour.
  void _maybeRecordImpression() {
    final creative = _creative;
    if (creative == null || _impressionRecorded || !widget.isActive) return;
    _impressionRecorded = true;
    widget.provider.recordImpression(creative);
  }

  @override
  Widget build(BuildContext context) {
    final creative = _creative;
    if (creative == null) return const _EmptyAdCard();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Ads get the house neutral rather than a book's colour, so the feed
        // reads the interruption before the copy does.
        const AmbientBackdrop(color: SpineColors.brassDim, intensity: 0.55),
        Padding(
          // Clears the floating masthead, exactly as a book card does.
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top + SpineTopBar.height + 16,
            24,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SpinePill(
                    label: creative.isTest ? 'Test ad' : 'Sponsored',
                    foreground: SpineColors.brass,
                    background: SpineColors.brass.withValues(alpha: 0.14),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      creative.sponsor.toUpperCase(),
                      style: SpineText.labelSmall.copyWith(
                        color: SpineColors.onInk(0.4),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                creative.headline,
                style: SpineText.bookTitle.copyWith(fontSize: 30),
              ),
              const SizedBox(height: 16),
              Text(creative.body, style: SpineText.ideaBody),
              const SizedBox(height: 26),
              Align(
                alignment: Alignment.centerLeft,
                child: TapScale(
                  onTap: () => widget.provider.recordClick(creative),
                  semanticLabel: creative.ctaLabel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: SpineColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      creative.ctaLabel.toUpperCase(),
                      style: SpineText.labelMedium.copyWith(
                        color: SpineColors.parchment,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: SpineColors.onInk(0.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SWIPE FOR THE NEXT BOOK',
                      style: SpineText.labelSmall.copyWith(
                        color: SpineColors.onInk(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyAdCard extends StatelessWidget {
  const _EmptyAdCard();

  @override
  Widget build(BuildContext context) {
    // No inventory: a quiet interstitial rather than a hole in the feed.
    return Center(
      child: Text(
        'SPINE',
        style: SpineText.wordmark.copyWith(
          fontSize: 15,
          color: SpineColors.onInk(0.25),
        ),
      ),
    );
  }
}
