import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'urplay_api.dart';
import 'urplay_categories.dart';
import 'urplay_mapper.dart';

/// The rows, listings and search of UR Play, all built from the one search endpoint.
class UrBrowse {
  static const _searchPages = 2;

  final UrPlayApi _api;

  UrBrowse(this._api);

  /// UR has no landing-page endpoint, so the rows are the newest programmes and series plus a few genres.
  Future<List<ReplayRail>> home() async {
    final rails = await Future.wait([
      _rail('newest-programs', 'Senaste program', const UrBrowseTarget('program'), newest: true),
      _rail('newest-series', 'Nya serier', const UrBrowseTarget('series'), newest: true),
      for (final genre in urHomeGenres) _rail('series:$genre', genre, UrBrowseTarget('series', genre)),
    ]);
    return [for (final rail in rails) ?rail];
  }

  Future<List<ReplayRail>> category(String genre) async {
    final rails = await Future.wait([
      _rail('series:$genre', 'Serier', UrBrowseTarget('series', genre)),
      _rail('program:$genre', 'Program', UrBrowseTarget('program', genre)),
    ]);
    return [for (final rail in rails) ?rail];
  }

  Future<ReplayPage> listing(String browseId, {required int page}) async {
    final target = UrBrowseTarget.parse(browseId, replayAllBrowseId);
    final Map<String, dynamic> body;
    try {
      body = await _api.search(target.query(start: page * urPageSize));
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 400) return const ReplayPage(titles: [], totalCount: 0);
      rethrow;
    }
    final results = (body['results'] as List?)?.length ?? 0;
    // UR reports no total, so the count grows by one page while a next page exists.
    final total = body['nextPageInfo'] == null ? page * urPageSize + results : (page + 2) * urPageSize;
    return ReplayPage(titles: urTitlesFromResults(body), totalCount: total);
  }

  /// Shows first, then single programmes: a title match on a show is what a viewer looking for a series wants.
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final titles = <ReplayTitle>[];
    final seen = <ReplayRef>{};
    var start = 0;
    for (var page = 0; page < _searchPages; page++) {
      final body = await _api.search({'query': trimmed, if (start > 0) 'start': '$start'});
      titles.addAll(urTitlesFromResults(body).where((t) => seen.add(t.ref)));
      final next = (body['nextPageInfo'] as Map?)?['start'];
      if (next is! int) break;
      start = next;
    }
    final shows = titles.where((t) => t.kind == ReplayKind.show);
    return [...shows, ...titles.where((t) => t.kind != ReplayKind.show)];
  }

  Future<ReplayRail?> _rail(String id, String title, UrBrowseTarget target, {bool newest = false}) async {
    try {
      final titles = urTitlesFromResults(await _api.search(target.query(newest: newest)));
      if (titles.isEmpty) return null;
      return ReplayRail(id: id, title: title, titles: titles, moreBrowseId: target.id);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 400) return null;
      rethrow;
    }
  }
}
