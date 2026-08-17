import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/ad_config.dart';

/// The reel ad factory registered on both platforms. Must match the string
/// passed to `registerNativeAdFactory` in MainActivity.kt and AppDelegate.swift
/// — a mismatch fails at load time with "factory not found", not at compile
/// time, so the constant lives here and both sides quote it.
const String kReelAdFactoryId = 'reelAd';

/// Owns every [NativeAd] the feed is holding: loads them ahead of the reader,
/// hands them out, and disposes them.
///
/// A native ad takes a network round trip and a native layout inflation to
/// become renderable. Loading one when its card scrolls into view guarantees
/// the reader sees an empty slot first, so slots are filled while they are
/// still several swipes away.
///
/// Ads are keyed by their slot position rather than pooled, because an ad is
/// only allowed to be in one place: [AdWidget] throws if the same ad object is
/// mounted twice, and reusing one across slots would also double-count
/// impressions.
class NativeAdPreloader with ChangeNotifier {
  NativeAdPreloader({required this.config, this.maxCached = 3});

  final AdConfig config;

  /// How many loaded ads to hold at once. Native ads are heavyweight — each
  /// one retains a platform view and its media — so the cache is deliberately
  /// small and evicts the slots furthest from the reader.
  final int maxCached;

  final Map<int, NativeAd> _ready = {};
  final Map<int, Future<void>> _inFlight = {};
  final Set<int> _failed = {};

  int _lastFocusedPosition = 0;
  bool _disposed = false;

  /// The ad for a slot, or null when nothing has loaded yet — in which case
  /// the card shows Spine's own filler rather than a blank.
  NativeAd? adFor(int position) => _ready[position];

  bool hasFailed(int position) => _failed.contains(position);

  /// Warms [positions], newest request wins the cache.
  ///
  /// Call this with the slots around the reader, not just the next one: a fast
  /// scroller can cross two ad slots before the first request returns.
  void preload(Iterable<int> positions, {int? focused}) {
    if (_disposed || !config.enabled || !AdConfig.supportsAds) return;
    if (focused != null) _lastFocusedPosition = focused;

    for (final position in positions) {
      if (_ready.containsKey(position) ||
          _inFlight.containsKey(position) ||
          _failed.contains(position)) {
        continue;
      }
      _inFlight[position] = _load(position);
    }

    _evictFurthest();
  }

  Future<void> _load(int position) {
    final completer = Completer<void>();

    final ad = NativeAd(
      adUnitId: config.nativeUnitId,
      factoryId: kReelAdFactoryId,
      request: const AdRequest(),
      // Full-screen slot, so the media is the point — ask for the largest
      // aspect the network has rather than letting it pick a banner-ish crop.
      nativeAdOptions: NativeAdOptions(
        mediaAspectRatio: MediaAspectRatio.portrait,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (_disposed) {
            ad.dispose();
            return;
          }
          _ready[position] = ad as NativeAd;
          _inFlight.remove(position);
          if (!completer.isCompleted) completer.complete();
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _inFlight.remove(position);
          // Remembered so a no-fill slot doesn't retry on every rebuild and
          // burn requests; a new session gets a fresh attempt.
          _failed.add(position);
          debugPrint('Spine ads: slot $position failed — ${error.message}');
          if (!completer.isCompleted) completer.complete();
          if (!_disposed) notifyListeners();
        },
      ),
    );

    unawaited(ad.load());
    return completer.future;
  }

  /// Drops whichever loaded ads sit furthest from where the reader is.
  ///
  /// Distance rather than insertion order: scrolling back up should not evict
  /// the ad directly above the reader in favour of one twenty cards below.
  void _evictFurthest() {
    if (_ready.length <= maxCached) return;

    final byDistance = _ready.keys.toList()
      ..sort((a, b) {
        final da = (a - _lastFocusedPosition).abs();
        final db = (b - _lastFocusedPosition).abs();
        return da.compareTo(db);
      });

    for (final position in byDistance.skip(maxCached)) {
      _ready.remove(position)?.dispose();
    }
  }

  /// Releases a single slot — used when a card leaves the tree for good.
  void release(int position) {
    _ready.remove(position)?.dispose();
    _failed.remove(position);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final ad in _ready.values) {
      ad.dispose();
    }
    _ready.clear();
    _inFlight.clear();
    super.dispose();
  }
}
