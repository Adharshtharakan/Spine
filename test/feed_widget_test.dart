import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/app.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/core/config/app_config.dart';
import 'package:spine/data/models/book.dart';
import 'package:spine/services/persistence/progress_store.dart';
import 'package:spine/data/models/review_item.dart';
import 'package:spine/services/notifications/daily_idea_notifier.dart';
import 'package:spine/services/persistence/review_store.dart';
import 'package:spine/services/widgets/home_widget_publisher.dart';
import 'package:spine/state/progress_controller.dart';
import 'package:spine/state/review_controller.dart';

import 'support/fakes.dart';

void main() {
  Future<FakeAudioPlayer> pumpSpine(
    WidgetTester tester, {
    List<Book>? books,
    AdConfig ads = const AdConfig(enabled: false),
    ProgressStore? store,
    ReviewStore? reviewStore,
    IdeaNotifier? notifier,
    HomeWidgetPublisher? homeWidget,
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
        reviewStore: reviewStore ?? InMemoryReviewStore(),
        repositoryOverride: FakeBookRepository(
          books ??
              [
                testBook(id: 'one', title: 'First Book'),
                testBook(id: 'two', title: 'Second Book'),
                testBook(id: 'three', title: 'Third Book'),
              ],
        ),
        adProviderOverride: FakeAdProvider(),
        notifierOverride: notifier ?? NoopIdeaNotifier(),
        homeWidgetOverride: homeWidget ?? NoopHomeWidgetPublisher(),
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


  testWidgets('reading an idea marks it read, which fills the ribbon', (
    tester,
  ) async {
    final store = InMemoryProgressStore();
    await pumpSpine(tester, store: store);
    await swipeToShelf(tester);

    // Reading has no "finished" event of its own; holding the screen is it.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    final progress = ProgressController(store);
    await progress.load();
    expect(progress.of('one').completedIdeas, contains(0));
  });

  testWidgets('a quick scroll past an idea does not count as reading it', (
    tester,
  ) async {
    final store = InMemoryProgressStore();
    await pumpSpine(tester, store: store);
    await swipeToShelf(tester);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.fling(find.text('Idea 1'), const Offset(0, -400), 1200);
    await tester.pumpAndSettle();

    final progress = ProgressController(store);
    await progress.load();
    expect(progress.of('one').completedIdeas, isEmpty);
  });

  testWidgets('an idea can be saved on its own', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.bySemanticsLabel('Save this idea'));
    await tester.pumpAndSettle();

    // The control itself has to flip, not just the stored state.
    expect(find.bySemanticsLabel('Unsave this idea'), findsOneWidget);
    expect(find.bySemanticsLabel('Save this idea'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('IDEAS'), findsOneWidget);
    expect(find.text('Idea 1'), findsOneWidget);
    // The whole book was not saved, only the idea.
    expect(find.text('BOOKS'), findsNothing);
  });

  testWidgets('an idea can be shared without going into Listen', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    // Read is the mode readers land in, and sharing used to be reachable
    // only from the Listen transport — invisible to anyone who never played
    // audio. It belongs on the idea, in every mode.
    expect(find.bySemanticsLabel('Share this idea'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Share this idea'));
    await tester.pumpAndSettle();

    expect(find.text('SHARE THIS IDEA'), findsOneWidget);
    expect(find.text('Instagram Stories'), findsOneWidget);
    expect(find.text('Facebook Stories'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
  });

  testWidgets('the last idea opens the recap', (tester) async {
    await pumpSpine(tester);
    await swipeToShelf(tester);

    await tester.tap(find.bySemanticsLabel('Idea 5'));
    await tester.pumpAndSettle();
    expect(find.text('IDEA 5 OF 5'), findsOneWidget);

    // The end of the book is a destination, not a dead end.
    await tester.tap(find.text('ALL 5 IDEAS'));
    await tester.pumpAndSettle();

    expect(find.text('THE WHOLE BOOK'), findsOneWidget);
    expect(find.text('All of First Book, on one page'), findsOneWidget);

    // The page holds all five; the later ones are a scroll away rather than
    // built off-screen.
    expect(find.text('Idea 1'), findsOneWidget);
    expect(find.text('Idea 2'), findsOneWidget);

    await tester.drag(find.text('Idea 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Idea 5'), findsOneWidget);

    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(find.text('IDEA 5 OF 5'), findsOneWidget);
  });

  testWidgets('a due idea comes back as a review card', (tester) async {
    final reviews = InMemoryReviewStore();
    await reviews.saveAll([
      ReviewItem(
        ideaId: 'one-2',
        bookId: 'one',
        dueAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);

    await pumpSpine(tester, reviewStore: reviews);
    await tester.fling(find.byType(PageView), const Offset(0, -400), 1400);
    await tester.pumpAndSettle();

    // The prompt comes first; the idea itself is withheld until asked for.
    expect(find.text('REVIEW'), findsOneWidget);
    expect(find.text('Idea 2'), findsOneWidget);
    expect(find.text('What was this one about?'), findsOneWidget);
    expect(find.text('Body of idea 2.'), findsNothing);

    await tester.tap(find.text('SHOW ME'));
    await tester.pumpAndSettle();

    expect(find.text('Body of idea 2.'), findsOneWidget);

    // Seeing it again pushes it out to the next interval.
    final reloaded = ReviewController(reviews);
    await reloaded.load();
    expect(reloaded.due(), isEmpty);
    expect(reloaded.isQueued('one-2'), isTrue);
  });

  testWidgets('turning on the daily idea schedules it and remembers the time', (
    tester,
  ) async {
    final notifier = NoopIdeaNotifier();
    final store = InMemoryProgressStore();
    await pumpSpine(tester, store: store, notifier: notifier);

    await tester.tap(find.bySemanticsLabel('You'));
    await tester.pumpAndSettle();

    expect(find.text("THE DAY'S IDEA"), findsOneWidget);

    await tester.tap(find.text('MORNING'));
    await tester.pumpAndSettle();

    // Permission is asked for at the moment it's turned on, not at launch.
    expect(notifier.calls, contains('requestPermission'));
    expect(notifier.calls.any((c) => c.startsWith('schedule:8')), isTrue);

    final progress = ProgressController(store);
    await progress.load();
    expect(progress.dailyIdeaHour, 8);
  });

  testWidgets('tapping the chosen time again turns it off', (tester) async {
    final notifier = NoopIdeaNotifier();
    await pumpSpine(tester, notifier: notifier);

    await tester.tap(find.bySemanticsLabel('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EVENING'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EVENING'));
    await tester.pumpAndSettle();

    expect(notifier.calls.last, 'cancelAll');
  });

  testWidgets("the home-screen widget is handed today's idea on launch", (
    tester,
  ) async {
    final widget = NoopHomeWidgetPublisher();
    await pumpSpine(tester, homeWidget: widget);

    // Same pick the Today card shows — the widget never computes its own.
    expect(widget.published, hasLength(1));
    expect(find.text(widget.published.single), findsOneWidget);
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
