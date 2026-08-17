import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/theme/spine_colors.dart';
import 'core/theme/spine_theme.dart';
import 'data/repository/asset_book_repository.dart';
import 'data/repository/book_repository.dart';
import 'core/config/ad_config.dart';
import 'services/ads/ad_provider.dart';
import 'services/ads/admob_ad_provider.dart';
import 'services/ads/native_ad_preloader.dart';
import 'services/ads/placeholder_ad_provider.dart';
import 'services/audio/audio_source_resolver.dart';
import 'services/audio/spine_audio_engine.dart';
import 'services/audio/spine_audio_player.dart';
import 'services/persistence/progress_store.dart';
import 'services/notifications/daily_idea_notifier.dart';
import 'services/persistence/review_store.dart';
import 'services/security/capture_guard.dart';
import 'services/sharing/story_card_renderer.dart';
import 'services/sharing/story_share_service.dart';
import 'services/widgets/home_widget_publisher.dart';
import 'state/library_controller.dart';
import 'state/playback_controller.dart';
import 'state/progress_controller.dart';
import 'state/review_controller.dart';
import 'state/shell_controller.dart';
import 'ui/screens/root_shell.dart';

/// Composition root. Every dependency is built here and injected, so any of
/// them — repository, store, audio engine, ad provider — can be swapped for a
/// different implementation (or a fake, in tests) without touching a screen.
class SpineApp extends StatefulWidget {
  const SpineApp({
    super.key,
    required this.config,
    required this.store,
    required this.reviewStore,
    this.repositoryOverride,
    this.adProviderOverride,
    this.adPreloaderOverride,
    this.audioOverride,
    this.notifierOverride,
    this.captureGuardOverride,
    this.homeWidgetOverride,
    this.storyShareServiceOverride,
  });

  final AppConfig config;
  final ProgressStore store;
  final ReviewStore reviewStore;
  final BookRepository? repositoryOverride;
  final AdProvider? adProviderOverride;

  /// Null keeps the feed on house creatives — which is what tests and any
  /// platform without the ads SDK get.
  final NativeAdPreloader? adPreloaderOverride;
  final SpineAudioPlayer? audioOverride;
  final IdeaNotifier? notifierOverride;
  final CaptureGuard? captureGuardOverride;
  final HomeWidgetPublisher? homeWidgetOverride;
  final StoryShareService? storyShareServiceOverride;

  @override
  State<SpineApp> createState() => _SpineAppState();
}

class _SpineAppState extends State<SpineApp> {
  late final BookRepository _repository;
  late final AdProvider _adProvider;
  NativeAdPreloader? _adPreloader;

  /// Only what this State built is torn down by it. An injected preloader
  /// belongs to whoever injected it, and disposing it here would be a second
  /// dispose on an object the caller still owns.
  bool _ownsAdPreloader = false;
  late final AudioSourceResolver _resolver;
  late final SpineAudioPlayer _audio;

  late final ProgressController _progress;
  late final ReviewController _review;
  late final LibraryController _library;
  late final PlaybackController _playback;
  late final ShellController _shell;
  late final IdeaNotifier _notifier;
  late final CaptureGuard _captureGuard;
  late final HomeWidgetPublisher _homeWidget;
  late final StoryCardRenderer _storyRenderer;
  late final StoryShareService _storyShareService;

