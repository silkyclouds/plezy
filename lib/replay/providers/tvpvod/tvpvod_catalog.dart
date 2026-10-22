import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'tvpvod_api.dart';
import 'tvpvod_mapper.dart';
import 'tvpvod_numbering.dart';
import 'tvpvod_refs.dart';
import 'tvpvod_rights.dart';

/// Resolves the show -> season -> episode structure of TVP VOD.
///
/// A season ref is `serialId/seasonId`. Episodes carry their own show and season, so a season list is only fetched
/// for the artwork and title of the show it belongs to.
class TvpCatalog {
  final TvpVodApi _api;
  final TvpRights _rights;

  TvpCatalog(this._api, this._rights);

  /// One show, film or episode by product id, or null when the site no longer has it.
  Future<ReplayTitle?> title(String productId) async {
    final product = await _product(productId);
    return product == null ? null : tvpTitleFromItem(product);
  }

  Future<ReplayTitle?> season(String serialId, String seasonId) async {
    final seasons = await this.seasons(serialId);
    return seasons.where((s) => s.ref == tvpSeasonRef(serialId, seasonId)).firstOrNull;
  }

  /// The seasons of a show, by number. Long-running soaps are cut into blocks of episodes that the site calls seasons.
  Future<List<ReplayTitle>> seasons(String serialId) async {
    final product = await _product(serialId);
    final show = product == null ? null : tvpTitleFromItem(product);
    if (show == null || show.kind != ReplayKind.show) return const [];
    final raw = await _api.products('vods/serials/$serialId/seasons');
    if (raw is! List) return const [];
    final entries = raw.whereType<Map<String, dynamic>>().toList();
    final seasons = [for (var i = 0; i < entries.length; i++) _season(entries[i], i + 1, show)];
    return tvpOrderSeasons(seasons);
  }

  Future<List<ReplayTitle>> episodes(String serialId, String seasonId) async {
    final raw = await _api.products('vods/serials/$serialId/seasons/$seasonId/episodes');
    if (raw is! List) return const [];
    final context = TvpContext(season: tvpSeasonRef(serialId, seasonId));
    final episodes = <ReplayTitle>[];
    for (final item in raw.whereType<Map<String, dynamic>>()) {
      final episode = tvpTitleFromItem(item, context: context);
      if (episode != null && episode.kind == ReplayKind.episode) episodes.add(episode);
    }
    final newestFirst = _newestFirst(raw);
    return tvpOrderEpisodes(episodes, newestFirst: newestFirst);
  }

  /// Where the end credits start, so the player can offer to skip them. Absent for most titles.
  Future<ReplayCredits?> credits(String productId) async {
    final Map<String, dynamic>? product;
    try {
      product = await _product(productId);
    } on MediaServerHttpException {
      return null;
    }
    final start = (product?['creditsTime'] as num?)?.toInt();
    final end = (product?['duration'] as num?)?.toInt();
    if (start == null || end == null || start <= 0 || end <= start) return null;
    return ReplayCredits(
      start: Duration(seconds: start),
      end: Duration(seconds: end),
    );
  }

  ReplayTitle _season(Map<String, dynamic> entry, int ordinal, ReplayTitle show) {
    final number = entry['number'];
    final title = (entry['title'] as String?)?.trim();
    return ReplayTitle(
      ref: tvpSeasonRef(show.ref.nativeId, entry['id']),
      kind: ReplayKind.season,
      title: title == null || title.isEmpty ? 'Sezon $ordinal' : title,
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: number is num && number > 0 ? number.toInt() : ordinal,
      showRef: show.ref,
      showTitle: show.title,
      availability: show.availability,
    );
  }

  /// The listing order is on every episode's parent show; it decides how unnumbered episodes are flipped.
  bool _newestFirst(List<dynamic> episodes) {
    for (final item in episodes.whereType<Map>()) {
      final season = item['season'];
      final serial = season is Map ? season['serial'] : null;
      if (serial is Map) return serial['sortType'] == 'DESC';
    }
    return false;
  }

  Future<Map<String, dynamic>?> _product(String id) async {
    try {
      final product = await _api.products('vods/$id');
      if (product is! Map<String, dynamic>) return null;
      _rights.learn(product);
      return product;
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
