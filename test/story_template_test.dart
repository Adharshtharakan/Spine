import 'package:flutter_test/flutter_test.dart';
import 'package:spine/data/models/story_template.dart';
import 'package:spine/services/sharing/story_typography.dart';

void main() {
  group('StoryTemplates', () {
    test('ships exactly six templates, ids 1 through 6', () {
      expect(StoryTemplates.all, hasLength(6));
      expect(StoryTemplates.all.map((t) => t.id), [1, 2, 3, 4, 5, 6]);
    });

    test('every template points at its own background asset', () {
      final assets = StoryTemplates.all.map((t) => t.backgroundAsset).toSet();
      expect(assets, hasLength(6), reason: 'two templates share a background');
    });

    test('is deterministic — the same idea always gets the same template', () {
      final first = StoryTemplates.forIdea('atomic-habits-1');
      final second = StoryTemplates.forIdea('atomic-habits-1');
      expect(first.id, second.id);
    });

    test('spreads across different ideas rather than collapsing to one', () {
      final ids = {
        for (var i = 0; i < 30; i++) StoryTemplates.forIdea('idea-$i').id,
      };
      expect(ids.length, greaterThan(1));
    });

    test('never picks outside the registered templates', () {
      for (var i = 0; i < 50; i++) {
        final template = StoryTemplates.forIdea('book-$i-idea-${i * 3}');
        expect(StoryTemplates.all.map((t) => t.id), contains(template.id));
      }
    });

    test('lightText agrees with how bright the title colour actually is', () {
      // The card derives its scrim, wordmark and footer polarity from
      // lightText while the title uses mainTitleColor, so the two drifting
      // apart would put white type on a white scrim. This catches that.
      for (final template in StoryTemplates.all) {
        final luminance = template.mainTitleColor.computeLuminance();
        expect(
          template.lightText,
          luminance > 0.5,
          reason:
              'template ${template.id} declares lightText=${template.lightText} '
              'but its title colour has luminance $luminance',
        );
      }
    });
  });

  group('SplitTitle', () {
    test('separates an existing terminal period from the body', () {
      final split = SplitTitle.of('Never miss twice.');
      expect(split.body, 'Never miss twice');
      expect(split.dot, '.');
    });

    test('appends a period to a title that lacks one', () {
      final split = SplitTitle.of('Identity Over Outcome');
      expect(split.body, 'Identity Over Outcome');
      expect(split.dot, '.');
    });

    test('trims trailing whitespace before checking for a period', () {
      final split = SplitTitle.of('The Four Laws.   ');
      expect(split.body, 'The Four Laws');
      expect(split.dot, '.');
    });

    test('recombining body and dot reproduces a normalised title', () {
      for (final title in ['1% Better', 'Never Miss Twice.', 'Seek Wealth, Not Money']) {
        final split = SplitTitle.of(title);
        expect('${split.body}${split.dot}', title.trimRight().endsWith('.') ? title.trimRight() : '$title.');
      }
    });

    test('an empty title does not throw', () {
      final split = SplitTitle.of('');
      expect(split.body, '');
      expect(split.dot, '.');
    });
  });
}
