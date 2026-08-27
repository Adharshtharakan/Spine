import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/session_state.dart';

import 'package:spine/services/persistence/progress_store.dart';

import 'render_preview.dart';

/// Renders the app in Paper mode, so the light palette can be judged without
/// toggling it by hand on a device.
///
///     flutter test test/preview/paper_preview.dart --update-goldens
void main() {
  setUpAll(loadRealFonts);

  testWidgets('paper — shelf', (tester) async {
    usePhoneSurface(tester);

    final store = InMemoryProgressStore();
    await store.saveSession(const SessionState(darkMode: false));

    await pumpApp(tester, store: store);
    await swipeToCard(tester, 1);
    await capture(tester, 'paper_shelf');
  });

  testWidgets('paper — saved', (tester) async {
    usePhoneSurface(tester);

    final store = InMemoryProgressStore();
    await store.saveSession(const SessionState(darkMode: false));

    await pumpApp(tester, store: store);
    // The shell painted a hardcoded dark gradient behind every tab; the shelf
    // was only ever hiding it behind a card.
    await tester.tap(find.bySemanticsLabel('Saved').last);
    await tester.pumpAndSettle();
    await capture(tester, 'paper_saved');
  });
}
