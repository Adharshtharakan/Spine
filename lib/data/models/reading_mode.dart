/// The three ways to take in a book on Spine.
enum ReadingMode {
  read('read'),
  listen('listen'),
  watch('watch');

  const ReadingMode(this.id);

  final String id;

  String get label => id.toUpperCase();

  static ReadingMode fromId(String? id) {
    return ReadingMode.values.firstWhere(
      (mode) => mode.id == id,
      orElse: () => ReadingMode.read,
    );
  }
}
