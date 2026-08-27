import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/ui/feed/page_turn.dart';

/// The turn's contract, both directions.
///
/// The bug this pins: going back used to swing from the opposite edge, because
/// the hinge moved with the direction. A page is bound at the spine — it turns
/// about the same edge whichever way you go, and only the leaf in flight moves.
/// So during *either* direction both pages have to be on screen at once: one
/// lying still, one turning over it.
void main() {
  Widget page(String text) => Center(child: Text(text));

  Future<void> pumpTurn(
    WidgetTester tester, {
    required String text,
    required Object key,
    required bool forward,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageTurn(turnKey: key, forward: forward, child: page(text)),
        ),
      ),
    );
  }

  testWidgets('at rest only the current page is on screen', (tester) async {
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('turning forward shows both pages mid-turn', (tester) async {
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    await pumpTurn(tester, text: 'two', key: 2, forward: true);
    await tester.pump(const Duration(milliseconds: 200));

    // The leaving page is still in flight above the arriving one.
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('turning back shows both pages too', (tester) async {
    await pumpTurn(tester, text: 'two', key: 2, forward: true);
    await tester.pumpAndSettle();

    // Backward: the page being returned to swings down onto the current one.
    await pumpTurn(tester, text: 'one', key: 1, forward: false);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('two'), findsNothing);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('a page that never changes is never wrapped in a transform', (
    tester,
  ) async {
    // A perspective matrix left in place distorts hit testing — the long-press
    // that highlights a sentence lands at the wrong offset.
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(PageTurn),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('turning again mid-turn does not strand the old page', (
    tester,
  ) async {
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    await pumpTurn(tester, text: 'two', key: 2, forward: true);
    await tester.pump(const Duration(milliseconds: 120));
    // Interrupted: a fast reader can outrun the animation.
    await pumpTurn(tester, text: 'three', key: 3, forward: true);
    await tester.pumpAndSettle();

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsNothing);
    expect(find.text('three'), findsOneWidget);
  });
}
