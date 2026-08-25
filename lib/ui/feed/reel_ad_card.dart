import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/theme/spine_palette.dart';
import '../../core/theme/spine_text.dart';
import '../widgets/spine_top_bar.dart';

/// A loaded native ad, full screen, in the reel format.
///
/// The ad's own content — media, headline, body, call to action, and the
/// advertiser attribution Google requires — is rendered by the platform
/// factory registered under `kReelAdFactoryId`, and arrives here as a single
/// [AdWidget]. Everything the ad network draws must be inside that view: the
/// SDK measures clicks against its own registered subviews, so a CTA built in
/// Flutter on top would look right and record nothing.
///
/// What this widget owns is the frame around it — the ground colour, the
/// masthead clearance, and the disclosure badge.
class ReelAdCard extends StatelessWidget {
  const ReelAdCard({super.key, required this.ad});

  /// Must already be loaded. [AdWidget] asserts on an ad that hasn't
  /// completed, and mounting the same ad object in two places throws — which
  /// is why `NativeAdPreloader` keys them by slot instead of pooling.
  final NativeAd ad;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.ground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The platform view fills the card; the factory's own layout decides
          // how the media is cropped within it.
          AdWidget(ad: ad),

          // Gradients over the top and bottom edges so the badge stays legible
          // against whatever creative the network serves, without dimming the
          // middle of the media.
          const IgnorePointer(child: _EdgeShade()),

          Positioned(
            top: MediaQuery.paddingOf(context).top + SpineTopBar.height + 8,
            left: 24,
            child: const IgnorePointer(child: SponsoredBadge()),
          ),
        ],
      ),
    );
  }
}

/// The disclosure marker.
///
/// Required, and deliberately not styled to disappear: an ad that reads as
/// editorial is both a policy breach and the fastest way to lose a reader's
/// trust in the rest of the feed.
class SponsoredBadge extends StatelessWidget {
  const SponsoredBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.brass.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'SPONSORED',
        style: SpineText.labelSmall.copyWith(
          color: palette.ground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EdgeShade extends StatelessWidget {
  const _EdgeShade();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.ground.withValues(alpha: 0.55),
            palette.ground.withValues(alpha: 0),
            palette.ground.withValues(alpha: 0),
            palette.ground.withValues(alpha: 0.35),
          ],
          stops: const [0, 0.22, 0.72, 1],
        ),
      ),
    );
  }
}
