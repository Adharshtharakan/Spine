import 'package:flutter_test/flutter_test.dart';
import 'package:spine/core/config/ad_config.dart';

import 'render_preview.dart';

void main() {
  setUpAll(loadRealFonts);

  testWidgets('shelf — read mode', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);
    await capture(tester, 'shelf_read');
  });

  testWidgets('shelf — a later book, second idea', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);

    await swipeToCard(tester, 2);
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    await capture(tester, 'shelf_read_later');
  });

  testWidgets('shelf — listen mode, playing', (tester) async {
    usePhoneSurface(tester);
    final audio = await pumpApp(tester);

    await tester.tap(find.text('LISTEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pumpAndSettle();
    await audio.seek(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await capture(tester, 'shelf_listen');
  });

  testWidgets('shelf — watch, coming soon', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);

    await tester.tap(find.text('WATCH'));
    await tester.pumpAndSettle();

    await capture(tester, 'shelf_watch');
  });

  testWidgets('feed — sponsored card', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, ads: const AdConfig(frequency: 2, leadIn: 2));

    await swipeToCard(tester, 2);

    await capture(tester, 'feed_ad');
  });

  testWidgets('search', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Search').last);
    await tester.pumpAndSettle();

    await capture(tester, 'search');
  });

  testWidgets('saved', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Save book'));
    await tester.pumpAndSettle();
    await swipeToCard(tester, 1);
    await tester.tap(find.bySemanticsLabel('Save book'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Saved'));
    await tester.pumpAndSettle();

    await capture(tester, 'saved');
  });

  testWidgets('you', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('You'));
    await tester.pumpAndSettle();

    await capture(tester, 'profile');
  });
}
