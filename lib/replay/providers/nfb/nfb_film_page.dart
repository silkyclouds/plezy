import '../../model/replay_title.dart';
import 'nfb_ids.dart';
import 'nfb_images.dart';
import 'nfb_page_data.dart';
import 'nfb_values.dart';

/// Reads a film or episode page. Returns null when the page carries neither structured data nor a data layer, which
/// is what a removed film or a redesigned page looks like.
ReplayTitle? nfbTitleFromFilmPage(String html, {required String slug}) {
  final work = nfbJsonLd(html).where((b) => nfbHasType(b, 'Movie') || nfbHasType(b, 'Episode')).firstOrNull;
  final layer = nfbDataLayer(html);
  final title = nfbNonEmpty(work?['name']) ?? nfbNonEmpty(layer.fields['nfb_version_title']);
  if (title == null) return null;

  final isEpisode = work != null && nfbHasType(work, 'Episode');
  final series = isEpisode && work['partofSeries'] is Map ? work['partofSeries'] as Map : null;
  final season = isEpisode && work['partofSeason'] is Map ? work['partofSeason'] as Map : null;
  final showSlug = nfbSeriesSlugFromUrl(nfbNonEmpty(series?['url']));
  final seasonNumber = nfbInt(season?['seasonNumber']);
  final thumbnail = nfbImageFromUrl(_first(work?['thumbnailUrl']));
  final image = nfbImageFromUrl(nfbNonEmpty(work?['image']));

  return ReplayTitle(
    ref: nfbRef(slug),
    kind: isEpisode ? ReplayKind.episode : ReplayKind.movie,
    title: title,
    summary: nfbText(work?['description']),
    posterUrl: image ?? thumbnail,
    backdropUrl: thumbnail ?? image,
    durationSeconds: layer.durationSeconds ?? nfbIsoSeconds(work?['duration']),
    year: layer.year ?? nfbInt(work?['dateCreated']),
    genres: layer.categories.isNotEmpty ? layer.categories : _names(work?['genre']),
    directors: _names(work?['director']),
    seasonNumber: seasonNumber,
    episodeNumber: isEpisode ? nfbInt(work['episodeNumber']) : null,
    showRef: showSlug == null ? null : nfbShowRef(showSlug),
    showTitle: nfbNonEmpty(series?['name']),
    seasonRef: showSlug == null || seasonNumber == null ? null : nfbSeasonRef(showSlug, seasonNumber),
  );
}

String? _first(Object? value) => nfbNonEmpty(value is List ? value.firstOrNull : value);

/// Names in a field that is a string, a list of strings, a person object or a list of persons.
List<String> _names(Object? value) {
  final entries = value is List ? value : [value];
  return [for (final entry in entries) ?nfbNonEmpty(entry is Map ? entry['name'] : entry)];
}
