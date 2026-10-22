import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ceskatelevize_api.dart';
import 'ceskatelevize_mapper.dart';
import 'ceskatelevize_numbering.dart';
import 'ceskatelevize_queries.dart';
import 'ceskatelevize_refs.dart';
import 'ceskatelevize_text.dart';

/// Resolves the show -> season -> episode structure.
///
/// A season ref is `show-<sidp>/<seasonId>`. A show without seasons (magazines, films, most news) gets a single
/// synthetic season, `show-<sidp>/_all`, so every show has the same two levels.
class CeskaTelevizeCatalog {
  static const _pageSize = 50;

  /// Longest episode list returned. A magazine can hold thousands; past this the newest episodes are kept.
  static const _maxEpisodes = 400;

  final CeskaTelevizeApi _api;
  final CeskaTelevizeMapper _mapper;
  final Map<String, String> _filmEpisodes = {};

  CeskaTelevizeCatalog(this._api, this._mapper);

  /// The show header, or null when the broadcaster no longer has the programme. A film is a movie unless [asShow].
  Future<ReplayTitle?> show(String sidp, {bool asShow = true}) async {
    final programme = await _programme(sidp);
    return programme == null ? null : _mapper.programme(programme, asShow: asShow);
  }

  Future<List<ReplayTitle>> seasons(String sidp) async {
    final programme = await _programme(sidp);
    final show = programme == null ? null : _mapper.programme(programme, asShow: true);
    if (programme == null || show == null) return const [];

    final entries = _seasonEntries(programme);
    if (entries.isEmpty) return [_wholeShow(show, sidp, programme['playableEpisodeCount'] as num?)];

    final counts = await _counts(sidp, [for (final e in entries) e.id]);
    final numbers = ceskatelevizeSeasonNumbers(entries);
    return [
      for (var i = 0; i < entries.length; i++)
        if (counts[i] > 0) _season(show, sidp, entries[i], numbers[i], counts[i]),
    ];
  }

  Future<ReplayTitle?> season(CeskaTelevizeSeasonId id) async {
    final all = await seasons(id.sidp);
    final ref = ceskatelevizeSeasonRef(id.sidp, id.seasonId);
    return all.where((s) => s.ref == ref).firstOrNull;
  }

  Future<List<ReplayTitle>> episodes(CeskaTelevizeSeasonId id) async {
    final all = await seasons(id.sidp);
    if (all.isEmpty) return const [];
    final show = all.first;
    final infos = {for (final s in all) _seasonIdOf(s.ref): (ref: s.ref, number: s.seasonNumber ?? 1)};
    final target = infos[id.seasonId];
    if (target == null) return const [];

    final context = CeskaTelevizeShowContext(
      show: show.showRef!,
      showTitle: show.showTitle ?? show.title,
      seasons: infos,
      fallback: target,
    );
    final items = await _episodeItems(id.sidp, id.isWholeShow ? null : id.seasonId);
    final seen = <ReplayRef>{};
    return [
      for (final item in items)
        if (_mapper.episode(item, context: context) case final episode? when seen.add(episode.ref)) episode,
    ];
  }

  /// Metadata of one episode. The page carries no show or season, so those stay empty.
  Future<ReplayTitle?> episode(String idec) async {
    try {
      final data = await _api.query(ceskatelevizeEpisodeQuery(idec), ttl: CeskaTelevizeApi.detailsTtl);
      final meta = data['episode'];
      if (meta is! Map<String, dynamic>) return null;
      return _mapper.episode({
        'idec': idec,
        'title': meta['title'],
        'description': meta['description'],
        'duration': meta['duration'],
        'date': {'datetime': meta['uploadDate']},
      });
    } on CeskaTelevizeNotFoundException {
      return null;
    }
  }

