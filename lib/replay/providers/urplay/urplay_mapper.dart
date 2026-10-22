import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'urplay_images.dart';
import 'urplay_numbering.dart';
import 'urplay_refs.dart';

/// Where an item was found, so an episode knows its show and season.
class UrContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  /// The item sits in a list of episodes that are not out yet.
  final bool upcoming;

  const UrContext({this.show, this.showTitle, this.season, this.seasonNumber, this.upcoming = false});

  static const none = UrContext();

  UrContext asUpcoming() =>
      UrContext(show: show, showTitle: showTitle, season: season, seasonNumber: seasonNumber, upcoming: true);
}

/// Maps one catalogue item to a [ReplayTitle]: a `series` becomes a show, a `program` an episode or a standalone
/// film. Anything else (UR adds product types now and then) is skipped.
ReplayTitle? urTitleFromItem(
  Map<String, dynamic> item, {
  UrContext context = UrContext.none,
  int? seasonCount,
  DateTime? now,
}) {
  final id = item['id']?.toString();
  final title = _nonEmpty(item['title'] as String?);
  if (id == null || title == null) return null;
  return switch (item['productType']) {
    'series' => _show(item, id, title, seasonCount, now ?? DateTime.now()),
    'program' => _program(item, id, title, context, now ?? DateTime.now()),
    _ => null,
  };
}

/// Items of a search or listing page. A show listed under several of its seasons is kept once, as its newest season.
List<ReplayTitle> urTitlesFromResults(Map<String, dynamic> page, {DateTime? now}) {
  final results = page['results'];
  if (results is! List) return const [];
  final seen = <ReplayRef>{};
  final newestSeason = <String, ({String id, int season})>{};
  for (final item in results.whereType<Map<String, dynamic>>()) {
    if (item['productType'] != 'series') continue;
    final key = urTitleKey(item['title'] as String? ?? '');
    final season = urSeasonFromDescription(item['description'] as String?) ?? 1;
    final best = newestSeason[key];
    if (best == null || season > best.season) newestSeason[key] = (id: '${item['id']}', season: season);
  }
  final titles = <ReplayTitle>[];
  for (final item in results.whereType<Map<String, dynamic>>()) {
    if (_isOlderSeason(item, newestSeason)) continue;
    final title = urTitleFromItem(item, now: now);
    if (title != null && seen.add(title.ref)) titles.add(title);
  }
  return titles;
}

bool _isOlderSeason(Map<String, dynamic> item, Map<String, ({String id, int season})> newest) {
  if (item['productType'] != 'series') return false;
  return newest[urTitleKey(item['title'] as String? ?? '')]?.id != '${item['id']}';
}

/// A season of a show, from the series entry that stands for it.
ReplayTitle urSeasonFromSeries(
  Map<String, dynamic> series, {
  required String showId,
  required String showTitle,
  required int seasonNumber,
  int? episodeCount,
  DateTime? now,
}) {
  final id = '${series['id']}';
  return ReplayTitle(
    ref: urplaySeasonRef(showId, id),
    kind: ReplayKind.season,
    title: 'Säsong $seasonNumber',
    summary: _seriesSummary(series),
    posterUrl: urPosterReference(id, series['image']),
    backdropUrl: urBackdropReference(id, series['image']),
    genres: _genres(series),
    seasonNumber: seasonNumber,
    childCount: episodeCount,
    showRef: urplayShowRef(showId),
    showTitle: showTitle,
    availableUntil: _window(series)?.end,
    availability: _availability(series, now ?? DateTime.now()),
  );
}

ReplayTitle _show(Map<String, dynamic> item, String id, String title, int? seasonCount, DateTime now) => ReplayTitle(
  ref: urplayShowRef(id),
  kind: ReplayKind.show,
  title: title,
  summary: _seriesSummary(item),
  posterUrl: urPosterReference(id, item['image']),
  backdropUrl: urBackdropReference(id, item['image']),
  genres: _genres(item),
  childCount: seasonCount,
  availableUntil: _window(item)?.end,
  availability: _availability(item, now),
);

ReplayTitle _program(Map<String, dynamic> item, String id, String title, UrContext context, DateTime now) {
  final showTitle = context.showTitle ?? _nonEmpty(item['mainTitle'] as String?);
  final isEpisode = item['isSingle'] != true && showTitle != null;
  final window = _window(item);
  return ReplayTitle(
    ref: urplayProgramRef(id),
    kind: isEpisode ? ReplayKind.episode : ReplayKind.movie,
    title: title,
    summary: _nonEmpty(item['description'] as String?) ?? _nonEmpty(item['usp'] as String?),
    posterUrl: urPosterReference(id, item['image']),
    backdropUrl: urBackdropReference(id, item['image']),
    durationSeconds: (item['duration'] as num?)?.toInt(),
    genres: _genres(item),
    airDate: DateTime.tryParse(item['publishDatePublic'] as String? ?? '')?.toUtc(),
    availableUntil: window?.end,
    availability: context.upcoming ? ReplayAvailability.upcoming : _availability(item, now),
    seasonNumber: isEpisode ? context.seasonNumber : null,
    episodeNumber: isEpisode ? (item['episodeNumber'] as num?)?.toInt() : null,
    showRef: isEpisode ? context.show : null,
    showTitle: isEpisode ? showTitle : null,
    seasonRef: isEpisode ? context.season : null,
  );
}

