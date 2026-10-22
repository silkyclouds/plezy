import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'urplay_api.dart';
import 'urplay_mapper.dart';
import 'urplay_numbering.dart';
import 'urplay_refs.dart';

/// One season of a show, as UR lists it: a `series` entry and the number its description announces.
class _Entry {
  final Map<String, dynamic> series;
  final int season;

  const _Entry(this.series, this.season);

  String get id => '${series['id']}';
}

/// Every season UR still offers of one show, oldest first, and the episodes of the season that was asked for.
class _Family {
  final String title;
  final List<_Entry> entries;
  final Map<String, dynamic> ownPage;
  final String ownId;

  const _Family(this.title, this.entries, this.ownPage, this.ownId);

  _Entry get own => entries.firstWhere((e) => e.id == ownId);
}

/// Where a programme sits in the show -> season -> episode tree.
class UrLineage {
  final ReplayRef show;
  final ReplayRef season;
  final int? seasonNumber;

  const UrLineage(this.show, this.season, this.seasonNumber);
}

/// Resolves the show -> season -> episode structure of UR Play.
///
/// UR has no show level: each season is its own `series`, with the season number only in its description. Seasons
/// of one show are found as the series that carry the same title.
class UrCatalog {
  static const _searchPages = 2;

  final UrPlayApi _api;

  UrCatalog(this._api);

  Future<ReplayTitle?> show(String seriesId) async {
    final family = await _family(seriesId);
    if (family == null) return null;
    return urTitleFromItem(family.own.series, seasonCount: family.entries.length);
  }

  Future<List<ReplayTitle>> seasons(String showId) async {
    final family = await _family(showId);
    if (family == null) return const [];
    return Future.wait([for (final entry in family.entries) _season(showId, family, entry)]);
  }

  Future<ReplayTitle?> season(String showId, String seriesId) async {
    final family = await _family(seriesId);
    if (family == null) return null;
    return _season(showId, family, family.own);
  }

  Future<List<ReplayTitle>> episodes(String showId, String seriesId) async {
    final family = await _family(seriesId);
    if (family == null) return const [];
    final context = UrContext(
      show: urplayShowRef(showId),
      showTitle: family.title,
      season: urplaySeasonRef(showId, seriesId),
      seasonNumber: family.own.season,
    );
    final upcoming = context.asUpcoming();
    final titles = [
      for (final item in _items(family.ownPage, 'accessibleEpisodes')) ?urTitleFromItem(item, context: context),
      for (final item in _items(family.ownPage, 'upcomingEpisodes')) ?urTitleFromItem(item, context: upcoming),
    ];
    return titles..sort(_byEpisodeNumber);
  }

  /// The show and season a programme belongs to, with the show named after the newest season so that every
  /// episode of one show points at the same ref.
  Future<UrLineage> lineage(String seriesId, String showTitle) async {
    final entries = _entries(await _siblings(showTitle));
    final own = entries.where((e) => e.id == seriesId).firstOrNull;
    final showId = entries.isEmpty ? seriesId : entries.last.id;
    return UrLineage(urplayShowRef(showId), urplaySeasonRef(showId, seriesId), own?.season);
  }

  /// The id of the first programme of a series that can be watched now, used to ask whether the series is blocked.
  Future<String?> firstProgramId(String seriesId) async {
    final page = await _api.seasonEpisodes(seriesId);
    if (page == null) return null;
    return _items(page, 'accessibleEpisodes').firstOrNull?['id']?.toString();
  }

  Future<ReplayTitle> _season(String showId, _Family family, _Entry entry) async {
    final count = await _episodeCount(entry.id);
    return urSeasonFromSeries(
      entry.series,
      showId: showId,
      showTitle: family.title,
      seasonNumber: entry.season,
      episodeCount: count,
    );
  }

  Future<int?> _episodeCount(String seriesId) async {
    try {
      final page = await _api.seasonEpisodes(seriesId);
      return page == null ? null : _items(page, 'accessibleEpisodes').length;
    } on MediaServerHttpException {
      return null;
    }
  }

  Future<_Family?> _family(String seriesId) async {
    final page = await _api.seasonEpisodes(seriesId);
    if (page == null) return null;
    final episodes = [..._items(page, 'accessibleEpisodes'), ..._items(page, 'upcomingEpisodes')];
    final title = episodes.firstOrNull?['mainTitle'] as String?;
    if (title == null) return null;

    final hits = await _siblings(title);
    if (!hits.any((h) => '${h['id']}' == seriesId)) hits.add(_stand(seriesId, title, episodes.first));
    return _Family(title, _entries(hits), page, seriesId);
  }

  /// Series whose title equals [title]. The search matches descriptions too, so its hits are filtered.
  Future<List<Map<String, dynamic>>> _siblings(String title) async {
    final key = urTitleKey(title);
    final hits = <Map<String, dynamic>>[];
    var start = 0;
    for (var page = 0; page < _searchPages; page++) {
      final body = await _api.search({'product_type': 'series', 'query': title, 'start': '$start'});
      for (final item in _items(body, 'results')) {
        if (item['productType'] == 'series' && urTitleKey(item['title'] as String? ?? '') == key) hits.add(item);
      }
      final next = (body['nextPageInfo'] as Map?)?['start'];
      if (next is! int) break;
      start = next;
    }
    return hits;
  }

  /// A series entry rebuilt from one of its episodes, for a series the search does not return.
  Map<String, dynamic> _stand(String seriesId, String title, Map<String, dynamic> episode) => {
    'id': int.parse(seriesId),
    'productType': 'series',
    'title': title,
    'mainGenre': episode['mainGenre'],
    'image': episode['image'],
    'accessiblePlatforms': episode['accessiblePlatforms'],
  };

  List<_Entry> _entries(List<Map<String, dynamic>> series) {
    final entries = [for (final s in series) _Entry(s, urSeasonFromDescription(s['description'] as String?) ?? 1)];
    return entries..sort(
      (a, b) => a.season != b.season ? a.season.compareTo(b.season) : int.parse(a.id).compareTo(int.parse(b.id)),
    );
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> page, String key) {
    final list = page[key];
    return list is List ? list.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
  }

  int _byEpisodeNumber(ReplayTitle a, ReplayTitle b) {
    final x = a.episodeNumber;
    final y = b.episodeNumber;
    if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
    return x.compareTo(y);
  }
}
