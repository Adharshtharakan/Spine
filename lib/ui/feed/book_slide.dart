import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/book.dart';
import '../../data/models/book_progress.dart';
import '../../data/models/reading_mode.dart';
import '../../services/audio/playback_snapshot.dart';
import '../../state/playback_controller.dart';
import '../../state/progress_controller.dart';
import 'cover_backdrop.dart';
import 'book_header.dart';
import 'book_recap.dart';
import 'idea_view.dart';
import 'listen_controls.dart';
import 'mode_toggle.dart';
import 'read_controls.dart';
import 'spine_ribbon.dart';
import 'watch_panel.dart';
import '../sharing/story_share_sheet.dart';
import '../widgets/spine_top_bar.dart';

/// Width of the ribbon rail on the left of every card. Text on the card lines
/// up to the right of it, so the card has a single left edge.
const double _railWidth = 28;

/// One book, one full screen.
///
/// Rebuild scope is deliberate: the card as a whole reacts to that book's
/// progress, while the backdrop, the ribbon and the transport — the only things
/// that move at scroll or playback rate — subscribe on their own.
class BookSlide extends StatefulWidget {
  const BookSlide({
    super.key,
    required this.book,
    required this.isActive,
    this.pageController,
    this.pageIndex = 0,
  });

  final Book book;

  /// Whether this is the card the reader is currently on. Off-screen cards stay
  /// built (the feed keeps a neighbour ready) but never drive audio.
  final bool isActive;

  /// Supplied by the feed so the light can drift against the scroll.
  final PageController? pageController;
  final int pageIndex;

  @override
  State<BookSlide> createState() => _BookSlideState();
}

class _BookSlideState extends State<BookSlide> {
  /// How long an idea has to be the thing on screen before it counts as read.
  /// Long enough that a fast scroll past doesn't bank it, short enough that
  /// actually reading it always does.
  static const _dwell = Duration(seconds: 3);

  Timer? _dwellTimer;
  bool _showRecap = false;
  int? _dwellingOn;

