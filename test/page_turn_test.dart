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

  testWidgets('turning forward shows both pages before the leaf goes over', (
    tester,
  ) async {
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    await pumpTurn(tester, text: 'two', key: 2, forward: true);
    // Early, while the leaf is still face-up: past upright it turns onto its
    // back and its text is no longer the side you can see.
    await tester.pump(const Duration(milliseconds: 150));

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
    // It starts face-down — the reader sees its back until it passes upright —
    // so the point where both faces are readable is late in the turn, the
    // mirror of the forward case.
    await pumpTurn(tester, text: 'one', key: 1, forward: false);
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('two'), findsNothing);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('a page that never changes is wrapped in nothing at all', (
    tester,
  ) async {
    // Whatever the turn puts round the page has to come off once it lands.
    // A clip or a transform left in place costs a layer on every frame the
    // reader is actually reading, and a perspective matrix left in place also
    // distorts hit testing — the long-press that highlights a sentence lands
    // at the wrong offset.
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    Finder inside(Type type) =>
        find.descendant(of: find.byType(PageTurn), matching: find.byType(type));

    expect(inside(Transform), findsNothing);
    expect(inside(ClipPath), findsNothing);
    expect(inside(ClipRect), findsNothing);
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

  testWidgets('mid-turn the sheet is cut into a fold, not spun whole', (
    tester,
  ) async {
    // Three pieces, and it has to be all three: the part still lying flat, the
    // part folded back over it, and the page uncovered beyond the crease. A
    // sheet spun about the spine instead reads as nothing happening for half
    // the turn — under perspective the near edge is magnified by as much as
    // the rotation foreshortens it — and then going edge-on and vanishing.
    await pumpTurn(tester, text: 'one', key: 1, forward: true);
    await tester.pumpAndSettle();

    await pumpTurn(tester, text: 'two', key: 2, forward: true);
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.descendant(
        of: find.byType(PageTurn),
        matching: find.byType(ClipPath),
      ),
      findsNWidgets(3),
    );

    await tester.pumpAndSettle();
  });
}
