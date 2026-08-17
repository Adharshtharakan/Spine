import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/ad_config.dart';
import '../../data/models/feed_item.dart';
import 'ad_creative.dart';
import 'ad_provider.dart';
import 'placeholder_ad_provider.dart';

/// Google Mobile Ads, with Spine's own card as the fallback.
///
/// The native ad itself is handled by `NativeAdPreloader` — the ad object has
/// to outlive any one card, so it can't be owned by a per-slot lookup. What
/// this class does is initialise the SDK and answer the question the feed
/// already knew how to ask: what should this slot show if there's no ad?
///
/// AdMob does not always fill. Rather than leave a hole in a full-screen feed,
/// an unfilled slot falls through to the house creative, which is the same
/// card the app shipped with before any network was wired up.
class AdMobAdProvider implements AdProvider {
  AdMobAdProvider({required this.config, AdProvider? fallback})
    : _fallback = fallback ?? PlaceholderAdProvider();

  final AdConfig config;
  final AdProvider _fallback;

  bool _initialised = false;
  bool get isInitialised => _initialised;

  @override
  Future<void> initialize() async {
    if (_initialised || !config.enabled || !AdConfig.supportsAds) return;

    await MobileAds.instance.initialize();

    // Test devices see test creatives from *live* unit ids too, which is how
    // you verify a real placement without risking an invalid-traffic flag.
    if (config.useTestUnits) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: const []),
      );
    }

    _initialised = true;
    debugPrint(
      'Spine ads: AdMob ready '
      '(${config.useTestUnits ? "test units" : "live units"})',
    );
  }

  @override
  AdCreative? creativeFor(AdFeedItem item) => _fallback.creativeFor(item);

  @override
  void recordImpression(AdCreative creative) =>
      _fallback.recordImpression(creative);

  @override
  void recordClick(AdCreative creative) => _fallback.recordClick(creative);
}
