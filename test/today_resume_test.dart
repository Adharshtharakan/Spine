import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/feed_item.dart';
import 'package:spine/ui/feed/today_slide.dart';

import 'support/fakes.dart';

/// The resume row is tested against [TodaySlide] directly rather than through
/// the feed: the daily pick is a hash of the date, so whether it collides with
/// the book being resumed would change from one day to the next and the test
/// would pass or fail on the calendar.
void main() {
  final book = testBook(id: 'two', title: 'Second Book');

  Future<void> pumpToday(WidgetTester tester, {ResumePoint? resume}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaySlide(
            item: DailyIdeaFeedItem(
              book: testBook(id: 'one', title: 'First Book'),
              ideaIndex: 0,
              day: '2026-03-02',
            ),
            onOpenBook: () {},
            resume: resume,
            onResume: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the book the reader was last in', (tester) async {
    await pumpToday(
      tester,
      resume: ResumePoint(book: book, ideaIndex: 2, completed: 2),
    );

    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsOneWidget);
    expect(find.text('Second Book'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
  });

  testWidgets('shows nothing when there is nowhere to return to', (
    tester,
  ) async {
    await pumpToday(tester);

    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsNothing);
  });

  testWidgets('the row is a single target naming the book', (tester) async {
    await pumpToday(
      tester,
      resume: ResumePoint(book: book, ideaIndex: 1, completed: 1),
    );

    expect(find.bySemanticsLabel('Continue Second Book'), findsOneWidget);
  });
}
