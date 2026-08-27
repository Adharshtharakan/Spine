import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/app.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/core/config/app_config.dart';
import 'package:spine/data/repository/asset_book_repository.dart';
import 'package:spine/services/persistence/progress_store.dart';
import 'package:spine/services/persistence/review_store.dart';

import '../support/fakes.dart';

/// A design harness, not a regression test.
///
/// It renders real screens, with the real catalogue and the real fonts, to PNGs
/// under `test/preview/output/`, so the UI can be looked at without a device:
///
///     flutter test test/preview/screens_preview.dart --update-goldens
///
/// The file is deliberately not named `*_test.dart`, so `flutter test` skips it:
/// these images are meant to change whenever the design does, and failing the
/// suite for that would be noise.
///
/// Nothing here asserts anything about appearance — deleting the folder would
/// not change the app.

/// Golden rendering defaults to a placeholder font; Spine is mostly typography,
/// so the previews load the real files.
Future<void> loadRealFonts() async {
  const families = {
    'Fraunces': 'assets/fonts/Fraunces-Variable.ttf',
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'IBMPlexMono': 'assets/fonts/IBMPlexMono-Medium.ttf',
  };

  for (final entry in families.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }

  await _loadMaterialIcons();
}

/// Icons come from the Flutter SDK rather than the app bundle, so goldens draw
/// them as empty boxes unless the font is loaded by hand. Best-effort: if the
/// SDK isn't where we expect, previews still render, just without glyphs.
Future<void> _loadMaterialIcons() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      p.dirname(p.dirname(Platform.resolvedExecutable));

  final candidates = [
    p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts',
        'MaterialIcons-Regular.otf'),
    p.join(p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable))),
        'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf'),
  ];

  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
    return;
  }
}

/// A 6.1" phone with a notch and a home indicator — what Spine is designed for.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
  addTearDown(tester.view.reset);
}

Future<FakeAudioPlayer> pumpApp(
  WidgetTester tester, {
  AdConfig ads = const AdConfig(frequency: 4, leadIn: 4),
  ProgressStore? store,
}) async {
  final audio = FakeAudioPlayer();

  // Read the real catalogue outside the frame loop. Asset loading resolves on
  // real I/O, which fake-time pumping can't be relied on to drive.
  final books = await tester.runAsync(
    () => AssetBookRepository(manifestPath: 'assets/content/books.json').loadBooks(),
  );

  await tester.pumpWidget(
    SpineApp(
      config: AppConfig(
        environment: 'preview',
        contentManifest: 'assets/content/books.json',
        contentBaseUrl: '',
        ads: ads,
      ),
      store: store ?? InMemoryProgressStore(),
      reviewStore: InMemoryReviewStore(),
      repositoryOverride: FakeBookRepository(books!),
      adProviderOverride: FakeAdProvider(),
      audioOverride: audio,
    ),
  );
  await tester.pumpAndSettle();
  return audio;
}

/// Writes the current frame to `test/preview/output/<name>.png`.
///
/// Asset images decode off the test's fake-async clock, so any cover still
/// loading when the frame is taken paints nothing — the preview would show an
/// empty card and misrepresent the design it exists to show. Precaching first
/// is what makes these images honest.
Future<void> capture(WidgetTester tester, String name) async {
  await precacheCovers(tester);
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('output/$name.png'),
  );
}

/// Decodes every cover currently mounted in the tree.
Future<void> precacheCovers(WidgetTester tester) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  if (images.isEmpty) return;

  final context = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final image in images) {
      // An absent asset is a legitimate state — Hoot's poses are optional and
      // the widget draws its own stand-in — so a preview must not fail on one.
      await precacheImage(image.image, context, onError: (_, __) {});
    }
  });
}

/// Swipes the feed up [times] cards.
Future<void> swipeToCard(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.fling(find.byType(PageView), const Offset(0, -400), 1400);
    await tester.pumpAndSettle();
  }
}
