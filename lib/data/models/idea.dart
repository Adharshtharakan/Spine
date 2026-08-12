/// One of the five ideas that make up a book on Spine.
class Idea {
  const Idea({
    required this.id,
    required this.order,
    required this.title,
    required this.body,
    required this.duration,
    this.audioRef,
  });

  final String id;

  /// Zero-based position within the book.
  final int order;

  final String title;
  final String body;

  /// How long the narrated version of this idea runs. Also drives the
  /// simulated fallback when no audio file is attached yet.
  final Duration duration;

  /// Where the narration lives. One of:
  ///   `asset:assets/audio/<book>/01.wav`  — bundled with the app
  ///   `https://…`                          — cloud-hosted, cached on first play
  ///   `null`                               — not recorded yet
  final String? audioRef;

  bool get hasAudio => audioRef != null && audioRef!.isNotEmpty;

  factory Idea.fromJson(Map<String, dynamic> json, {required int order}) {
    return Idea(
      id: json['id'] as String? ?? 'idea-$order',
      order: json['order'] as int? ?? order,
      title: json['title'] as String,
      body: json['body'] as String,
      duration: Duration(
        milliseconds: ((json['seconds'] as num?)?.toDouble() ?? 0) * 1000 ~/ 1,
      ),
      audioRef: json['audio'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'title': title,
    'body': body,
    'seconds': duration.inMilliseconds / 1000,
    if (audioRef != null) 'audio': audioRef,
  };
}