  @override
  void initState() {
    super.initState();

    _notifier = widget.notifierOverride ?? LocalIdeaNotifier();
    _captureGuard = widget.captureGuardOverride ?? CaptureGuard();
    _homeWidget = widget.homeWidgetOverride ?? const SpineHomeWidgetPublisher();
    _storyRenderer = const StoryCardRenderer();
    _storyShareService =
        widget.storyShareServiceOverride ?? NativeStoryShareService();

    // On Android this genuinely blocks screenshots and screen recording; on
    // iOS it only hides the app-switcher snapshot and reports captures. See
    // CaptureGuard.
    _captureGuard.enable();

    _repository =
        widget.repositoryOverride ??
        AssetBookRepository(manifestPath: widget.config.contentManifest);
    // AdMob only where there is an AdMob: desktop and test runs stay on the
    // house creatives rather than reaching for an SDK that isn't there.
    final useAdMob = widget.config.ads.enabled && AdConfig.supportsAds;
    _adProvider =
        widget.adProviderOverride ??
        (useAdMob
            ? AdMobAdProvider(config: widget.config.ads)
            : PlaceholderAdProvider());
    _ownsAdPreloader = widget.adPreloaderOverride == null;
    _adPreloader =
        widget.adPreloaderOverride ??
        (useAdMob ? NativeAdPreloader(config: widget.config.ads) : null);
    _resolver = AudioSourceResolver(baseUrl: widget.config.contentBaseUrl);
    _audio = widget.audioOverride ?? SpineAudioEngine(resolver: _resolver);

    _progress = ProgressController(widget.store);
    _review = ReviewController(widget.reviewStore);

    // Finishing an idea is what puts it in the review queue. Progress stays
    // ignorant of reviews; it just announces the completion.
    _progress.onIdeaCompleted = (bookId, ideaId) =>
        _review.schedule(ideaId: ideaId, bookId: bookId);
    _library = LibraryController(
      repository: _repository,
      adConfig: widget.config.ads,
    );
    _playback = PlaybackController(engine: _audio, progress: _progress);
    _shell = ShellController();

    _adProvider.initialize();

    // Ordered: the shelf puts books you've started back near the top, so the
    // catalogue can't be arranged until stored progress is in memory.
    _progress.load().then((_) => _review.load()).then((_) {
      if (!mounted) return;
      _library.load(
        progressOf: _progress.of,
        dueReviews: _review.due(limit: 2),
      ).then((_) {
        _refreshDailyIdea();
        // The widget is a reader: the app hands it today's idea on launch and
        // it renders whatever it was last given.
        _homeWidget.publish(books: _library.books, now: DateTime.now());
      });
    });

    // Re-scheduling when the preference changes keeps the queued notifications
    // honest without the settings screen knowing about the notifier.
    _progress.addListener(_refreshDailyIdea);
  }

  int? _scheduledHour;
  bool _scheduling = false;

  /// Keeps the fortnight of queued ideas in step with the reader's preference.
  Future<void> _refreshDailyIdea() async {
    final hour = _progress.dailyIdeaHour;
    if (_scheduling || hour == _scheduledHour) return;
    if (_library.status != LibraryStatus.ready) return;

    _scheduling = true;
    try {
      if (hour == null) {
        await _notifier.cancelAll();
      } else {
        await _notifier.schedule(
          books: _library.books,
          timeOfDay: Duration(hours: hour),
        );
      }
      _scheduledHour = hour;
    } finally {
      _scheduling = false;
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_refreshDailyIdea);
    _playback.dispose();
    _progress.dispose();
    _review.dispose();
    _library.dispose();
    _shell.dispose();
    _resolver.dispose();
    if (_ownsAdPreloader) _adPreloader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: widget.config),
        Provider<AdProvider>.value(value: _adProvider),
        // ChangeNotifierProvider, not Provider: the preloader notifies when a
        // slot fills, and plain Provider rejects a Listenable outright since
        // it can't pass those notifications on.
        //
        // Nullable on purpose — the feed treats "no preloader" as "no network
        // ads", so nothing downstream needs a platform check of its own. That
        // null is also why this took a device to find: every test left it
        // null, and null isn't a Listenable, so the assert stayed quiet.
        //
        // `.value` deliberately: disposal belongs to this State, alongside
        // every other service it builds.
        ChangeNotifierProvider<NativeAdPreloader?>.value(value: _adPreloader),
        Provider<IdeaNotifier>.value(value: _notifier),
        Provider<StoryCardRenderer>.value(value: _storyRenderer),
        Provider<StoryShareService>.value(value: _storyShareService),
        ChangeNotifierProvider<ProgressController>.value(value: _progress),
        ChangeNotifierProvider<ReviewController>.value(value: _review),
        ChangeNotifierProvider<LibraryController>.value(value: _library),
        ChangeNotifierProvider<PlaybackController>.value(value: _playback),
        ChangeNotifierProvider<ShellController>.value(value: _shell),
      ],
      child: MaterialApp(
        title: 'Spine',
        debugShowCheckedModeBanner: false,
        theme: SpineTheme.build(),
        home: const _Bootstrap(),
        builder: (context, child) {
          // Spine's layout is tuned type; huge system text scales would break
          // the cards, so scaling is honoured within a range rather than
          // ignored.
          final scale = MediaQuery.textScalerOf(context).clamp(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.25,
          );
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scale),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Holds the splash colour until stored progress is in memory.
///
/// The shelf builds its scroll position once, on the way in — so it has to know
/// where the reader left off before it is built, not a frame later.
class _Bootstrap extends StatelessWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context) {
    final ready = context.select<ProgressController, bool>(
      (controller) => controller.isLoaded,
    );

    if (!ready) {
      return const ColoredBox(
        color: SpineColors.ink,
        child: SizedBox.expand(),
      );
    }
    return const RootShell();
  }
}
