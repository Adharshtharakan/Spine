import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/core/theme/spine_palette.dart';
import 'package:spine/core/theme/spine_theme.dart';
import 'package:spine/ui/feed/page_turn.dart';

import 'render_preview.dart';

/// The turn on its own, frame by frame, with nothing else on the page.
///
///     flutter test test/preview/turn_preview.dart --update-goldens
///
/// A whole-screen capture buries the leaf under the rest of the card; this
/// isolates it so the geometry can actually be read.
void main() {
  setUpAll(loadRealFonts);

  Widget page(String text, Color colour) => DecoratedBox(
    decoration: BoxDecoration(color: colour),
    child: Center(
      child: Text(text, style: const TextStyle(fontSize: 64, color: Colors.black)),
    ),
  );

  Widget harness(String text, Object key, bool forward) => MaterialApp(
    theme: SpineTheme.build(SpinePalette.light),
    home: Scaffold(
      backgroundColor: const Color(0xFF303030),
      body: Padding(
        padding: const EdgeInsets.all(40),
        child: PageTurn(
          turnKey: key,
          forward: forward,
          child: page(text, const Color(0xFFF3EADA)),
        ),
      ),
    ),
  );

  for (final ms in [90, 170, 260, 350, 440]) {
    testWidgets('forward @${ms}ms', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(harness('ONE', 1, true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(harness('TWO', 2, true));
      await tester.pump(Duration(milliseconds: ms));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/turn_fwd_$ms.png'),
      );
      await tester.pumpAndSettle();
    });
  }

  for (final ms in [90, 260, 440]) {
    testWidgets('back @${ms}ms', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(harness('TWO', 2, true));
      await tester.pumpAndSettle();

      await tester.pumpWidget(harness('ONE', 1, false));
      await tester.pump(Duration(milliseconds: ms));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('output/turn_back_$ms.png'),
      );
      await tester.pumpAndSettle();
    });
  }
}
