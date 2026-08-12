import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/theme/spine_colors.dart';
import 'core/theme/spine_theme.dart';
import 'data/repository/asset_book_repository.dart';
import 'data/repository/book_repository.dart';
import 'services/ads/ad_provider.dart';
import 'services/ads/placeholder_ad_provider.dart';
import 'services/audio/audio_source_resolver.dart';
import 'services/audio/spine_audio_engine.dart';
import 'services/audio/spine_audio_player.dart';
import 'services/persistence/progress_store.dart';
import 'state/library_controller.dart';
import 'state/playback_controller.dart';
import 'state/progress_controller.dart';
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
    this.repositoryOverride,
    this.adProviderOverride,
    this.audioOverride,
  });

  final AppConfig config;
  final ProgressStore store;
  final BookRepository? repositoryOverride;
  final AdProvider? adProviderOverride;
  final SpineAudioPlayer? audioOverride;

  @override
  State<SpineApp> createState() => _SpineAppState();
}

class _SpineAppState extends State<SpineApp> {
  late final BookRepository _repository;
  late final AdProvider _adProvider;
  late final AudioSourceResolver _resolver;
  late final SpineAudioPlayer _audio;

  late final ProgressController _progress;
  late final LibraryController _library;
  late final PlaybackController _playback;
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();

    _repository =
        widget.repositoryOverride ??
        AssetBookRepository(manifestPath: widget.config.contentManifest);
    _adProvider = widget.adProviderOverride ?? PlaceholderAdProvider();
    _resolver = AudioSourceResolver(baseUrl: widget.config.contentBaseUrl);
    _audio = widget.audioOverride ?? SpineAudioEngine(resolver: _resolver);

    _progress = ProgressController(widget.store);
    _library = LibraryController(
      repository: _repository,
      adConfig: widget.config.ads,
    );
    _playback = PlaybackController(engine: _audio, progress: _progress);
    _shell = ShellController();

    // Both loads are independent; the UI renders its loading state until the
    // catalogue lands.
    _adProvider.initialize();
    _progress.load();
    _library.load();
  }

  @override
  void dispose() {
    _playback.dispose();
    _progress.dispose();
    _library.dispose();
    _shell.dispose();
    _resolver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppConfig>.value(value: widget.config),
        Provider<AdProvider>.value(value: _adProvider),
        ChangeNotifierProvider<ProgressController>.value(value: _progress),
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
