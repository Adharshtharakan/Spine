/// What an ad card renders. Deliberately editorial and minimal — an ad on
/// Spine is a full card in the house style, not a banner glued to a book.
class AdCreative {
  const AdCreative({
    required this.id,
    required this.sponsor,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    this.imageUrl,
    this.destination,
    this.isTest = false,
  });

  final String id;
  final String sponsor;
  final String headline;
  final String body;
  final String ctaLabel;
  final String? imageUrl;
  final String? destination;

  /// Test creatives always render the "TEST AD" marker, so a placeholder can
  /// never be mistaken for live inventory in a build review.
  final bool isTest;
}
