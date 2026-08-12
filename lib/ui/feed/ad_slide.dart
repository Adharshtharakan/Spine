import 'package:flutter/material.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/feed_item.dart';
import '../../services/ads/ad_creative.dart';
import '../../services/ads/ad_provider.dart';
import '../widgets/spine_pill.dart';
import '../widgets/tap_scale.dart';

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SpinePill(
                label: creative.isTest ? 'Test ad' : 'Sponsored',
                foreground: SpineColors.brassDim,
                borderColor: SpineColors.line,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  creative.sponsor.toUpperCase(),
                  style: SpineText.labelSmall.copyWith(
                    color: SpineColors.parchmentDim,
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
            style: SpineText.ideaHeading.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 12),
          Text(creative.body, style: SpineText.ideaBody),
          const SizedBox(height: 20),
          TapScale(
            onTap: () => widget.provider.recordClick(creative),
            semanticLabel: creative.ctaLabel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: SpineColors.brassDim),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                creative.ctaLabel.toUpperCase(),
                style: SpineText.labelMedium.copyWith(
                  color: SpineColors.brass,
                ),
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.keyboard_arrow_up,
                size: 16,
                color: SpineColors.parchmentDim,
              ),
              const SizedBox(width: 6),
              Text(
                'SWIPE FOR THE NEXT BOOK',
                style: SpineText.labelSmall.copyWith(
                  color: SpineColors.parchmentDim,
                ),
              ),
            ],
          ),
        ],
      ),
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
        style: SpineText.label.copyWith(color: SpineColors.brassDim),
      ),
    );
  }
}
