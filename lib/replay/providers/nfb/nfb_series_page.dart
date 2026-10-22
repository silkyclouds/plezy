import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nfb_ids.dart';
import 'nfb_images.dart';
import 'nfb_page_data.dart';
import 'nfb_values.dart';

/// One season of a series page with its episodes.
class NfbSeason {
  final ReplayTitle season;
  final List<ReplayTitle> episodes;

  const NfbSeason(this.season, this.episodes);
}

/// A series page read into the show, its seasons and their episodes.
class NfbSeries {
  final ReplayTitle show;
  final List<NfbSeason> seasons;

  const NfbSeries(this.show, this.seasons);
}

/// Reads the series structured data. Returns null when the page has none, such as a removed series.
///
/// A series page lists its seasons with the episodes inside. The site names a lone season "Unique Season" and
/// sometimes starts at episode 0 or repeats numbers, so names and numbers are normalised here. A series that lists
/// no season still gets one, so every show has the same two levels.
NfbSeries? nfbParseSeriesPage(String html, {required String slug}) {
  final data = nfbJsonLd(html).where((b) => nfbHasType(b, 'CreativeWorkSeries')).firstOrNull;
  final name = nfbNonEmpty(data?['name']);
  if (data == null || name == null) return null;

  final thumbnail = nfbImageFromUrl(_first(data['thumbnail_url']));
  final jacket = nfbImageFromUrl(nfbNonEmpty(data['image']));
  final entries = [if (data['containsSeason'] case final List seasons) ...seasons.whereType<Map<String, dynamic>>()];
  final show = ReplayTitle(
    ref: nfbShowRef(slug),
    kind: ReplayKind.show,
    title: name,
    summary: nfbText(data['description']),
    posterUrl: jacket ?? thumbnail,
    backdropUrl: thumbnail ?? jacket,
    year: nfbInt(data['startDate']),
    directors: [
      for (final d in (data['directors'] as List? ?? const []).whereType<Map<String, dynamic>>())
        ?nfbNonEmpty(d['name']),
    ],
    childCount: entries.isEmpty ? 1 : entries.length,
  );
  return NfbSeries(
    show,
    entries.isEmpty ? [NfbSeason(_season(show, slug, 1, name, 0), const [])] : _seasons(entries, show, slug),
  );
}

List<NfbSeason> _seasons(List<Map<String, dynamic>> entries, ReplayTitle show, String slug) {
  final numbers = _numbers([for (final e in entries) nfbInt(e['season_number'])]);
  final seasons = <NfbSeason>[];
  for (var i = 0; i < entries.length; i++) {
    final episodes = _episodes(entries[i], show, nfbSeasonRef(slug, numbers[i]), numbers[i]);
    final title = _seasonName(entries[i], numbers[i]);
    seasons.add(NfbSeason(_season(show, slug, numbers[i], title, episodes.length), episodes));
  }
  seasons.sort((a, b) => a.season.seasonNumber!.compareTo(b.season.seasonNumber!));
  return seasons;
}

ReplayTitle _season(ReplayTitle show, String slug, int number, String title, int count) => ReplayTitle(
  ref: nfbSeasonRef(slug, number),
  kind: ReplayKind.season,
  title: title,
  posterUrl: show.posterUrl,
  backdropUrl: show.backdropUrl,
  seasonNumber: number,
  childCount: count,
  showRef: show.ref,
  showTitle: show.title,
);

String _seasonName(Map<String, dynamic> entry, int number) {
  final name = nfbNonEmpty(entry['name']);
  return name == null || name.toLowerCase() == 'unique season' ? 'Season $number' : name;
}

List<ReplayTitle> _episodes(Map<String, dynamic> season, ReplayTitle show, ReplayRef seasonRef, int seasonNumber) {
  final entries = [
    for (final e in (season['episodes'] as List? ?? const []).whereType<Map<String, dynamic>>())
      if (nfbSlugFromUrl(nfbNonEmpty(e['url'])) != null && nfbNonEmpty(e['name']) != null) e,
  ];
  final numbers = _numbers([for (final e in entries) nfbInt(e['episodeNumber'])]);
  final episodes = [
    for (var i = 0; i < entries.length; i++)
      ReplayTitle(
        ref: nfbRef(nfbSlugFromUrl(nfbNonEmpty(entries[i]['url']))!),
        kind: ReplayKind.episode,
        title: _withoutShowName(nfbNonEmpty(entries[i]['name'])!, show.title),
        posterUrl: show.posterUrl,
        backdropUrl: show.backdropUrl,
        seasonNumber: seasonNumber,
        episodeNumber: numbers[i],
        showRef: show.ref,
        showTitle: show.title,
        seasonRef: seasonRef,
      ),
  ];
  episodes.sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
  return episodes;
}

/// The numbers the site gave, kept when every one is present and distinct. Otherwise the position in the list stands
/// in: a missing or repeated number would make two entries indistinguishable in the player queue.
List<int> _numbers(List<int?> given) {
  final present = given.whereType<int>().toList();
  final usable = present.length == given.length && present.toSet().length == present.length;
  return usable ? present : [for (var i = 0; i < given.length; i++) i + 1];
}

/// "Show - Episode" becomes "Episode" when the site repeats the show name in every episode title.
String _withoutShowName(String title, String show) {
  final prefix = RegExp('^${RegExp.escape(show)}\\s*[-–—:]\\s*', caseSensitive: false);
  final rest = title.replaceFirst(prefix, '').trim();
  return rest.isEmpty ? title : rest;
}

String? _first(Object? value) => nfbNonEmpty(value is List ? value.firstOrNull : value);