  /// The episode id that plays a film, or null when the film has no playable episode.
  Future<String?> filmEpisode(String sidp) async {
    final known = _filmEpisodes[sidp];
    if (known != null) return known;
    try {
      final data = await _api.query(ceskatelevizeFilmEpisodeQuery(sidp), ttl: CeskaTelevizeApi.detailsTtl);
      final items = ((data['programme'] as Map?)?['episodes'] as Map?)?['items'];
      final id = items is List && items.isNotEmpty ? (items.first as Map)['id'] : null;
      if (id is! String) return null;
      return _filmEpisodes[sidp] = id;
    } on CeskaTelevizeNotFoundException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _programme(String sidp) async {
    try {
      final data = await _api.query(ceskatelevizeShowQuery(sidp), ttl: CeskaTelevizeApi.detailsTtl);
      final programme = data['programme'];
      return programme is Map<String, dynamic> ? programme : null;
    } on CeskaTelevizeNotFoundException {
      return null;
    }
  }

  List<CeskaTelevizeSeasonEntry> _seasonEntries(Map<String, dynamic> programme) {
    final seasons = programme['seasons'];
    if (seasons is! List) return const [];
    return [
      for (final s in seasons.whereType<Map<String, dynamic>>())
        if (s['id'] is String) (id: s['id'] as String, title: ceskatelevizeLabel(s['title']) ?? s['id'] as String),
    ];
  }

  Future<List<int>> _counts(String sidp, List<String> seasonIds) async {
    final data = await _api.query(ceskatelevizeSeasonCountsQuery(sidp, seasonIds), ttl: CeskaTelevizeApi.detailsTtl);
    final programme = data['programme'] as Map<String, dynamic>? ?? const {};
    return [
      for (var i = 0; i < seasonIds.length; i++) ((programme['c$i'] as Map?)?['totalCount'] as num?)?.toInt() ?? 0,
    ];
  }

  /// Episodes oldest first. A list longer than [_maxEpisodes] is read newest first instead and put back in order,
  /// so the cut falls on the oldest episodes.
  Future<List<Map<String, dynamic>>> _episodeItems(String sidp, String? seasonId) async {
    var order = 'oldest';
    var page = await _episodePage(sidp, seasonId, order, 0);
    final total = (page['totalCount'] as num?)?.toInt() ?? 0;
    final capped = total > _maxEpisodes;
    if (capped) {
      order = 'newest';
      page = await _episodePage(sidp, seasonId, order, 0);
    }

    final items = <Map<String, dynamic>>[..._itemsOf(page)];
    final wanted = capped ? _maxEpisodes : total;
    while (items.length < wanted) {
      final more = _itemsOf(await _episodePage(sidp, seasonId, order, items.length));
      if (more.isEmpty) break;
      items.addAll(more);
    }
    final limited = items.take(wanted).toList();
    return capped ? limited.reversed.toList() : limited;
  }

  Future<Map<String, dynamic>> _episodePage(String sidp, String? seasonId, String order, int offset) async {
    final query = ceskatelevizeEpisodesQuery(
      sidp,
      seasonId: seasonId,
      limit: _pageSize,
      offset: offset,
      orderBy: order,
    );
    final data = await _api.query(query, ttl: CeskaTelevizeApi.detailsTtl);
    return ((data['programme'] as Map?)?['episodes'] as Map<String, dynamic>?) ?? const {};
  }

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> page) {
    final items = page['items'];
    return items is List ? items.whereType<Map<String, dynamic>>().toList() : const [];
  }

  ReplayTitle _season(ReplayTitle show, String sidp, CeskaTelevizeSeasonEntry entry, int number, int count) =>
      ReplayTitle(
        ref: ceskatelevizeSeasonRef(sidp, entry.id),
        kind: ReplayKind.season,
        title: entry.title,
        posterUrl: show.posterUrl,
        backdropUrl: show.backdropUrl,
        seasonNumber: number,
        childCount: count,
        showRef: show.ref,
        showTitle: show.title,
        availability: show.availability,
      );

  ReplayTitle _wholeShow(ReplayTitle show, String sidp, num? count) => ReplayTitle(
    ref: ceskatelevizeSeasonRef(sidp, ceskatelevizeAllEpisodes),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    childCount: count?.toInt(),
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );

  String _seasonIdOf(ReplayRef season) => season.nativeId.substring(season.nativeId.indexOf('/') + 1);
}
