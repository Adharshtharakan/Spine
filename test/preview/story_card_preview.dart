import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/book.dart';
import 'package:spine/data/models/idea.dart';
import 'package:spine/data/models/story_template.dart';
import 'package:spine/ui/sharing/story_card.dart';

import 'render_preview.dart';

/// Renders the shareable story card at full export size, so its typography can
/// be judged without pushing a build to a phone and posting to Instagram.
///
///     flutter test test/preview/story_card_preview.dart --update-goldens
///
/// Like the rest of `test/preview`, this asserts nothing — see
/// `render_preview.dart`.
void main() {
  setUpAll(loadRealFonts);

  final book = Book.fromJson(const {
    'id': 'how-to-win-friends',
    // The longest title and one of the longest author strings in the
    // catalogue — if the layout survives these it survives all 25.
    'title': 'How to Win Friends and Influence People',
    'author': 'Brown, Roediger & McDaniel',
    'spineColor': '#B4703C',
    'blurb': 'x',
    'ideas': [
      {'id': 'i1', 'title': 'The Obstacle Becomes the Path', 'body': 'x'},
    ],
  });

  final shortIdea = Idea.fromJson(const {
    'id': 'i2',
    'title': 'Never miss twice',
    'body': 'x',
  }, order: 0);

  for (final template in StoryTemplates.all) {
    testWidgets('story card — template ${template.id}', (tester) async {
      // The card lays out at its own fixed size; the surface only has to be
      // big enough not to clip it.
      tester.view.physicalSize = StoryCard.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final card = MediaQuery(
        data: const MediaQueryData(),
        child: StoryCard(
          // Alternates so both a short title and the longest one get seen.
          idea: template.id.isEven ? shortIdea : book.ideaAt(0),
          book: book,
          template: template,
        ),
      );

      await tester.pumpWidget(card);

      // Asset images decode off the test's fake-async clock, so without this
      // every background falls through to its errorBuilder and the preview
      // shows a blank card — exactly the thing it exists to rule out.
      await tester.runAsync(() async {
        for (final asset in [
          template.backgroundAsset,
          'assets/story/bookmark.png',
        ]) {
          await precacheImage(AssetImage(asset), tester.element(find.byType(StoryCard)));
        }
      });

      await tester.pumpWidget(card);
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StoryCard),
        matchesGoldenFile('output/story_card_${template.id}.png'),
      );
    });
  }
}
