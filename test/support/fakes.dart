import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spine/data/models/book.dart';
import 'package:spine/data/models/idea.dart';
import 'package:spine/data/repository/book_repository.dart';
import 'package:spine/services/ads/ad_creative.dart';
import 'package:spine/services/ads/ad_provider.dart';
import 'package:spine/data/models/feed_item.dart';
import 'package:spine/services/audio/audio_track.dart';
import 'package:spine/services/audio/playback_snapshot.dart';
import 'package:spine/services/audio/spine_audio_player.dart';

Book testBook({
  String id = 'test-book',
  String title = 'Test Book',
  int ideaCount = 5,
  bool withAudio = false,
  DateTime? publishedAt,
}) {
  return Book(
    id: id,
    title: title,
    author: 'A. Writer',
    genre: 'Testing',
    durationLabel: '10 MIN',
    spineColor: const Color(0xFFC9A227),
    publishedAt: publishedAt,
    ideas: [
      for (var i = 0; i < ideaCount; i++)
        Idea(
          id: '$id-${i + 1}',
          order: i,
          title: 'Idea ${i + 1}',
          body: 'Body of idea ${i + 1}.',
          duration: const Duration(seconds: 10),
          audioRef: withAudio ? 'asset:assets/audio/$id/0${i + 1}.wav' : null,
        ),
    ],
  );
}

class FakeBookRepository implements BookRepository {
  FakeBookRepository(this.books);

  final List<Book> books;

  @override
  Future<List<Book>> loadBooks() async => books;
}

class FakeAdProvider implements AdProvider {
  final List<String> impressions = [];
  final List<String> clicks = [];

  @override
  Future<void> initialize() async {}

  @override
  AdCreative? creativeFor(AdFeedItem item) => AdCreative(
    id: 'fake-${item.position}',
    sponsor: 'Fake',
    headline: 'Fake headline',
    body: 'Fake body',
    ctaLabel: 'Tap',
    isTest: true,
  );

  @override
  void recordImpression(AdCreative creative) => impressions.add(creative.id);

  @override
  void recordClick(AdCreative creative) => clicks.add(creative.id);
}

/// A player under full test control: nothing advances unless the test says so.
class FakeAudioPlayer implements SpineAudioPlayer {
  final _controller = StreamController<PlaybackSnapshot>.broadcast();
  final List<String> loaded = [];

  PlaybackSnapshot _snapshot = PlaybackSnapshot.idle;

  @override
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  @override
  PlaybackSnapshot get snapshot => _snapshot;

  @override
  Future<void> load(AudioTrack track, {Duration startAt = Duration.zero}) async {
    loaded.add(track.id);
    _emit(
      PlaybackSnapshot(
        trackId: track.id,
        bookId: track.bookId,
        ideaIndex: track.ideaIndex,
        status: PlaybackStatus.paused,
        position: startAt,
        duration: track.expectedDuration,
      ),
    );
  }

  @override
  Future<void> play() async =>
      _emit(_snapshot.copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async =>
      _emit(_snapshot.copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> seek(Duration position) async =>
      _emit(_snapshot.copyWith(position: position));

  @override
  Future<void> stop() async => _emit(PlaybackSnapshot.idle);

  @override
  Future<void> dispose() async => _controller.close();

  /// Simulates the current track running to its end.
  void finishTrack() {
    _emit(
      _snapshot.copyWith(
        position: _snapshot.duration,
        status: PlaybackStatus.completed,
      ),
    );
  }

  void _emit(PlaybackSnapshot next) {
    _snapshot = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}
