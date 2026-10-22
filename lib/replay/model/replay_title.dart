import 'replay_ref.dart';

/// What a title is, independent of the broadcaster's own vocabulary.
enum ReplayKind { movie, show, season, episode, clip }

/// Whether a title can be played by this app right now.
///
/// Everything except [playable] is a reason shown to the user instead of a
/// player that fails to start.
enum ReplayAvailability {
  playable,
  geoBlocked,
  drmProtected,
  loginRequired,
  expired,
  upcoming,
  timeSlotRestricted,
  unknown,
}

/// A card in a rail, a show, a season or an episode, as a broadcaster describes it.
class ReplayTitle {
  final ReplayRef ref;
  final ReplayKind kind;
  final String title;
  final String? subtitle;
  final String? summary;

  /// Portrait artwork (2:3). Falls back to [backdropUrl] when the source has one image only.
  final String? posterUrl;

  /// Landscape artwork (16:9).
  final String? backdropUrl;
  final String? logoUrl;
  final int? durationSeconds;
  final int? year;
  final List<String> genres;
  final List<String> directors;
  final List<String> cast;
  final String? contentRating;
  final DateTime? airDate;
  final DateTime? availableUntil;
  final ReplayAvailability availability;

  /// Position of an episode in its season, and of a season in its show.
  final int? seasonNumber;
  final int? episodeNumber;

  /// Number of seasons (shows) or episodes (seasons), when the source says.
  final int? childCount;

  /// The show this season or episode belongs to.
  final ReplayRef? showRef;
  final String? showTitle;

  /// The season this episode belongs to.
  final ReplayRef? seasonRef;

  const ReplayTitle({
    required this.ref,
    required this.kind,
    required this.title,
    this.subtitle,
    this.summary,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.durationSeconds,
    this.year,
    this.genres = const [],
    this.directors = const [],
    this.cast = const [],
    this.contentRating,
    this.airDate,
    this.availableUntil,
    this.availability = ReplayAvailability.playable,
    this.seasonNumber,
    this.episodeNumber,
    this.childCount,
    this.showRef,
    this.showTitle,
    this.seasonRef,
  });

  bool get isPlayable => kind == ReplayKind.movie || kind == ReplayKind.episode || kind == ReplayKind.clip;

  /// This title with every field it lacks taken from [seen], an earlier sighting of the same title. Broadcaster pages
  /// often carry less than their listings (no pictures, no show or season), so the richer record fills the gaps.
  ReplayTitle filledFrom(ReplayTitle seen) => ReplayTitle(
    ref: ref,
    kind: kind,
    title: title,
    subtitle: subtitle ?? seen.subtitle,
    summary: summary ?? seen.summary,
    posterUrl: posterUrl ?? seen.posterUrl,
    backdropUrl: backdropUrl ?? seen.backdropUrl,
    logoUrl: logoUrl ?? seen.logoUrl,
    durationSeconds: durationSeconds ?? seen.durationSeconds,
    year: year ?? seen.year,
    genres: genres.isEmpty ? seen.genres : genres,
    directors: directors.isEmpty ? seen.directors : directors,
    cast: cast.isEmpty ? seen.cast : cast,
    contentRating: contentRating ?? seen.contentRating,
    airDate: airDate ?? seen.airDate,
    availableUntil: availableUntil ?? seen.availableUntil,
    availability: availability,
    seasonNumber: seasonNumber ?? seen.seasonNumber,
    episodeNumber: episodeNumber ?? seen.episodeNumber,
    childCount: childCount ?? seen.childCount,
    showRef: showRef ?? seen.showRef,
    showTitle: showTitle ?? seen.showTitle,
    seasonRef: seasonRef ?? seen.seasonRef,
  );
}

/// A titled row of cards, such as "Most viewed" or "Last chance".
class ReplayRail {
  final String id;
  final String title;
  final List<ReplayTitle> titles;

  /// Browse id to open for "see all"; null when the row is complete.
  final String? moreBrowseId;

  const ReplayRail({required this.id, required this.title, required this.titles, this.moreBrowseId});
}

/// One page of a flat listing.
class ReplayPage {
  final List<ReplayTitle> titles;
  final int totalCount;

  const ReplayPage({required this.titles, required this.totalCount});
}

/// A browseable section of a broadcaster, such as Series or Documentaries.
class ReplayCategory {
  final String id;
  final String title;

  const ReplayCategory({required this.id, required this.title});
}
