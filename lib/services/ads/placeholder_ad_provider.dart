import 'package:flutter/foundation.dart';

import '../../data/models/feed_item.dart';
import 'ad_creative.dart';
import 'ad_provider.dart';

/// House/test creatives. No network, no SDK, no account required.
class PlaceholderAdProvider implements AdProvider {
  static const _creatives = <AdCreative>[
    AdCreative(
      id: 'test-001',
      sponsor: 'Test Sponsor',
      headline: 'Your message, in the house style',
      body:
          'Spine ad slots are full cards, set in the same type as the books. '
          'This one is a placeholder so the feed can be tested end to end.',
      ctaLabel: 'Learn more',
      isTest: true,
    ),
    AdCreative(
      id: 'test-002',
      sponsor: 'Test Sponsor',
      headline: 'One card. Then back to reading.',
      body:
          'Frequency is configured, never hard-coded — swipe past and the '
          'shelf picks up exactly where it left off.',
      ctaLabel: 'Learn more',
      isTest: true,
    ),
  ];

  @override
  Future<void> initialize() async {}

  @override
  AdCreative? creativeFor(AdFeedItem item) {
    if (_creatives.isEmpty) return null;
    return _creatives[(item.position - 1) % _creatives.length];
  }

  @override
  void recordImpression(AdCreative creative) {
    debugPrint('Spine ads: impression ${creative.id}');
  }

  @override
  void recordClick(AdCreative creative) {
    debugPrint('Spine ads: click ${creative.id}');
  }
}
