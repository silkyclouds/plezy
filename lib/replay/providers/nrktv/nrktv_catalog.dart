import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'nrktv_api.dart';
import 'nrktv_geo.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_mapper.dart';
import 'nrktv_numbering.dart';
import 'nrktv_program.dart';

typedef _SeasonEntry = ({String name, String title, bool available, int? episodes, String? poster});

/// Resolves show -> season -> episode for NRK series.
///
/// Sequential series have numbered seasons, standard series one season per year and news series one per month; all
/// three are listed under `_links.seasons` and read the same way. A series with no season list gets one stand-in
/// season, [nrkAllEpisodes], holding the episodes the series page embeds.
class NrkCatalog {
  final NrkApi _api;
  final NrkGeoMemory _geo;
  final DateTime Function() _now;

  NrkCatalog(this._api, this._geo, this._now);

  /// The series header as a show, or null when NRK has no such series.
  Future<ReplayTitle?> show(String seriesId) async {
    final body = await _series(seriesId);
    return body == null ? null : _showOf(body, seriesId);
  }

  /// The seasons of a series, oldest first, without those NRK marks as having nothing to watch.
  Future<List<ReplayTitle>> seasons(String seriesId) async {
    final body = await _series(seriesId);
    if (body == null) return const [];
    final show = _showOf(body, seriesId);
    final entries = [
      for (final e in _seasonEntries(body))
        if (e.available) e,
    ];
    if (entries.isEmpty) return [_standIn(show, seriesId)];

    final numbers = nrkSeasonNumbers([for (final e in entries) e.name]);
    final seasons = [
      for (var i = 0; i < entries.length; i++)
        ReplayTitle(
          ref: nrkSeasonRef(seriesId, entries[i].name),
          kind: ReplayKind.season,
          title: entries[i].title,
          posterUrl: entries[i].poster ?? show.posterUrl,
          backdropUrl: show.backdropUrl,
          seasonNumber: numbers[i],
          childCount: entries[i].episodes,
          showRef: show.ref,
          showTitle: show.title,
        ),
    ];
    return seasons..sort((a, b) => a.seasonNumber!.compareTo(b.seasonNumber!));
  }

  /// One season by name, or null.
  Future<ReplayTitle?> season(String seriesId, String name) async {
    final all = await seasons(seriesId);
    for (final season in all) {
      if (season.ref == nrkSeasonRef(seriesId, name)) return season;
    }
    return null;
  }

  /// The episodes of one season, numbered and in viewing order.
  Future<List<ReplayTitle>> episodes(String seriesId, String name) async {
    final body = name == nrkAllEpisodes ? await _series(seriesId) : await _seasonBody(seriesId, name);
    if (body == null) return const [];
    final raw = [
      for (final e in _episodeList(body['_embedded']))
        if (e['prfId'] is String) e,
    ];
    for (final e in raw) {
      final flag = nrkNorwayOnly(e['usageRights']);
      if (flag != null) _geo.remember(e['prfId'] as String, norwayOnly: flag);
    }
    final context = await _context(body, seriesId, name);
    final now = _now();
    return [for (final n in nrkNumberEpisodes(raw)) nrkEpisode(n.episode, context, n.number, now)];
  }

  /// A programme as a movie or an episode, with the show and season it belongs to.
  Future<ReplayTitle?> program(String programId) async {
    final results = await Future.wait<Map<String, dynamic>?>([
      _orMissing(() => _api.program(programId)),
      _orMissing(() => _api.metadata(programId)),
    ]);
    final page = results[0];
    if (page == null) return null;
    final flag = nrkProgramNorwayOnly(page);
    if (flag != null) _geo.remember(programId, norwayOnly: flag);
    return nrkProgram(programId, page, results[1], _now());
  }

  Future<Map<String, dynamic>?> _series(String seriesId) => _orMissing(() => _api.series(seriesId));

  Future<Map<String, dynamic>?> _seasonBody(String seriesId, String name) =>
      _orMissing(() => _api.season(seriesId, name));

