import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/app.dart';
import 'package:spine/core/config/ad_config.dart';
import 'package:spine/core/config/app_config.dart';
import 'package:spine/data/models/companion.dart';
import 'package:spine/data/models/session_state.dart';
import 'package:spine/services/notifications/daily_idea_notifier.dart';
import 'package:spine/services/persistence/progress_store.dart';
import 'package:spine/services/persistence/review_store.dart';
import 'package:spine/services/widgets/home_widget_publisher.dart';
import 'package:spine/ui/screens/profile_screen.dart';
import 'package:spine/ui/widgets/hoot.dart';

import 'support/fakes.dart';

/// The header reads out as one button carrying its own contents — "Change your
/// name, R, Reader, 1 DAY STREAK, Novice" — so it is matched on the action
/// rather than by pinning that whole string.
final _changeName = RegExp('Change your name');

void main() {
  group('Hoot levels up on ideas read, and nothing else', () {
    test('a reader who has finished nothing is level one', () {
      final level = CompanionLevel.forIdeas(0);

      expect(level.level, 1);
      expect(level.title, 'Novice');
      expect(level.xp, 0);
      expect(level.progress, 0);
      expect(level.isMaxed, isFalse);
    });

    test('XP is ideas at ten apiece', () {
      expect(CompanionLevel.forIdeas(12).xp, 120);
      expect(CompanionLevel.forIdeas(12).xpIntoLevel, 120);
      expect(CompanionLevel.forIdeas(12).xpForLevel, 300);
    });

    test('a rank boundary is the first XP of the new rank, not the last of '
        'the old', () {
      expect(CompanionLevel.forIdeas(29).level, 1);
      expect(CompanionLevel.forIdeas(30).level, 2);
      expect(CompanionLevel.forIdeas(30).title, 'Reader');
      // Reset against the new floor, not carried over from the old one.
      expect(CompanionLevel.forIdeas(30).xpIntoLevel, 0);
    });

    test('the top rank has a full bar, not an empty one', () {
      // Arriving somewhere should not look identical to having just started.
      final top = CompanionLevel.forIdeas(500);

      expect(top.title, 'Owl');
      expect(top.isMaxed, isTrue);
      expect(top.xpForLevel, isNull);
      expect(top.progress, 1);
    });

    test('a negative count cannot happen, and does not throw if it does', () {
      expect(CompanionLevel.forIdeas(-4).level, 1);
      expect(CompanionLevel.forIdeas(-4).xp, 0);
    });
  });

  group('achievements', () {
    test('are earned at the threshold, not past it', () {
      final rows = achievementsFor(
        streak: 5,
        ideasRead: 10,
        booksFinished: 0,
      );

      Achievement row(String title) =>
          rows.firstWhere((row) => row.title == title);

      expect(row('5 day streak').earned, isTrue);
      expect(row('14 day streak').earned, isFalse);
      expect(row('10 ideas').earned, isTrue);
      expect(row('50 ideas').earned, isFalse);
      expect(row('First book').earned, isFalse);
    });
  });

  group('the reader s name', () {
    test('an unset name reads as Reader without storing one', () {
      const state = SessionState();

      expect(state.readerName, isNull);
      expect(state.displayName, 'Reader');
    });

    test('whitespace is not a name', () {
      expect(const SessionState(readerName: '   ').displayName, 'Reader');
      expect(const SessionState(readerName: ' Ada ').displayName, 'Ada');
    });

    test('survives a round trip through storage', () {
      final restored = SessionState.fromJson(
        const SessionState(readerName: 'Ada').toJson(),
      );

      expect(restored.readerName, 'Ada');
    });

    test('a session saved before this existed still loads', () {
      // Readers upgrading have no such key, and must not land on a crash.
      final restored = SessionState.fromJson(const {'streak': 3});

      expect(restored.readerName, isNull);
      expect(restored.displayName, 'Reader');
      expect(restored.streak, 3);
    });
  });

  group('the profile screen', () {
    Future<InMemoryProgressStore> pumpProfile(
      WidgetTester tester, {
      SessionState? session,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final store = InMemoryProgressStore();
      if (session != null) await store.saveSession(session);

      await tester.pumpWidget(
        SpineApp(
          config: const AppConfig(
            environment: 'test',
            contentManifest: 'unused',
            contentBaseUrl: '',
            ads: AdConfig(enabled: false),
          ),
          store: store,
          reviewStore: InMemoryReviewStore(),
          repositoryOverride: FakeBookRepository([
            testBook(id: 'one', title: 'First Book'),
          ]),
          adProviderOverride: FakeAdProvider(),
          notifierOverride: NoopIdeaNotifier(),
          homeWidgetOverride: NoopHomeWidgetPublisher(),
          audioOverride: FakeAudioPlayer(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('You'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('shows Hoot even with no artwork installed', (tester) async {
      // The poses are optional assets. A missing one has to draw the stand-in,
      // not a broken-image box or an exception during layout.
      await pumpProfile(tester);

      expect(find.byType(Hoot), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renaming changes the header and the avatar with it', (
      tester,
    ) async {
      final store = await pumpProfile(tester);
      expect(find.text('Reader'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(_changeName));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ada');
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Ada'), findsOneWidget);
      // The initial is taken from the name, so it moves with it rather than
      // staying stuck on the default's letter.
      expect(find.text('A'), findsOneWidget);
      expect(find.text('R'), findsNothing);

      expect((await store.loadSession()).readerName, 'Ada');
    });

    testWidgets('cancelling leaves the name alone', (tester) async {
      await pumpProfile(tester, session: const SessionState(readerName: 'Ada'));
      expect(find.text('Ada'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(_changeName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Grace');
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsNothing);
    });

    testWidgets('clearing the field puts the default back', (tester) async {
      // An empty box is a deliberate "no name", and has to be told apart from
      // dismissing the sheet.
      final store = await pumpProfile(
        tester,
        session: const SessionState(readerName: 'Ada'),
      );

      await tester.tap(find.bySemanticsLabel(_changeName));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.bySemanticsLabel('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Reader'), findsOneWidget);
      expect((await store.loadSession()).readerName, isNull);
    });

    testWidgets('the awards sheet lists what has and has not been earned', (
      tester,
    ) async {
      await pumpProfile(tester);

      // A fixed drag rather than dragUntilVisible: that stops as soon as the
      // target is on screen at all, which leaves it under the floating nav bar
      // and sends the tap to a tab instead.
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('Achievements'), findsWidgets);
      expect(find.text('First idea'), findsOneWidget);
      expect(find.text('365 day streak'), findsOneWidget);
    });
  });
}
