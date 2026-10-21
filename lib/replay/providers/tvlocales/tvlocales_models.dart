/// A show as listed on a station's index page.
class TvShowCard {
  final String slug;
  final String title;
  final String? imageUrl;

  const TvShowCard({required this.slug, required this.title, this.imageUrl});
}

/// A season of a show, as the station site filters its episode list.
class TvSeasonLink {
  /// Value that selects the season in the site's filter.
  final String facet;
  final String label;

  const TvSeasonLink({required this.facet, required this.label});
}

/// An episode as listed on a show page.
class TvEpisodeCard {
  /// Path of the episode on the station site, after the show slug.
  final String path;
  final String title;
  final DateTime? airDate;
  final int? durationSeconds;
  final String? imageUrl;

  const TvEpisodeCard({required this.path, required this.title, this.airDate, this.durationSeconds, this.imageUrl});
}

/// One page of a show: its header, its season filter and a slice of its episodes.
class TvShowPage {
  final String title;
  final String? summary;
  final String? posterUrl;
  final String? backdropUrl;
  final List<TvSeasonLink> seasons;
  final List<TvEpisodeCard> episodes;

  /// Whether the site offers a further slice of episodes.
  final bool hasNext;

  const TvShowPage({
    required this.title,
    this.summary,
    this.posterUrl,
    this.backdropUrl,
    this.seasons = const [],
    this.episodes = const [],
    this.hasNext = false,
  });
}

/// What an episode page says about its video.
class TvEpisodePage {
  /// Freecaster id of the video; null for an article that has no video.
  final String? videoId;
  final String? title;
  final String? showName;
  final String? summary;
  final String? imageUrl;
  final DateTime? airDate;
  final int? durationSeconds;

  const TvEpisodePage({
    this.videoId,
    this.title,
    this.showName,
    this.summary,
    this.imageUrl,
    this.airDate,
    this.durationSeconds,
  });
}
