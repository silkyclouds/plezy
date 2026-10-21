/// A programme cover from the index page.
class PsProgramme {
  final String slug;
  final String title;
  final String? posterUrl;

  const PsProgramme({required this.slug, required this.title, this.posterUrl});
}

/// One video card of a programme page or of the replay page.
class PsCard {
  final String videoId;
  final String title;
  final String showSlug;

  /// Programme name printed on the card; null when the card does not carry it.
  final String? showTitle;
  final DateTime? airDate;
  final int? durationSeconds;
  final String? theme;
  final String imageUrl;

  /// The `eN` counter in the episode URL. The site reuses it unevenly, so it only tells whether a
  /// programme numbers its episodes at all.
  final int? siteNumber;

  const PsCard({
    required this.videoId,
    required this.title,
    required this.showSlug,
    required this.imageUrl,
    this.showTitle,
    this.airDate,
    this.durationSeconds,
    this.theme,
    this.siteNumber,
  });
}

/// What the "load more" call of a programme page needs to ask for the next batch.
class PsPaging {
  final String termId;
  final int limit;
  final String nonce;
  final String action;
  final int total;

  const PsPaging({
    required this.termId,
    required this.limit,
    required this.nonce,
    required this.action,
    required this.total,
  });
}

/// A programme page: header facts, the first batch of cards and how to ask for more.
class PsShowPage {
  final String? title;
  final String? summary;
  final String? backdropUrl;
  final List<PsCard> cards;
  final PsPaging? paging;

  const PsShowPage({this.title, this.summary, this.backdropUrl, this.cards = const [], this.paging});
}