  Book get book => widget.book;

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
  }

  /// Read mode has no natural "finished" event the way audio does, so the card
  /// banks an idea once it has held the screen. Without this, reading a book
  /// end to end never marks a single idea complete.
  void _watchDwell(int ideaIndex, BookProgress progress) {
    final active = widget.isActive && progress.mode == ReadingMode.read;
    final alreadyRead = progress.completedIdeas.contains(ideaIndex);

    if (!active || alreadyRead || _showRecap) {
      _dwellTimer?.cancel();
      _dwellTimer = null;
      _dwellingOn = null;
      return;
    }

    if (_dwellingOn == ideaIndex && _dwellTimer != null) return;

    _dwellTimer?.cancel();
    _dwellingOn = ideaIndex;
    _dwellTimer = Timer(_dwell, () {
      if (!mounted) return;
      context.read<ProgressController>().markIdeaComplete(
        book.id,
        ideaIndex,
        ideaId: book.ideaAt(ideaIndex).id,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.select<ProgressController, BookProgress>(
      (controller) => controller.of(book.id),
    );
    final ideaIndex = progress.ideaIndex.clamp(0, book.ideaCount - 1);

    // Short devices (and large system text) get a tighter card so the idea
    // itself never loses its room.
    final compact = MediaQuery.sizeOf(context).height < 760;

    _watchDwell(ideaIndex, progress);

    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(
          book: book,
          controller: widget.pageController,
          index: widget.pageIndex,
        ),
        Padding(
          // Clears the floating masthead at the top; the light behind it does
          // not stop there.
          padding: EdgeInsets.fromLTRB(
            24,
            MediaQuery.paddingOf(context).top +
                SpineTopBar.height +
                (compact ? 4 : 16),
            24,
            compact ? 8 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                // Aligned with the idea text, which sits to the right of the
                // ribbon rail — one left edge down the whole card.
                padding: const EdgeInsets.only(left: _railWidth),
                child: BookHeader(
                  book: book,
                  saved: progress.saved,
                  compact: compact,
                  onToggleSaved: () =>
                      context.read<ProgressController>().toggleSaved(book.id),
                ),
              ),
              SizedBox(height: compact ? 18 : 28),
              Padding(
                padding: const EdgeInsets.only(left: _railWidth),
                child: ModeToggle(
                  mode: progress.mode,
                  accent: book.spineColor,
                  watchLocked: !book.watch.isAvailable,
                  onSelect: (mode) => _selectMode(context, progress, mode),
                ),
              ),
              SizedBox(height: compact ? 20 : 30),
              Expanded(
                child: _Body(
                  book: book,
                  progress: progress,
                  ideaIndex: ideaIndex,
                  isActive: widget.isActive,
                  compact: compact,
                  showRecap: _showRecap,
                  onShowRecap: () => setState(() => _showRecap = true),
                  onHideRecap: () => setState(() => _showRecap = false),
                  onSelectIdea: (index) => _selectIdea(context, progress, index),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _selectIdea(BuildContext context, BookProgress progress, int index) {
    final clamped = index.clamp(0, book.ideaCount - 1);
    if (_showRecap) setState(() => _showRecap = false);
    if (clamped == progress.ideaIndex) return;

    context.read<ProgressController>().setIdeaIndex(book.id, clamped);

    if (progress.mode == ReadingMode.listen) {
      final playback = context.read<PlaybackController>();
      // Jumping while listening keeps listening; jumping while paused stays
      // paused, cued at the new idea.
      playback.open(
        book,
        clamped,
        autoplay: playback.isPlayingBook(book.id),
        startAt: Duration.zero,
      );
    }
  }

  void _selectMode(BuildContext context, BookProgress progress, ReadingMode mode) {
    if (mode == progress.mode) return;

    context.read<ProgressController>().setMode(book.id, mode);
    final playback = context.read<PlaybackController>();

    if (mode == ReadingMode.listen) {
      // Cue the track so the transport shows a real duration immediately, but
      // don't start playing until asked.
      playback.open(book, progress.ideaIndex);
    } else {
      playback.pause();
    }
  }
}

/// The light drifts at a fraction of the scroll, and dims as the card leaves.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.book,
    required this.controller,
    required this.index,
  });

  final Book book;
  final PageController? controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return RepaintBoundary(child: CoverBackdrop(book: book));
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final page = controller.hasClients && controller.position.haveDimensions
              ? (controller.page ?? controller.initialPage.toDouble())
              : controller.initialPage.toDouble();
          final delta = (page - index).clamp(-1.0, 1.0);

          return CoverBackdrop(
            book: book,
            parallax: delta,
            intensity: 1 - delta.abs() * 0.55,
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.book,
    required this.progress,
    required this.ideaIndex,
    required this.isActive,
    required this.compact,
    required this.showRecap,
    required this.onShowRecap,
    required this.onHideRecap,
    required this.onSelectIdea,
  });

  final Book book;
  final BookProgress progress;
  final int ideaIndex;
  final bool isActive;
  final bool compact;
  final bool showRecap;
  final VoidCallback onShowRecap;
  final VoidCallback onHideRecap;
  final ValueChanged<int> onSelectIdea;

  @override
  Widget build(BuildContext context) {
    if (progress.mode == ReadingMode.watch && !book.watch.isAvailable) {
      return WatchPanel(
        book: book,
        notified: progress.notifyOnWatch,
        onNotify: (value) =>
            context.read<ProgressController>().setNotifyOnWatch(book.id, value),
      );
    }

    // The recap is reachable from the end of any book, finished or not.
    if (showRecap) {
      return BookRecap(
        book: book,
        compact: compact,
        finished: progress.isFinished(book.ideaCount),
        onBack: onHideRecap,
      );
    }

    final idea = book.ideaAt(ideaIndex);
    final listening = progress.mode == ReadingMode.listen;
    final onLastIdea = ideaIndex >= book.ideaCount - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            // Sideways flicks move between ideas — the gesture a phone invites,
            // with Prev/Next still there for anyone who prefers a target.
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -180) onSelectIdea(ideaIndex + 1);
              if (velocity > 180) onSelectIdea(ideaIndex - 1);
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Ribbon(
                  book: book,
                  progress: progress,
                  ideaIndex: ideaIndex,
                  isActive: isActive,
                  compact: compact,
                  onSelect: onSelectIdea,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IdeaView(
                      idea: idea,
                      index: ideaIndex,
                      total: book.ideaCount,
                      compact: compact,
                      saved: progress.isIdeaSaved(idea.id),
                      onToggleSave: () => context
                          .read<ProgressController>()
                          .toggleSavedIdea(book.id, idea.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        Padding(
          padding: const EdgeInsets.only(left: _railWidth),
          child: listening
              ? _ListenFooter(book: book, ideaIndex: ideaIndex, compact: compact)
              : ReadControls(
                  accent: book.spineColor,
                  compact: compact,
                  onShare: () =>
                      showStoryShareSheet(context, book: book, idea: idea),
                  canGoBack: ideaIndex > 0,
                  canGoForward: true,
                  // The last idea used to be a dead end. Now it opens onto the
                  // whole book — and says so, because "Recap" didn't explain
                  // itself.
                  nextLabel: onLastIdea ? 'All 5 ideas' : 'Next',
                  onPrev: () => onSelectIdea(ideaIndex - 1),
                  onNext: onLastIdea
                      ? onShowRecap
                      : () => onSelectIdea(ideaIndex + 1),
                ),
        ),
      ],
    );
  }
}

/// The ribbon fills from the playhead in Listen mode, so it subscribes to
/// playback rather than making the whole card do so.
class _Ribbon extends StatelessWidget {
  const _Ribbon({
    required this.book,
    required this.progress,
    required this.ideaIndex,
    required this.isActive,
    required this.compact,
    required this.onSelect,
  });

  final Book book;
  final BookProgress progress;
  final int ideaIndex;
  final bool isActive;
  final bool compact;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final listening = isActive && progress.mode == ReadingMode.listen;

    final fill = listening
        ? context.select<PlaybackController, double>((controller) {
            final snapshot = controller.snapshot;
            final isThisIdea =
                snapshot.bookId == book.id && snapshot.ideaIndex == ideaIndex;
            return isThisIdea ? snapshot.fraction : 0;
          })
        : 0.0;

    // Held to the top of the body at a fixed height: run full-height and it
    // stops reading as a bookmark and starts reading as a rule.
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: compact ? 168 : 196,
        child: RepaintBoundary(
          child: SpineRibbon(
            count: book.ideaCount,
            currentIndex: ideaIndex,
            currentFill: fill,
            showPlayhead: listening,
            completed: progress.completedIdeas,
            color: book.spineColor,
            onSelect: onSelect,
          ),
        ),
      ),
    );
  }
}

class _ListenFooter extends StatelessWidget {
  const _ListenFooter({
    required this.book,
    required this.ideaIndex,
    required this.compact,
  });

  final Book book;
  final int ideaIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final idea = book.ideaAt(ideaIndex);

    final snapshot = context.select<PlaybackController, PlaybackSnapshot>((
      controller,
    ) {
      final current = controller.snapshot;
      // Before this idea is cued, show its declared length rather than zero —
      // the transport should never flash an empty duration.
      return current.trackId == idea.id
          ? current
          : PlaybackSnapshot(
              trackId: idea.id,
              bookId: book.id,
              ideaIndex: ideaIndex,
              duration: idea.duration,
              isSimulated: !idea.hasAudio,
            );
    });

    return RepaintBoundary(
      child: ListenControls(
        accent: book.spineColor,
        snapshot: snapshot,
        compact: compact,
        onShare: () => showStoryShareSheet(context, book: book, idea: idea),
        onTogglePlay: () =>
            context.read<PlaybackController>().toggle(book, ideaIndex),
        onSeekFraction: (fraction) =>
            context.read<PlaybackController>().seekFraction(fraction),
      ),
    );
  }
}
