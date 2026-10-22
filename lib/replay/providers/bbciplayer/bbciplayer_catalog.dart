import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'bbciplayer_api.dart';
import 'bbciplayer_mapper.dart';
import 'bbciplayer_seasons.dart';

/// Resolves single titles and the show -> season -> episode structure.
///
/// A show is its programme id, a season is `programmeId/sliceKey` and an episode or a one-off is its own id. A
/// show always has seasons: a show whose episodes name no series gets one synthetic season.
class BbcIplayerCatalog {
  static const _pageSize = 200;
  static const _maxPages = 10;

  final BbcIplayerApi _api;
  final DateTime Function() _now;

  BbcIplayerCatalog(this._api, this._now);

  /// One title by native id: an episode or one-off, a show, or a season.
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (id.contains('/')) return _season(ref);
    final episodes = (await _api.ibl('episodes/$id'))['episodes'];
    final episode = episodes is List ? episodes.whereType<Map<String, dynamic>>().firstOrNull : null;
    if (episode != null) return bbcEpisode(episode, now: _now());
    final programmes = (await _api.ibl('programmes/$id'))['programmes'];
    final programme = programmes is List ? programmes.whereType<Map<String, dynamic>>().firstOrNull : null;
    return programme == null ? null : bbcTitleFromItem(programme, now: _now());
  }

  Future<List<ReplayTitle>> seasons(ReplayRef show) async {
    final data = await _load(show.nativeId);
    if (data == null) return const [];
    return [for (final group in data.groups) _seasonTitle(group, data.show)];
  }

  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final parts = season.nativeId.split('/');
    final data = await _load(parts.first);
    if (data == null) return const [];
    final group = data.groups.where((g) => g.key == parts.sublist(1).join('/')).firstOrNull;
    if (group == null) return const [];
    final number = group.number;
    return [
      for (final entry in group.episodes)
        bbcEpisode(
          entry.item,
          now: _now(),
          context: BbcContext(season: season, seasonNumber: number, episodeNumber: entry.number),
        ),
    ];
  }

  Future<ReplayTitle?> _season(ReplayRef ref) async {
    final id = ref.nativeId.split('/').first;
    final data = await _load(id);
    if (data == null) return null;
    final group = data.groups.where((g) => bbcSeasonRef(id, g.key) == ref).firstOrNull;
    return group == null ? null : _seasonTitle(group, data.show);
  }

  ReplayTitle _seasonTitle(BbcSeasonGroup group, ReplayTitle show) => ReplayTitle(
    ref: bbcSeasonRef(show.ref.nativeId, group.key),
    kind: ReplayKind.season,
    title: group.key == bbcAllKey ? show.title : group.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    logoUrl: show.logoUrl,
    seasonNumber: group.number,
    childCount: group.episodes.length,
    showRef: show.ref,
    showTitle: show.title,
  );

  Future<_ShowData?> _load(String programmeId) async {
    final items = <Map<String, dynamic>>[];
    Map<String, dynamic>? programme;
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.ibl(
        'programmes/$programmeId/episodes',
        query: {'per_page': '$_pageSize', 'page': '$page'},
      );
      final block = body['programme_episodes'];
      if (block is! Map<String, dynamic>) break;
      final head = block['programme'];
      if (page == 1 && head is Map<String, dynamic>) programme = head;
      final elements = block['elements'];
      final batch = elements is List ? elements.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
      items.addAll(batch);
      final total = (block['count'] as num?)?.toInt() ?? 0;
      if (batch.length < _pageSize || items.length >= total) break;
    }
    if (programme == null || programme['tleo_type'] == 'episode') return null;
    final show = bbcTitleFromItem(programme, now: _now());
    if (show == null) return null;
    return _ShowData(show, bbcSeasonGroups(items, showTitle: show.title));
  }
}

class _ShowData {
  final ReplayTitle show;
  final List<BbcSeasonGroup> groups;

  const _ShowData(this.show, this.groups);
}
