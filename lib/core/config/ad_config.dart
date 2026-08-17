import 'dart:io';

/// How often an ad card is woven into the feed.
///
/// The feed itself knows nothing about frequency — it renders whatever
/// `FeedComposer` produces. Changing the cadence (or switching ads off) is a
/// config change, never a feed-architecture change.
class AdConfig {
  const AdConfig({
    this.enabled = true,
    this.frequency = 6,
    this.leadIn = 5,
    this.maxAdsPerSession,
    this.androidNativeUnitId = testNativeUnitIdAndroid,
    this.iosNativeUnitId = testNativeUnitIdIos,
    this.useTestUnits = true,
  }) : assert(frequency > 0, 'frequency must be at least 1');

  /// Google's own always-fills test units. Real inventory needs a real unit id
  /// *and* `useTestUnits: false` — see README, "Ads".
  ///
  /// Serving live ads from a development build is a policy violation that gets
  /// AdMob accounts suspended, which is why the default here is the test unit
  /// rather than a blank string waiting to be filled in.
  static const testNativeUnitIdAndroid =
      'ca-app-pub-3940256099942544/2247696110';
  static const testNativeUnitIdIos = 'ca-app-pub-3940256099942544/3986624511';

  /// Master switch. `false` produces a feed of pure books.
  final bool enabled;

  /// Insert an ad after every N books.
  ///   frequency 3 → Book Book Book Ad Book Book Book Ad
  final int frequency;

  /// Books the reader sees before the first ad is allowed. Keeping this at or
  /// above `frequency` means a session never opens on an ad — the reading
  /// experience earns the first impression.
  final int leadIn;

  /// Optional ceiling on ads per composed feed. `null` = no ceiling.
  final int? maxAdsPerSession;

  final String androidNativeUnitId;
  final String iosNativeUnitId;

  /// Whether the ids above are Google's test units. Kept explicit rather than
  /// inferred from `kDebugMode`: a release build pointed at a staging unit is
  /// a legitimate thing to want, and guessing would hide it.
  final bool useTestUnits;

  /// The unit for the platform actually running. Throws on desktop and web
  /// rather than returning a plausible-looking wrong id — nothing should be
  /// requesting ads there, and a silent fallback would hide the mistake.
  String get nativeUnitId {
    if (Platform.isAndroid) return androidNativeUnitId;
    if (Platform.isIOS) return iosNativeUnitId;
    throw UnsupportedError('Spine serves ads on Android and iOS only.');
  }

  static bool get supportsAds => Platform.isAndroid || Platform.isIOS;

  AdConfig copyWith({
    bool? enabled,
    int? frequency,
    int? leadIn,
    int? maxAdsPerSession,
    String? androidNativeUnitId,
    String? iosNativeUnitId,
    bool? useTestUnits,
  }) {
    return AdConfig(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      leadIn: leadIn ?? this.leadIn,
      maxAdsPerSession: maxAdsPerSession ?? this.maxAdsPerSession,
      androidNativeUnitId: androidNativeUnitId ?? this.androidNativeUnitId,
      iosNativeUnitId: iosNativeUnitId ?? this.iosNativeUnitId,
      useTestUnits: useTestUnits ?? this.useTestUnits,
    );
  }

  static AdConfig fromEnvironment() {
    // Defining a real unit id is what opts a build into live inventory; there
    // is deliberately no way to serve live ads by accident.
    const android = String.fromEnvironment(
      'SPINE_AD_UNIT_ANDROID',
      defaultValue: testNativeUnitIdAndroid,
    );
    const ios = String.fromEnvironment(
      'SPINE_AD_UNIT_IOS',
      defaultValue: testNativeUnitIdIos,
    );

    return const AdConfig(
      enabled: bool.fromEnvironment('SPINE_ADS', defaultValue: true),
      frequency: int.fromEnvironment('SPINE_AD_FREQUENCY', defaultValue: 6),
      leadIn: int.fromEnvironment('SPINE_AD_LEAD_IN', defaultValue: 5),
      androidNativeUnitId: android,
      iosNativeUnitId: ios,
      useTestUnits:
          android == testNativeUnitIdAndroid || ios == testNativeUnitIdIos,
    );
  }
}
