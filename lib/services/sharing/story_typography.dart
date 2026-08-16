/// The idea title, split so its terminal period can be coloured on its own.
///
/// A story card colours the closing dot in brand gold, independent of the
/// rest of the title — Spine's own full-stop mark. A title that doesn't
/// already end in one gets a period appended, so the mark appears on every
/// card rather than only the titles that happen to already end in one.
class SplitTitle {
  const SplitTitle({required this.body, required this.dot});

  final String body;

  /// Always `"."` in the MVP; kept as a field rather than a literal at the
  /// call site so a future title ending in `?` or `!` could carry its own
  /// mark through the same mechanism.
  final String dot;

  static SplitTitle of(String title) {
    final trimmed = title.trimRight();
    if (trimmed.isEmpty) return const SplitTitle(body: '', dot: '.');

    if (trimmed.endsWith('.')) {
      return SplitTitle(body: trimmed.substring(0, trimmed.length - 1), dot: '.');
    }
    return SplitTitle(body: trimmed, dot: '.');
  }
}
