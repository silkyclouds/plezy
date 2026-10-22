/// One dated recording as any of LRT's feeds describes it. Feeds differ in what they carry, so most fields are optional.
class LrtRecording {
  final String postId;
  final String title;
  final String? subtitle;
  final String? summary;

  /// Absolute picture URL with a `{WxH}` placeholder for the size.
  final String? imageTemplate;
  final DateTime? published;
  final int? durationSeconds;
  final String? showTitle;
  final String? showSlug;
  final String? seasonSlug;
  final String? ageRating;
  final DateTime? availableUntil;
  final bool isMovie;

  const LrtRecording({
    required this.postId,
    required this.title,
    this.subtitle,
    this.summary,
    this.imageTemplate,
    this.published,
    this.durationSeconds,
    this.showTitle,
    this.showSlug,
    this.seasonSlug,
    this.ageRating,
    this.availableUntil,
    this.isMovie = false,
  });

  /// This recording with [seconds] as its length, unless it already has one.
  LrtRecording withDuration(int? seconds) {
    if (seconds == null || durationSeconds != null) return this;
    return LrtRecording(
      postId: postId,
      title: title,
      subtitle: subtitle,
      summary: summary,
      imageTemplate: imageTemplate,
      published: published,
      durationSeconds: seconds,
      showTitle: showTitle,
      showSlug: showSlug,
      seasonSlug: seasonSlug,
      ageRating: ageRating,
      availableUntil: availableUntil,
      isMovie: isMovie,
    );
  }
}

/// A programme season. LRT seasons are calendar years, so the title is a year such as `2026` or `2024-2`.
class LrtSeason {
  final String id;
  final String title;
  final String slug;

  const LrtSeason({required this.id, required this.title, required this.slug});
}

/// A programme as the A to Z index or a search hit names it.
class LrtProgramme {
  final String slug;
  final String title;
  final String? imageTemplate;

  const LrtProgramme({required this.slug, required this.title, this.imageTemplate});
}

/// What a programme page carries: its description, its seasons and the newest recordings.
class LrtShowPage {
  final String slug;
  final String title;
  final String? summary;
  final String? imageTemplate;
  final List<LrtSeason> seasons;
  final List<LrtRecording> episodes;

  /// Recordings in the whole programme, as the page counts them.
  final int? episodeTotal;

  const LrtShowPage({
    required this.slug,
    required this.title,
    required this.seasons,
    required this.episodes,
    this.summary,
    this.imageTemplate,
    this.episodeTotal,
  });
}

/// One page of search hits.
class LrtSearchPage {
  final int total;
  final List<LrtRecording> recordings;
  final List<LrtProgramme> programmes;

  const LrtSearchPage({required this.total, required this.recordings, required this.programmes});

  static const empty = LrtSearchPage(total: 0, recordings: [], programmes: []);
}
