import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'rtveplay_api.dart';
import 'rtveplay_ids.dart';
import 'rtveplay_mapper.dart';
import 'rtveplay_pages.dart';

/// Videos RTVE returns per request, and how many requests one season or show may take (so 1,000 episodes).
const _pageSize = 100;
const _maxPages = 10;

/// Resolves show -> season -> episode for RTVE programmes.
///
/// Programmes with seasons list them as RTVE gives them. Daily shows, magazines and one-off series have none and get
/// a single synthetic season, so every show has the same two levels.
class RtveCatalog {
  final RtvePlayApi _api;
  final DateTime Function() _now;

  RtveCatalog(this._api, this._now);

  Future<ReplayTitle?> show(String programId) async {
    final record = await _firstItem('programas/$programId.json');
    return record == null ? null : rtveShowFromProgram(record);
  }

  Future<List<ReplayTitle>> seasons(String programId) async {
    final show = await this.show(programId);
    if (show == null) return const [];
    if ((show.childCount ?? 0) == 0) return [rtveSyntheticSeason(show)];
    final page = await _api.catalogue('programas/$programId/temporadas');
    final seasons = [for (final item in rtveItems(page)) ?rtveSeasonFromItem(item, show)];
    if (seasons.isEmpty) return [rtveSyntheticSeason(show)];
    seasons.sort((a, b) => (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0));
    return seasons;
  }

  Future<List<ReplayTitle>> episodes(RtveSeasonTarget season) async {
    final show = await this.show(season.programId);
    if (show == null) return const [];
    final seasonRef = rtveSeasonRef(season.programId, season.seasonId);
    final number = season.isSynthetic ? null : await _seasonNumber(season);
    final path = season.isSynthetic
        ? 'programas/${season.programId}/videos'
        : 'programas/${season.programId}/temporadas/${season.seasonId}/videos';
    final context = RtveContext(season: seasonRef, seasonNumber: number);
    final titles = <ReplayTitle>[];
    final seen = <ReplayRef>{};
    var pages = 1;
    for (var page = 1; page <= pages && page <= _maxPages; page++) {
      final body = await _api.catalogue(
        path,
        query: {'type': '$rtveFullEpisodeType', 'size': '$_pageSize', 'page': '$page'},
      );
      pages = rtveTotalPages(body);
      for (final item in rtveItems(body)) {
        final title = rtveTitleFromVideo(item, context: context, now: _now());
        if (title != null && seen.add(title.ref)) titles.add(title);
      }
    }
    return _inViewingOrder(titles);
  }

  /// One video with its show and season, or null when RTVE no longer has it.
  Future<ReplayTitle?> video(String videoId) async {
    final record = await _firstItem('videos/$videoId.json');
    return record == null ? null : rtveTitleFromVideo(record, now: _now());
  }

  Future<int?> _seasonNumber(RtveSeasonTarget season) async {
    final seasons = await this.seasons(season.programId);
    final ref = rtveSeasonRef(season.programId, season.seasonId);
    return seasons.where((s) => s.ref == ref).firstOrNull?.seasonNumber;
  }

  /// RTVE lists newest first. When every episode has a number the season reads in order, otherwise the list keeps
  /// RTVE's order: dated editions of a news show have no meaningful number.
  List<ReplayTitle> _inViewingOrder(List<ReplayTitle> titles) {
    if (titles.any((t) => t.episodeNumber == null)) return titles;
    final listed = {for (var i = 0; i < titles.length; i++) titles[i].ref: i};
    return [...titles]..sort((a, b) {
      final byNumber = a.episodeNumber!.compareTo(b.episodeNumber!);
      return byNumber != 0 ? byNumber : listed[a.ref]!.compareTo(listed[b.ref]!);
    });
  }

  /// The first record of a document, or null when RTVE answers 404 or an empty page.
  Future<Map<String, dynamic>?> _firstItem(String path) async {
    try {
      return rtveItems(await _api.catalogue(path)).firstOrNull;
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
