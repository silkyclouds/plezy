import '../../model/replay_title.dart';
import 'rtsplay_api.dart';
import 'rtsplay_episodes.dart';
import 'rtsplay_ids.dart';
import 'rtsplay_mapper.dart';
import 'rtsplay_numbering.dart';

const _pageSize = 100;

/// Resolves the show -> season -> episode structure of RTS Play.
///
/// RTS has no season endpoint. Seasons come from the numbers on the episodes. A show with numbered
/// episodes gets one season per number, plus "Bonus" for episodes without one. A show with no numbers
/// gets one synthetic season, or one season per broadcast year when it has more than
/// [rtsLongShowThreshold] episodes, because only the newest pages of a daily show are worth loading.
class RtsPlayShows {
  final RtsPlayApi _api;
  final RtsEpisodeSource _source;

  RtsPlayShows(this._api) : _source = RtsEpisodeSource(_api);

  Future<ReplayTitle?> show(String showId) async {
    final raw = await _api.unit('show/tv/$showId');
    return raw == null ? null : rtsTitleFromShow(raw);
  }

  Future<List<ReplayTitle>> seasons(String showId) async {
    final raw = await _api.unit('show/tv/$showId');
    final show = raw == null ? null : rtsTitleFromShow(raw);
    if (raw == null || show == null) return const [];
    final expected = rtsEpisodeCount(raw) ?? 0;

    final first = (await _source.page0(showId)) ?? const {};
    final firstItems = _items(first);
    final isLong = first['next'] is String && expected > rtsLongShowThreshold && firstItems.isNotEmpty;
    if (isLong && !firstItems.any((i) => rtsNumbers(i).season != null)) {
      return _yearSeasons(showId, show, firstItems, expected);
    }

    final loaded = await _source.load(showId, expected: expected);
    return _seasonTitles(showId, show, RtsSeasonGroups.of(loaded.items), known: !loaded.truncated);
  }

  Future<List<ReplayTitle>> episodes(RtsSeasonId id) async {
    final raw = await _api.unit('show/tv/${id.showId}');
    final show = raw == null ? null : rtsTitleFromShow(raw);
    if (raw == null || show == null) return const [];

    final year = id.key.year;
    if (year != null) return _yearEpisodes(id, show, year, rtsEpisodeCount(raw) ?? 0);

    final loaded = await _source.load(id.showId, expected: rtsEpisodeCount(raw) ?? 0);
    final groups = RtsSeasonGroups.of(loaded.items);
    final context = RtsContext(
      show: show.ref,
      showTitle: show.title,
      season: rtsSeasonRef(id.showId, id.key),
      seasonNumber: groups.numberOf(id.key),
    );
    return rtsOrderEpisodes(_episodeTitles(groups.groups[id.key] ?? const [], context));
  }

  List<ReplayTitle> _seasonTitles(String showId, ReplayTitle show, RtsSeasonGroups groups, {required bool known}) {
    return [
      for (final MapEntry(:key, value: items) in groups.groups.entries)
        _season(
          showId,
          show,
          key,
          number: groups.numberOf(key),
          title: key.number != null
              ? 'Saison ${key.number}'
              : groups.hasNumberedSeasons
              ? 'Bonus'
              : show.title,
          count: known ? items.length : null,
        ),
    ];
  }

  ReplayTitle _season(
    String showId,
    ReplayTitle show,
    RtsSeasonKey key, {
    required int number,
    required String title,
    int? count,
  }) {
    return ReplayTitle(
      ref: rtsSeasonRef(showId, key),
      kind: ReplayKind.season,
      title: title,
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: number,
      childCount: count,
      showRef: show.ref,
      showTitle: show.title,
    );
  }

  /// Years from the newest broadcast back to the oldest page, found by looking at the last non-empty page.
  Future<List<ReplayTitle>> _yearSeasons(
    String showId,
    ReplayTitle show,
    List<Map<String, dynamic>> newest,
    int expected,
  ) async {
    final newestYear = _yearOf(newest.first);
    final end = await _firstEmptyPage(showId, expected);
    final oldest = end > 0 ? await _source.pageAt(showId, end - 1) : newest;
    final oldestYear = oldest.isEmpty ? newestYear : _yearOf(oldest.last);
    if (newestYear == null || oldestYear == null) return const [];
    return [
      for (var year = oldestYear; year <= newestYear; year++)
        _season(showId, show, RtsSeasonKey.year(year), number: year, title: '$year'),
    ];
  }

  Future<List<ReplayTitle>> _yearEpisodes(RtsSeasonId id, ReplayTitle show, int year, int expected) async {
    final context = RtsContext(
      show: show.ref,
      showTitle: show.title,
      season: rtsSeasonRef(id.showId, id.key),
      seasonNumber: year,
    );
    final items = <Map<String, dynamic>>[];
    for (var index = await _firstPageReaching(id.showId, year, expected); ; index++) {
      final page = await _source.pageAt(id.showId, index);
      if (page.isEmpty) break;
      items.addAll(page.where((i) => _yearOf(i) == year));
      final last = _yearOf(page.last);
      if (last == null || last < year) break;
    }
    return _episodeTitles(items, context);
  }

  /// First page whose oldest item is no newer than [year], so that the year starts on or after it.
  Future<int> _firstPageReaching(String showId, int year, int expected) async {
    var low = 0;
    var high = expected ~/ _pageSize + 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final page = await _source.pageAt(showId, mid);
      final oldest = page.isEmpty ? null : _yearOf(page.last);
      if (oldest == null || oldest <= year) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  /// Index of the first page with no episode, by bisection over the newest-first pages.
  Future<int> _firstEmptyPage(String showId, int expected) async {
    var low = 0;
    var high = expected ~/ _pageSize + 2;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if ((await _source.pageAt(showId, mid)).isEmpty) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  List<ReplayTitle> _episodeTitles(List<Map<String, dynamic>> items, RtsContext context) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (rtsTitleFromMedia(item, context: context) case final title? when seen.add(title.ref.nativeId)) title,
    ];
  }
}

List<Map<String, dynamic>> _items(Map<String, dynamic> page) {
  final list = page['mediaList'];
  return list is List ? list.whereType<Map<String, dynamic>>().toList() : const [];
}

int? _yearOf(Map<String, dynamic> item) {
  final date = item['date'];
  return date is String && date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
}
