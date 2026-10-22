import '../../model/replay_title.dart';
import 'nfb_ids.dart';
import 'nfb_images.dart';
import 'nfb_values.dart';

/// Maps one film of the paged catalogue to a [ReplayTitle], or null for works that cannot be streamed for free.
///
/// The catalogue answers for the caller's own address, so `geoblocked` already reflects the viewer's country.
/// Episodes of a series are left out of listings, where their show stands for them, unless [includeEpisodes].
ReplayTitle? nfbTitleFromFilm(Map<String, dynamic> item, {String? genre, bool includeEpisodes = false, DateTime? now}) {
  final slug = nfbNonEmpty(item['slug']);
  final title = nfbNonEmpty(item['title']);
  if (slug == null || title == null) return null;

  final seriesSlug = _seriesOf(item);
  if (seriesSlug != null && !includeEpisodes) return null;

  final availability = _availability(item, now ?? DateTime.now());
  if (availability == null) return null;

  final thumbnail = nfbImageFromPath(item['thumbnail']);
  final jacket = nfbImageFromPath(item['jacket']);
  final soon = nfbDate(item['coming_soon']);
  return ReplayTitle(
    ref: nfbRef(slug),
    kind: seriesSlug == null ? ReplayKind.movie : ReplayKind.episode,
    title: title,
    summary: nfbText(item['description']),
    posterUrl: jacket ?? thumbnail,
    backdropUrl: thumbnail ?? jacket,
    durationSeconds: _seconds(item['duration']),
    year: _year(item['year']),
    genres: genre == null ? const [] : [genre],
    directors: _directors(item['directors']),
    contentRating: nfbNonEmpty(item['rating']),
    airDate: soon,
    availableUntil: nfbDate(item['leaving_soon']),
    availability: availability,
    showRef: seriesSlug == null ? null : nfbShowRef(seriesSlug),
  );
}

/// Titles of one catalogue page, in the order the catalogue gave them.
List<ReplayTitle> nfbTitlesFromFilms(
  Map<String, dynamic> body, {
  String? genre,
  bool includeEpisodes = false,
  DateTime? now,
}) {
  final items = body['items'];
  if (items is! List) return const [];
  return [
    for (final raw in items)
      if (raw is Map<String, dynamic>) ?nfbTitleFromFilm(raw, genre: genre, includeEpisodes: includeEpisodes, now: now),
  ];
}

/// Number of works the catalogue counts for a page body.
int nfbTotal(Map<String, dynamic> body, int fallback) =>
    (((body['meta'] as Map?)?['pagination'] as Map?)?['total'] as num?)?.toInt() ?? fallback;

/// A series of the catalogue as a show card.
ReplayTitle? nfbShowFromSeries(Map<String, dynamic> item) {
  final slug = nfbNonEmpty(item['slug']);
  final title = nfbNonEmpty(item['title']);
  if (slug == null || title == null) return null;
  final thumbnail = nfbImageFromPath(item['thumbnail']);
  final jacket = nfbImageFromPath(item['jacket']);
  return ReplayTitle(
    ref: nfbShowRef(slug),
    kind: ReplayKind.show,
    title: title,
    summary: nfbText(item['description']) ?? nfbText(item['tagline']),
    posterUrl: jacket ?? thumbnail,
    backdropUrl: thumbnail ?? jacket,
    durationSeconds: _seconds(item['duration']),
    year: _year(item['year']),
    directors: _directors(item['directors']),
    contentRating: nfbNonEmpty(item['rating']),
    childCount: (item['seasons_count'] as num?)?.toInt(),
  );
}

List<ReplayTitle> nfbShowsFromSeries(Map<String, dynamic> body) {
  final items = body['items'];
  if (items is! List) return const [];
  return [
    for (final raw in items)
      if (raw is Map<String, dynamic>) ?nfbShowFromSeries(raw),
  ];
}

ReplayAvailability? _availability(Map<String, dynamic> item, DateTime now) {
  final soon = nfbDate(item['coming_soon']);
  if (soon != null && soon.isAfter(now)) return ReplayAvailability.upcoming;
  final offer = item['availability'];
  if (offer is Map && offer['is_public'] == false) return null;
  final until = nfbDate(item['leaving_soon']);
  if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
  return item['geoblocked'] == true ? ReplayAvailability.geoBlocked : ReplayAvailability.playable;
}

String? _seriesOf(Map<String, dynamic> item) {
  final parts = item['part_of'];
  if (parts is! List) return null;
  for (final part in parts.whereType<Map<String, dynamic>>()) {
    if (part['category'] == 'series') return nfbNonEmpty(part['slug']);
  }
  return null;
}

int? _seconds(Object? duration) {
  final seconds = duration is num ? duration.round() : 0;
  return seconds > 0 ? seconds : null;
}

int? _year(Object? year) => year is num && year > 0 ? year.toInt() : null;

List<String> _directors(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final d in raw.whereType<Map<String, dynamic>>())
      ?nfbNonEmpty('${d['first_name'] ?? ''} ${d['last_name'] ?? ''}'),
  ];
}
