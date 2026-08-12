import '../../data/models/feed_item.dart';
import 'ad_creative.dart';

/// Where ad content comes from.
///
/// The MVP ships `PlaceholderAdProvider` so the feed can be tested with no
/// advertising account. A Google Mobile Ads implementation slots in here:
/// `initialize()` becomes `MobileAds.instance.initialize()`, `creativeFor`
/// returns a loaded native ad, and the impression/click hooks forward to the
/// SDK. Nothing in the feed changes.
abstract interface class AdProvider {
  Future<void> initialize();

  /// The creative for a given slot, or null if nothing is available — in which
  /// case the feed shows a quiet, unobtrusive card rather than a gap.
  AdCreative? creativeFor(AdFeedItem item);

  void recordImpression(AdCreative creative);

  void recordClick(AdCreative creative);
}
