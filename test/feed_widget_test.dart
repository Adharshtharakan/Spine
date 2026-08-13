import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/app.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/core/config/app_config.dart';
import 'package:spine/data/models/book.dart';
import 'package:spine/services/persistence/progress_store.dart';

import 'support/fakes.dart';

void main() {
  Future<FakeAudioPlayer> pumpSpine(
    WidgetTester tester, {
    List<Book>? books,
    AdConfig ads = const AdConfig(enabled: false),
    ProgressStore? store,
  }) async {
    final audio = FakeAudioPlayer();

    // Test on a phone-shaped surface rather than the 800x600 default — this is
    // a portrait, full-screen-card product.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SpineApp(
        config: AppConfig(
          environment: 'test',
          contentManifest: 'unused',
          contentBaseUrl: '',
          ads: ads,
        ),
        store: store ?? InMemoryProgressStore(),
        repositoryOverride: FakeBookRepository(
          books ??
              [
                testBook(id: 'one', title: 'First Book'),
                testBook(id: 'two', title: 'Second Book'),
                testBook(id: 'three', title: 'Third Book'),
              ],
        ),
        adProviderOverride: FakeAdProvider(),
        audioOverride: audio,
      ),
    );
    await tester.pumpAndSettle();
    return audio;
  }


  /// A reader with no history lands on the Today card. Tests about the shelf
  /// itself step past it first.
  Future<void> swipeToShelf(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(0, -400), 1400);
    await tester.pumpAndSettle();
  }

  testWidgets('the feed opens on the day\'s idea, then the shelf', (
    tester,
  ) async {
    await pumpSpine(tester);

    // The Today card leads the feed for a reader with no history.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('FROM'), findsOneWidget);

    await swipeToShelf(tester);

    expect(find.text('First Book'), findsOneWidget);
    expect(find.text('IDEA 1 OF 5'), findsOneWidget);
    expect(find.text('Idea 1'), findsOneWidget);
    // Only the current card is on screen.
    expect(find.text('Second Book'), findsNothing);
  });

  testWidgets('swiping up moves to the next book', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(find.text('Second Book'), findsOneWidget);
    expect(find.text('First Book'), findsNothing);
  });

  testWidgets('Next and the ribbon both move through the ideas', (
    tester,
  ) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();
    expect(find.text('IDEA 2 OF 5'), findsOneWidget);

    // Ribbon segments are addressable directly — tap the fourth.
    await tester.tap(find.bySemanticsLabel('Idea 4'));
    await tester.pumpAndSettle();
    expect(find.text('IDEA 4 OF 5'), findsOneWidget);
  });

  testWidgets('a sideways flick moves to the next idea', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.fling(find.text('Idea 1'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('IDEA 2 OF 5'), findsOneWidget);
  });

  testWidgets('Listen mode cues the track and plays it', (tester) async {
    final audio = await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.text('LISTEN'));
    await tester.pumpAndSettle();

    expect(audio.loaded, ['one-1']);
    expect(find.bySemanticsLabel('Play'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pumpAndSettle();

    expect(audio.snapshot.isPlaying, isTrue);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });

  testWidgets('finishing an idea advances the card automatically', (
    tester,
  ) async {
    final audio = await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.text('LISTEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pumpAndSettle();

    audio.finishTrack();
    await tester.pumpAndSettle();

    expect(find.text('IDEA 2 OF 5'), findsOneWidget);
    expect(audio.loaded.last, 'one-2');
  });

  testWidgets('swiping to another book stops playback', (tester) async {
    final audio = await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.text('LISTEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pumpAndSettle();

    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(audio.snapshot.isPlaying, isFalse);
  });

  testWidgets('Watch keeps the Coming Soon card and remembers Notify Me', (
    tester,
  ) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.text('WATCH'));
    await tester.pumpAndSettle();

    expect(find.text('Animated explainer'), findsOneWidget);
    expect(find.text('COMING SOON'), findsOneWidget);

    await tester.tap(find.text('NOTIFY ME'));
    await tester.pumpAndSettle();
    expect(find.text("YOU'LL BE NOTIFIED"), findsOneWidget);

    // Leave the card and come back: the choice survives.
    await tester.fling(find.text('Animated explainer'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Idea 1'), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();

    expect(find.text("YOU'LL BE NOTIFIED"), findsOneWidget);
  });

  testWidgets('saving a book fills the Saved tab', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.bySemanticsLabel('Save book'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('First Book'), findsOneWidget);
    expect(find.text('Nothing saved yet'), findsNothing);
  });

  testWidgets('search finds a book and opens the shelf on it', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    // Both the masthead icon and the tab are called Search; take the tab.
    await tester.tap(find.bySemanticsLabel('Search').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'third');
    await tester.pumpAndSettle();
    expect(find.text('Third Book'), findsOneWidget);

    await tester.tap(find.text('Third Book'));
    await tester.pumpAndSettle();

    // Back on the shelf, parked on the book that was tapped.
    expect(find.text('IDEA 1 OF 5'), findsOneWidget);
    expect(find.text('Third Book'), findsOneWidget);
  });

  testWidgets('ads appear on cadence and are labelled', (tester) async {
    await pumpSpine(
      tester,
      ads: const AdConfig(frequency: 2, leadIn: 2),
    );
    await swipeToShelf(tester);

    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    expect(find.text('TEST AD'), findsOneWidget);
    expect(find.text('Fake headline'), findsOneWidget);
  });

  testWidgets('the reader returns to the card they left on', (tester) async {
    final store = InMemoryProgressStore();
    await pumpSpine(tester, store: store);
    await swipeToShelf(tester);

    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    // Relaunch: tear the app down entirely, then start again on the same
    // storage. (Pumping another SpineApp straight away would update the
    // existing element in place and prove nothing.)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpSpine(tester, store: store);

    expect(find.text('Second Book'), findsOneWidget);
    expect(find.text('IDEA 2 OF 5'), findsOneWidget);
  });
}
