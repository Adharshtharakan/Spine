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
}
