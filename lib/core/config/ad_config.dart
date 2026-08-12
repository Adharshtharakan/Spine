/// How often an ad card is woven into the feed.
///
/// The feed itself knows nothing about frequency — it renders whatever
/// `FeedComposer` produces. Changing the cadence (or switching ads off) is a
/// config change, never a feed-architecture change.
class AdConfig {
  const AdConfig({
    this.enabled = true,
    this.frequency = 4,
    this.leadIn = 4,
    this.maxAdsPerSession,
  }) : assert(frequency > 0, 'frequency must be at least 1');

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

  AdConfig copyWith({
    bool? enabled,
    int? frequency,
    int? leadIn,
    int? maxAdsPerSession,
  }) {
    return AdConfig(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      leadIn: leadIn ?? this.leadIn,
      maxAdsPerSession: maxAdsPerSession ?? this.maxAdsPerSession,
    );
  }

  static AdConfig fromEnvironment() {
    return const AdConfig(
      enabled: bool.fromEnvironment('SPINE_ADS', defaultValue: true),
      frequency: int.fromEnvironment('SPINE_AD_FREQUENCY', defaultValue: 4),
      leadIn: int.fromEnvironment('SPINE_AD_LEAD_IN', defaultValue: 4),
    );
  }
}
