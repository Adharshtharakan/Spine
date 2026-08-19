/// Splits an idea's body into the units a reader can keep.
///
/// A sentence is the right grain for a highlight: a word is too small to mean
/// anything on its own, and the whole idea is already what "save" keeps.
abstract final class Sentences {
  /// Splits on sentence-ending punctuation followed by a space.
  ///
  /// Deliberately simple. Spine's bodies are written in-house in plain prose —
  /// no citations, no abbreviations like "e.g." mid-sentence — so the cases a
  /// heavier parser would earn its keep on don't occur, and a wrong split here
  /// is visible in the app rather than silent.
  static List<String> of(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const [];

    final sentences = <String>[];
    final buffer = StringBuffer();

    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      buffer.write(char);

      if (!_terminators.contains(char)) continue;

      // Run past a closing quote or bracket so punctuation stays with its
      // sentence rather than opening the next one.
      var end = i + 1;
      while (end < trimmed.length && _trailing.contains(trimmed[end])) {
        buffer.write(trimmed[end]);
        end++;
      }

      final atEnd = end >= trimmed.length;
      if (atEnd || trimmed[end] == ' ' || trimmed[end] == '\n') {
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) sentences.add(sentence);
        buffer.clear();
        i = end;
      } else {
        i = end - 1;
      }
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) sentences.add(tail);

    return List.unmodifiable(sentences);
  }

  static const _terminators = {'.', '!', '?'};
  static const _trailing = {'"', '”', "'", '’', ')', ']'};
}
