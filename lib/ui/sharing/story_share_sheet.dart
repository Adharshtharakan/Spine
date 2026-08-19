import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/spine_colors.dart';
import '../../core/theme/spine_text.dart';
import '../../data/models/book.dart';
import '../../data/models/idea.dart';
import '../../data/models/story_template.dart';
import '../../services/sharing/story_card_renderer.dart';
import '../../services/sharing/story_share_service.dart';
import '../widgets/tap_scale.dart';
import 'story_card.dart';

/// The sheet behind the share icon: Instagram, Facebook, the plain OS share
/// sheet, or the idea as text. Each option renders the card fresh and hands
/// it straight to the platform — nothing is cached between shares, since a
/// share happens once in a while, not often enough for that to matter.
Future<void> showStoryShareSheet(
  BuildContext context, {
  required Book book,
  required Idea idea,

  /// A line the reader kept. When present it becomes the card's headline —
  /// their own choice of what mattered beats the idea's title.
  String? highlight,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _StoryShareSheet(book: book, idea: idea, highlight: highlight),
  );
}

class _StoryShareSheet extends StatefulWidget {
  const _StoryShareSheet({
    required this.book,
    required this.idea,
    this.highlight,
  });

  final Book book;
  final Idea idea;
  final String? highlight;

  @override
  State<_StoryShareSheet> createState() => _StoryShareSheetState();
}

class _StoryShareSheetState extends State<_StoryShareSheet> {
  bool _busy = false;

  Future<void> _share(StoryTarget target) =>
      _run((renderer, service, file) => service.shareToStory(file, target: target));

  Future<void> _shareGeneric() =>
      _run((renderer, service, file) => service.shareGeneric(file));

  /// The plain-text version, for anywhere an image doesn't belong.
  ///
  /// Both the messenger and the navigator are resolved before the sheet pops,
  /// since this context dies with it.
  Future<void> _copyText(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final text =
        '“${widget.highlight ?? widget.idea.title}” — ${widget.book.title} '
        'by ${widget.book.author}, on Spine';

    await Clipboard.setData(ClipboardData(text: text));
    navigator.pop();

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpineColors.inkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            'Copied to clipboard',
            style: SpineText.label.copyWith(color: SpineColors.parchment),
          ),
        ),
      );
  }

  /// Uses the State's own `context` rather than one passed in, so the
  /// `mounted` checks across the awaits actually guard the context in use.
  Future<void> _run(
    Future<void> Function(
      StoryCardRenderer renderer,
      StoryShareService service,
      dynamic file,
    )
    action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);

    final renderer = context.read<StoryCardRenderer>();
    final service = context.read<StoryShareService>();
    final template = StoryTemplates.forIdea(widget.idea.id);
    final navigator = Navigator.of(context);

    try {
      // Before the capture, not during it: the renderer only waits a couple
      // of frames, which is nowhere near long enough to decode a multi-megabyte
      // background, and a card photographed mid-decode comes out without one.
      await StoryCard.precacheAssets(context, template);
      if (!mounted) return;

      final file = await renderer.capture(
        context: context,
        fileName: 'spine-${widget.idea.id}.png',
        card: StoryCard(
          idea: widget.idea,
          book: widget.book,
          template: template,
          headline: widget.highlight,
        ),
      );
      await action(renderer, service, file);
    } catch (error) {
      debugPrint('Spine: story share failed — $error');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (navigator.canPop()) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: SpineColors.inkCard,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SHARE THIS IDEA',
              style: SpineText.label.copyWith(color: SpineColors.onInk(0.5)),
            ),
            const SizedBox(height: 16),
            _ShareRow(
              icon: Icons.camera_alt_outlined,
              label: 'Instagram Stories',
              busy: _busy,
              onTap: () => _share(StoryTarget.instagram),
            ),
            _ShareRow(
              icon: Icons.facebook_outlined,
              label: 'Facebook Stories',
              busy: _busy,
              onTap: () => _share(StoryTarget.facebook),
            ),
            _ShareRow(
              icon: Icons.ios_share_rounded,
              label: 'More',
              busy: _busy,
              onTap: () => _shareGeneric(),
            ),
            _ShareRow(
              icon: Icons.content_copy_rounded,
              label: 'Copy text',
              busy: _busy,
              onTap: () => _copyText(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      enabled: !busy,
      onTap: onTap,
      semanticLabel: 'Share to $label',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: SpineColors.onInk(0.75)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: SpineText.ideaBody.copyWith(fontSize: 15),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(SpineColors.brass),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