/// The programme page of a single programme. Its labels and series block give the numbers the listings lack.
ReplayTitle? urTitleFromEpisodeInfo(Map<String, dynamic> info, {UrContext context = UrContext.none, DateTime? now}) {
  final about = info['about'];
  final id = info['id']?.toString();
  final title = _nonEmpty(info['title'] as String?);
  if (about is! Map<String, dynamic> || id == null || title == null) return null;

  final numbers = urNumbersFromLabels(info['metadataLabels']);
  final showTitle = context.showTitle ?? urSeriesTitleOfInfo(info);
  final isEpisode = about['seriesId'] != null && showTitle != null;
  final participants = _participants(about['participants']);
  return ReplayTitle(
    ref: urplayProgramRef(id),
    kind: isEpisode ? ReplayKind.episode : ReplayKind.movie,
    title: title,
    summary: _nonEmpty(about['description'] as String?),
    posterUrl: urPosterReference(id, null),
    backdropUrl: urBackdropReference(id, null),
    durationSeconds: (about['duration'] as num?)?.toInt(),
    year: (about['productionYear'] as num?)?.toInt(),
    genres: [for (final k in (about['keywords'] as List? ?? const []).take(4)) k.toString()],
    directors: [
      for (final p in participants)
        if (p.role.toLowerCase().startsWith('regi')) p.name,
    ],
    cast: [
      for (final p in participants)
        if (!p.role.toLowerCase().startsWith('regi')) p.name,
    ],
    availableUntil: _window(about)?.end,
    availability: _availability(about, now ?? DateTime.now()),
    seasonNumber: isEpisode ? (numbers.season ?? context.seasonNumber) : null,
    episodeNumber: isEpisode ? numbers.episode : null,
    showRef: isEpisode ? context.show : null,
    showTitle: isEpisode ? showTitle : null,
    seasonRef: isEpisode ? context.season : null,
  );
}

/// The title of the series a programme page belongs to, or null for a standalone programme.
String? urSeriesTitleOfInfo(Map<String, dynamic> info) {
  final product = (info['pedagogical'] is Map ? (info['pedagogical'] as Map)['product'] : null);
  final series = product is Map ? product['series'] : null;
  final fromSeries = series is Map ? _nonEmpty(series['title'] as String?) : null;
  if (fromSeries != null) return fromSeries;
  final seo = info['seoTitle'] as String?;
  final title = info['title'] as String?;
  if (seo == null || title == null || !seo.endsWith(': $title')) return null;
  return _nonEmpty(seo.substring(0, seo.length - title.length - 2));
}

({DateTime? start, DateTime? end})? _window(Map<String, dynamic> item) {
  final platforms = item['accessiblePlatforms'];
  final window = platforms is Map ? platforms['urplay'] : null;
  if (window is! Map) return null;
  return (
    start: DateTime.tryParse(window['startTime'] as String? ?? '')?.toUtc(),
    end: DateTime.tryParse(window['endTime'] as String? ?? '')?.toUtc(),
  );
}

ReplayAvailability _availability(Map<String, dynamic> item, DateTime now) {
  final window = _window(item);
  if (window == null) return ReplayAvailability.playable;
  if (window.end != null && window.end!.isBefore(now)) return ReplayAvailability.expired;
  if (window.start != null && window.start!.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}

String? _seriesSummary(Map<String, dynamic> series) {
  final description = series['description'] as String?;
  final stripped = description == null ? '' : urStripSeasonPrefix(description);
  return stripped.isNotEmpty ? stripped : _nonEmpty(series['usp'] as String?);
}

List<String> _genres(Map<String, dynamic> item) {
  final genre = _nonEmpty(item['mainGenre'] as String?);
  return genre == null ? const [] : [genre];
}

List<({String name, String role})> _participants(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final p in raw.whereType<Map<String, dynamic>>())
      if (_nonEmpty('${p['firstname'] ?? ''} ${p['lastname'] ?? ''}') case final name?)
        (name: name, role: p['role'] as String? ?? ''),
  ];
}

String? _nonEmpty(String? value) {
  final trimmed = value?.replaceAll(' ', ' ').trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
