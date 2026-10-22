import 'orftvthek_ids.dart';
import 'orftvthek_json.dart';
import 'orftvthek_numbering.dart';

/// A show spanning more than this is split by broadcast year; a shorter one is a single season.
const _yearSplitSpan = Duration(days: 400);

/// One season of a show and the episodes that belong to it.
class OrfSeasonPlan {
  final String key;

  /// Season number, the broadcast year for year seasons, 0 for extras.
  final int number;
  final String title;
  final List<Map<String, dynamic>> episodes;

  const OrfSeasonPlan({required this.key, required this.number, required this.title, required this.episodes});
}

/// Splits the episodes of ONE profile into seasons.
///
/// ORF has no season level, so the grouping is derived, in this order:
/// 1. [profileSeason], when the profile itself is one season of a show ("Kiwi Staffel 2").
/// 2. Season markers in the episodes ("(S4/E3)", a "Staffel 3" sub-headline), when at least half carry one; the
///    rest are extras.
/// 3. The broadcast year, when the episodes span more than [_yearSplitSpan].
/// 4. One season holding everything.
List<OrfSeasonPlan> orfPlanSeasons(List<Map<String, dynamic>> episodes, {int? profileSeason}) {
  if (episodes.isEmpty) return const [];
  if (profileSeason != null) return [_numbered(profileSeason, episodes)];

  final marked = <int?>[for (final e in episodes) _seasonMarker(e)];
  final markedCount = marked.whereType<int>().length;
  if (markedCount > 0 && markedCount * 2 >= episodes.length) return _byMarker(episodes, marked);

  final dates = [for (final e in episodes) orfDate(e['date'])].whereType<DateTime>().toList()..sort();
  if (dates.length > 1 && dates.last.difference(dates.first) > _yearSplitSpan) return _byYear(episodes);

  return [OrfSeasonPlan(key: orfAllEpisodes, number: 1, title: 'Alle Folgen', episodes: episodes)];
}

OrfSeasonPlan _numbered(int number, List<Map<String, dynamic>> episodes) =>
    OrfSeasonPlan(key: orfNumberedSeasonKey(number), number: number, title: 'Staffel $number', episodes: episodes);

int? _seasonMarker(Map<String, dynamic> episode) =>
    orfTitleMarkers(orfString(episode['title']) ?? '').season ?? orfSeasonFromText(orfString(episode['sub_headline']));

List<OrfSeasonPlan> _byMarker(List<Map<String, dynamic>> episodes, List<int?> marked) {
  final groups = <int, List<Map<String, dynamic>>>{};
  final extras = <Map<String, dynamic>>[];
  for (var i = 0; i < episodes.length; i++) {
    final season = marked[i];
    if (season == null) {
      extras.add(episodes[i]);
    } else {
      groups.putIfAbsent(season, () => []).add(episodes[i]);
    }
  }
  return [
    for (final number in groups.keys.toList()..sort()) _numbered(number, groups[number]!),
    if (extras.isNotEmpty) OrfSeasonPlan(key: orfExtras, number: 0, title: 'Extras', episodes: extras),
  ];
}

List<OrfSeasonPlan> _byYear(List<Map<String, dynamic>> episodes) {
  final groups = <int, List<Map<String, dynamic>>>{};
  for (final episode in episodes) {
    final year = _broadcastYear(episode);
    if (year != null) groups.putIfAbsent(year, () => []).add(episode);
  }
  return [
    for (final year in groups.keys.toList()..sort())
      OrfSeasonPlan(key: orfYearSeasonKey(year), number: year, title: '$year', episodes: groups[year]!),
  ];
}

/// The year in ORF's own timestamp, which carries the Vienna offset, so a New Year's Eve broadcast stays in its year.
int? _broadcastYear(Map<String, dynamic> episode) {
  final date = orfString(episode['date']);
  return date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4));
}
