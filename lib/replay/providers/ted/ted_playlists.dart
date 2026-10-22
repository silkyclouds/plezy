import '../../model/replay_title.dart';
import 'ted_api.dart';
import 'ted_mapper.dart';
import 'ted_queries.dart';
import 'ted_talks.dart';

/// Talks per request when reading a playlist's talks.
const _talksPerRequest = 50;

/// Playlists are the shows of TED: one synthetic season, the talks in playlist order as episodes.
class TedPlaylists {
  final TedApi _api;

  TedPlaylists(this._api);

  Future<ReplayPage> list({int page = 0}) async {
    final data = await _api.query(tedPlaylistsQuery(first: tedPageSize, after: page * tedPageSize));
    final connection = data['playlists'];
    return ReplayPage(titles: tedPlaylistsFromConnection(connection), totalCount: tedTotalCount(connection));
  }

  Future<ReplayTitle?> show(String slug) async {
    final node = await _node(slug, after: 0);
    return node == null ? null : tedPlaylistFromNode(node);
  }

  /// The playlist's only season, or null when the playlist does not exist.
  Future<ReplayTitle?> season(String slug) async {
    final node = await _node(slug, after: 0);
    if (node == null) return null;
    final show = tedPlaylistFromNode(node);
    return show == null ? null : tedSeasonOfPlaylist(show, talkCount: tedTotalCount(node['videos']));
  }

  /// Every talk of the playlist, numbered from 1 in playlist order.
  Future<List<ReplayTitle>> episodes(String slug) async {
    final first = await _node(slug, after: 0);
    if (first == null) return const [];
    final show = tedPlaylistFromNode(first);
    if (show == null) return const [];

    final total = tedTotalCount(first['videos']);
    final episodes = <ReplayTitle>[];
    var node = first;
    for (var after = 0; after < total; after += _talksPerRequest) {
      if (after > 0) {
        final next = await _node(slug, after: after);
        if (next == null) break;
        node = next;
      }
      final offset = after;
      episodes.addAll(
        tedTalksFromConnection(
          node['videos'],
          placementOf: (index) => TedPlacement(show: show.ref, showTitle: show.title, number: offset + index + 1),
        ),
      );
    }
    return episodes;
  }

  Future<Map<String, dynamic>?> _node(String slug, {required int after}) async {
    final data = await _api.query(tedPlaylistQuery(slug, first: _talksPerRequest, after: after));
    final node = data['playlist'];
    return node is Map<String, dynamic> ? node : null;
  }
}