  /// A request whose 404 means "no such thing" rather than a failure.
  Future<Map<String, dynamic>?> _orMissing(Future<Map<String, dynamic>> Function() request) async {
    try {
      return await request();
    } on MediaServerHttpException catch (e) {
      if (nrkIsNotFound(e)) return null;
      rethrow;
    }
  }

  ReplayTitle _showOf(Map<String, dynamic> body, String seriesId) {
    final entries = _seasonEntries(body).where((e) => e.available).toList();
    final poster = entries.map((e) => e.poster).whereType<String>().firstOrNull;
    return nrkShow(body, seriesId: seriesId, posterFrom: poster, seasons: entries.isEmpty ? 1 : entries.length);
  }

  ReplayTitle _standIn(ReplayTitle show, String seriesId) => ReplayTitle(
    ref: nrkSeasonRef(seriesId, nrkAllEpisodes),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    showRef: show.ref,
    showTitle: show.title,
  );

  List<_SeasonEntry> _seasonEntries(Map<String, dynamic> body) {
    final embedded = <String, Map<dynamic, dynamic>>{
      for (final s in ((body['_embedded'] as Map?)?['seasons'] as List? ?? const []).whereType<Map>())
        ?_embeddedName(s): s,
    };
    final listed = ((body['_links'] as Map?)?['seasons'] as List? ?? const []).whereType<Map>();
    final entries = <_SeasonEntry>[];
    for (final link in listed) {
      final name = link['name'];
      if (name is! String) continue;
      final detail = embedded[name];
      entries.add((
        name: name,
        title: (link['title'] as String?) ?? name,
        available: (detail?['hasAvailableEpisodes'] ?? detail?['hasAvailableInstalments']) != false,
        episodes: _embeddedCount(detail),
        poster: nrkImageRef(detail?['posterImage']),
      ));
    }
    return entries;
  }

  String? _embeddedName(Map<dynamic, dynamic> season) {
    final self = (season['_links'] as Map?)?['self'] as Map?;
    final name = self?['name'];
    if (name is String) return name;
    final href = self?['href'];
    return href is String ? href.split('/').last : null;
  }

  int? _embeddedCount(Map<dynamic, dynamic>? season) {
    final episodes = (season?['_embedded'] as Map?)?['episodes'];
    return episodes is List ? episodes.length : null;
  }

  /// The episodes a series or season response embeds: `episodes` (sequential) or `instalments` (standard, news),
  /// the latter either as a list or wrapped in a paging object.
  List<Map<String, dynamic>> _episodeList(Object? embedded) {
    if (embedded is! Map) return const [];
    var list = embedded['episodes'] ?? embedded['instalments'];
    if (list is Map) list = (list['_embedded'] as Map?)?['instalments'];
    return list is List ? list.whereType<Map<String, dynamic>>().toList() : const [];
  }

  Future<NrkSeasonContext> _context(Map<String, dynamic> body, String seriesId, String name) async {
    final link = (body['_links'] as Map?)?['series'] as Map?;
    final seriesType = body['seriesType'] as String? ?? link?['name'] as String? ?? 'standard';
    final show = name == nrkAllEpisodes ? _showOf(body, seriesId) : null;
    final showTitle = show?.title ?? link?['title'] as String? ?? seriesId;
    final seasonNumber = name == nrkAllEpisodes ? 1 : int.tryParse(name) ?? await _positionOf(seriesId, name);
    return NrkSeasonContext(
      showRef: nrkShowRef(seriesId),
      showTitle: showTitle,
      seriesType: seriesType,
      seasonRef: nrkSeasonRef(seriesId, name),
      seasonNumber: seasonNumber,
    );
  }

  Future<int?> _positionOf(String seriesId, String name) async {
    final all = await seasons(seriesId);
    return all.where((s) => s.ref == nrkSeasonRef(seriesId, name)).firstOrNull?.seasonNumber;
  }
}
