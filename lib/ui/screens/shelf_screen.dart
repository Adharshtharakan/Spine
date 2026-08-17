import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/feed_item.dart';
import '../../services/ads/ad_provider.dart';
import '../../services/ads/native_ad_preloader.dart';
import '../../state/library_controller.dart';
import '../../state/playback_controller.dart';
import '../../state/progress_controller.dart';
import '../../state/review_controller.dart';
import '../../state/shell_controller.dart';
import '../feed/ad_slide.dart';
import '../feed/book_slide.dart';
import '../feed/review_slide.dart';
import '../feed/today_slide.dart';

/// The feed. One card per screen, vertical, snapping.
///
/// `PageView` gives real snap physics and platform-correct fling behaviour for
/// free, and only keeps the neighbouring card alive — which is what keeps the
/// feed light no matter how long the catalogue gets.
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  /// Created once the feed exists, because where the reader resumes depends on
  /// where their book landed in today's order.
  PageController? _controller;
  int _activeIndex = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  PageController _controllerFor(List<FeedItem> items) {
    final existing = _controller;
    if (existing != null) return existing;

    final lastBookId = context.read<ProgressController>().lastBookId;
    final resumeAt = lastBookId == null
        ? -1
        : items.indexWhere(
            (item) => item is BookFeedItem && item.book.id == lastBookId,
          );

    _activeIndex = resumeAt < 0 ? 0 : resumeAt;
    return _controller = PageController(initialPage: _activeIndex);
  }

  void _onPageChanged(int index, List<FeedItem> items) {
    setState(() => _activeIndex = index);

    // Audio belongs to the card you are on. Swiping away ends it rather than
    // letting a voice follow you down the feed.
    context.read<PlaybackController>().stop();

    final item = items[index];
    if (item is BookFeedItem) {
      context.read<ProgressController>().setLastBookId(item.book.id);
    }

    _warmAds(index, items);
  }

  /// How far ahead ad slots are filled. Three cards is roughly two seconds of
  /// unhurried swiping and comfortably longer than a native ad takes to load,
  /// so a slot is ready well before it is reached. One card behind is kept
  /// warm too, since scrolling back up is common and re-requesting an ad the
  /// reader just passed would both stall and waste a request.
  static const _lookAhead = 4;
  static const _lookBehind = 1;

  void _warmAds(int index, List<FeedItem> items) {
    final preloader = context.read<NativeAdPreloader?>();
    if (preloader == null) return;

    final from = (index - _lookBehind).clamp(0, items.length - 1);
    final to = (index + _lookAhead).clamp(0, items.length - 1);

    // Ads are keyed by their slot position, not their feed index — the feed
    // index of a given ad shifts as the shelf reorders between sessions.
    final positions = <int>[
      for (var i = from; i <= to; i++)
        if (items[i] case AdFeedItem(:final position)) position,
    ];
    if (positions.isEmpty) return;

    final focused = switch (items[index]) {
      AdFeedItem(:final position) => position,
      _ => null,
    };
    preloader.preload(positions, focused: focused);
  }

  void _goToBook(String bookId, List<FeedItem> items) {
    final target = items.indexWhere(
      (item) => item is BookFeedItem && item.book.id == bookId,
    );
    final controller = _controller;
    if (target < 0 || controller == null || !controller.hasClients) return;

    controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  /// A stored position can outlive the feed that produced it — the catalogue
  /// shrinks, or the ad cadence changes. Land on the last card instead of an
  /// empty viewport.
  void _clampToFeed(int length) {
    final controller = _controller;
    if (length == 0 || _activeIndex < length) return;
    if (controller == null || !controller.hasClients) return;
    controller.jumpToPage(length - 1);
  }

  /// Handles a "open this book" request coming from Search or Saved.
  void _handlePendingBook(List<FeedItem> items) {
    final shell = context.read<ShellController>();
    final bookId = shell.pendingBookId;
    if (bookId == null) return;

    final target = items.indexWhere(
      (item) => item is BookFeedItem && item.book.id == bookId,
    );
    shell.consumePendingBook();
    final controller = _controller;
    if (target < 0 || controller == null || !controller.hasClients) return;

    if ((target - _activeIndex).abs() > 2) {
      controller.jumpToPage(target);
    } else {
      controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    switch (library.status) {
      case LibraryStatus.loading:
        return const _FeedMessage(text: 'OPENING THE SHELF');
      case LibraryStatus.failed:
        return const _FeedMessage(text: 'THE SHELF IS EMPTY');
      case LibraryStatus.ready:
        break;
    }

    final items = library.feedItems;
    if (items.isEmpty) return const _FeedMessage(text: 'THE SHELF IS EMPTY');

    // Watching the shell here means a request from another tab is picked up on
    // the frame the shelf comes back into view.
    context.watch<ShellController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _clampToFeed(items.length);
      _handlePendingBook(items);
      // onPageChanged never fires for the page the feed opens on, so without
      // this the first ad slot only starts loading after a swipe — which is
      // exactly the slot most likely to be reached before it is ready.
      _warmAds(_activeIndex, items);
    });

    final controller = _controllerFor(items);

    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      onPageChanged: (index) => _onPageChanged(index, items),
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isActive = index == _activeIndex;

        return RepaintBoundary(
          child: KeyedSubtree(
            key: ValueKey(item.key),
            child: switch (item) {
              BookFeedItem(:final book) => BookSlide(
                book: book,
                isActive: isActive,
                pageController: controller,
                pageIndex: index,
              ),
              DailyIdeaFeedItem() => TodaySlide(
                item: item,
                onOpenBook: () => _goToBook(item.book.id, items),
              ),
              ReviewFeedItem() => ReviewSlide(
                item: item,
                onReviewed: () =>
                    context.read<ReviewController>().markReviewed(item.idea.id),
                onOpenBook: () => _goToBook(item.book.id, items),
              ),
              AdFeedItem() => AdSlide(
                item: item,
                provider: context.read<AdProvider>(),
                preloader: context.read<NativeAdPreloader?>(),
                isActive: isActive,
              ),
            },
          ),
        );
      },
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: SpineText.label.copyWith(color: SpineColors.parchmentDim),
      ),
    );
  }
}
