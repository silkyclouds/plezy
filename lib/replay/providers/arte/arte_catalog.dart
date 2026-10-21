import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'arte_api.dart';
import 'arte_mapper.dart';

/// Native id of the season that stands for "every video" of a show that has no real seasons.
const arteAllVideosSeason = '_all';

/// Resolves the show -> season -> episode structure of ARTE collections.
///
/// A season ref is `RC-series/RC-season`. Magazines, topics and mini-series without seasons get a single
/// synthetic season, `RC-series/_all`, so every show has the same two levels.
class ArteCatalog {
  final ArteApi _api;

  ArteCatalog(this._api);

  /// The collection header as a show, or null when the id is not a collection.
  Future<ReplayTitle?> show(String seriesId) async {
    final page = await _api.emac('collections/$seriesId');
    final header = _zone(page, 'collection_content_')?['content']?['data'];
    if (header is! List || header.isEmpty) return null;
    return arteTitleFromItem(header.first as Map<String, dynamic>);
  }

  Future<List<ReplayTitle>> seasons(String seriesId) async {
    final page = await _api.emac('collections/$seriesId');
    final show = await _showFromPage(page);
    if (show == null) return const [];
    final subZones = _zones(page, 'collection_subcollection_');
    final context = ArteContext(show: show.ref, showTitle: show.title);

    if (_isSeasonList(subZones, show)) {
      return [for (var i = 0; i < subZones.length; i++) _season(subZones[i], i + 1, show, context)];
    }
    return [_syntheticSeason(show)];
  }

  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final parts = season.nativeId.split('/');
    final seriesId = parts.first;
    final subId = parts.length > 1 ? parts[1] : arteAllVideosSeason;
    final page = await _api.emac('collections/$seriesId');
    final show = await _showFromPage(page);
    if (show == null) return const [];

    final zone = subId == arteAllVideosSeason
        ? (_zone(page, 'collection_videos_') ?? _zones(page, 'collection_subcollection_').firstOrNull)
        : _zones(
            page,
            'collection_subcollection_',
          ).firstWhere((z) => (z['code'] as String).endsWith(subId), orElse: () => const {});
    if (zone == null || zone.isEmpty) return const [];

    final context = ArteContext(show: show.ref, showTitle: show.title, season: season);
    return _allPages(zone, context);
  }

  Future<List<ReplayTitle>> _allPages(Map<String, dynamic> zone, ArteContext context) async {
    final titles = <ReplayTitle>[...arteTitlesFromZone(zone, context: context)];
    var next = _nextLink(zone);
    for (var guard = 0; next != null && guard < 12; guard++) {
      final page = await _api.link(next);
      titles.addAll(arteTitlesFromZone({'content': page}, context: context));
      next = (page['pagination'] as Map?)?['links']?['next'] as String?;
    }
    return titles;
  }

  Future<ReplayTitle?> _showFromPage(Map<String, dynamic> page) async {
    final data = _zone(page, 'collection_content_')?['content']?['data'];
    if (data is! List || data.isEmpty) return null;
    return arteTitleFromItem(data.first as Map<String, dynamic>);
  }

  /// A season list is one whose episodes carry a season number, or a lone sub-collection of a series.
  bool _isSeasonList(List<Map<String, dynamic>> subZones, ReplayTitle show) {
    if (subZones.isEmpty) return false;
    final numbered = subZones.any((z) => _firstEpisodeSeason(z) != null);
    return numbered || (subZones.length == 1 && show.kind == ReplayKind.show && _isSeries(subZones.first));
  }

  bool _isSeries(Map<String, dynamic> zone) {
    final data = (zone['content'] as Map?)?['data'];
    return data is List && data.any((e) => e is Map && (e['episodeInfo'] as Map?)?['episode'] != null);
  }

  int? _firstEpisodeSeason(Map<String, dynamic> zone) {
    final data = (zone['content'] as Map?)?['data'];
    if (data is! List) return null;
    for (final e in data.whereType<Map<String, dynamic>>()) {
      final season = (e['episodeInfo'] as Map?)?['season'];
      if (season is num) return season.toInt();
    }
    return null;
  }

  ReplayTitle _season(Map<String, dynamic> zone, int ordinal, ReplayTitle show, ArteContext context) {
    final code = zone['code'] as String;
    final subId = code.substring(code.lastIndexOf('_') + 1);
    final number = _firstEpisodeSeason(zone) ?? ordinal;
    final pagination = (zone['content'] as Map?)?['pagination'] as Map?;
    final count = (pagination?['totalCount'] as num?)?.toInt() ?? ((zone['content'] as Map?)?['data'] as List?)?.length;
    return ReplayTitle(
      ref: arteRef('${_seriesIdOf(show)}/$subId'),
      kind: ReplayKind.season,
      title: (zone['title'] as String?)?.trim() ?? 'Saison $number',
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: number,
      childCount: count,
      showRef: show.ref,
      showTitle: show.title,
      availability: show.availability,
    );
  }

  ReplayTitle _syntheticSeason(ReplayTitle show) => ReplayTitle(
    ref: arteRef('${_seriesIdOf(show)}/$arteAllVideosSeason'),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    showRef: show.ref,
    showTitle: show.title,
    availability: show.availability,
  );

  String _seriesIdOf(ReplayTitle show) => show.ref.nativeId;

  String? _nextLink(Map<String, dynamic> zone) =>
      (((zone['content'] as Map?)?['pagination'] as Map?)?['links'] as Map?)?['next'] as String?;

  Map<String, dynamic>? _zone(Map<String, dynamic> page, String codePrefix) => _zones(page, codePrefix).firstOrNull;

  List<Map<String, dynamic>> _zones(Map<String, dynamic> page, String codePrefix) {
    final zones = page['zones'];
    if (zones is! List) return const [];
    return [
      for (final z in zones.whereType<Map<String, dynamic>>())
        if ((z['code'] as String? ?? '').startsWith(codePrefix)) z,
    ];
  }
}
