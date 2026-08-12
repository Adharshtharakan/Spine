import 'package:flutter_test/flutter_test.dart';
import 'package:spine/services/persistence/progress_store.dart';
import 'package:spine/state/playback_controller.dart';
import 'package:spine/state/progress_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeAudioPlayer engine;
  late ProgressController progress;
  late PlaybackController playback;

  setUp(() async {
    engine = FakeAudioPlayer();
    progress = ProgressController(InMemoryProgressStore());
    await progress.load();
    playback = PlaybackController(engine: engine, progress: progress);
  });

  test('opening an idea loads its track', () async {
    final book = testBook();
    await playback.open(book, 0);

    expect(engine.loaded, ['test-book-1']);
    expect(engine.snapshot.bookId, 'test-book');
  });

  test('re-opening the loaded idea does not restart it', () async {
    final book = testBook();
    await playback.open(book, 0, autoplay: true);
    await playback.open(book, 0);

    expect(engine.loaded, hasLength(1));
    expect(engine.snapshot.isPlaying, isTrue);
  });

  test('finishing an idea banks progress and rolls into the next', () async {
    final book = testBook();
    await playback.open(book, 0, autoplay: true);

    engine.finishTrack();
    await pumpEventQueue();

    expect(progress.of(book.id).completedIdeas, contains(0));
    expect(progress.of(book.id).ideaIndex, 1);
    expect(engine.loaded.last, 'test-book-2');
    expect(engine.snapshot.isPlaying, isTrue);
  });

  test('finishing the last idea stops rather than wrapping around', () async {
    final book = testBook(ideaCount: 2);
    await playback.open(book, 1, autoplay: true);

    engine.finishTrack();
    await pumpEventQueue();

    expect(progress.of(book.id).completedIdeas, contains(1));
    expect(progress.of(book.id).ideaIndex, 1);
    expect(engine.loaded, hasLength(1));
  });

  test('toggle pauses a playing idea and resumes it', () async {
    final book = testBook();
    await playback.open(book, 0, autoplay: true);

    await playback.toggle(book, 0);
    expect(engine.snapshot.isPlaying, isFalse);

    await playback.toggle(book, 0);
    expect(engine.snapshot.isPlaying, isTrue);
  });

  test('toggling a different idea switches to it and plays', () async {
    final book = testBook();
    await playback.open(book, 0, autoplay: true);

    await playback.toggle(book, 3);

    expect(engine.loaded.last, 'test-book-4');
    expect(engine.snapshot.isPlaying, isTrue);
  });

  test('stopping banks the position so Listen can resume there', () async {
    final book = testBook();
    await playback.open(book, 0, autoplay: true);
    await playback.seekFraction(0.5);

    await playback.stop();

    expect(progress.of(book.id).resumeAt, const Duration(seconds: 5));
    expect(engine.snapshot.status.name, 'idle');
  });

  test('opening resumes from the stored position', () async {
    final book = testBook();
    progress.setResumePosition(book.id, 0, const Duration(seconds: 4));

    await playback.open(book, 0);

    expect(engine.snapshot.position, const Duration(seconds: 4));
  });
}
