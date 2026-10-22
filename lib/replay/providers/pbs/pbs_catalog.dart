import 'dart:math';

import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'pbs_api.dart';
import 'pbs_categories.dart';
import 'pbs_flight.dart';
import 'pbs_ids.dart';
import 'pbs_mapper.dart';
import 'pbs_pages.dart';

/// The search index only fills its "popular shows" row for a query it can answer, and any text will do.
const _popularQuery = 'zzzz';
const _searchShowLimit = 12;

/// Browsing and search over pbs.org: genre pages, show pages, season lists and the search index.
class PbsCatalog {
  final PbsApi _api;
  final PbsPages _pages;

  PbsCatalog(this._api, this._pages);

  Future<List<ReplayRail>> home() async {
    final popular = _showTitles(_collection(await _api.search(_popularQuery, limit: 1), 'popular-shows'));
    final front = await _pages.front();
    return [
      if (popular.isNotEmpty) ReplayRail(id: 'popular', title: 'Popular shows', titles: popular),
      ..._rails('home', front.rows),
    ];
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    if (!isPbsCategory(categoryId)) return const [];
    return _rails(categoryId, (await _pages.genre(categoryId)).rows);
  }

  /// Every show of one genre, or of all genres, by name. PBS has no list of all shows for a visitor without a station.
  Future<ReplayPage> listing(String browseId, {required int page, required int pageSize}) async {
    final shows = browseId == replayAllBrowseId
        ? await _allShows()
        : isPbsCategory(browseId)
        ? (await _pages.genre(browseId)).shows
        : const <Map<String, dynamic>>[];
    final titles = _showTitles(shows)..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final from = page * pageSize;
    final slice = from >= titles.length
        ? const <ReplayTitle>[]
        : titles.sublist(from, min(from + pageSize, titles.length));
    return ReplayPage(titles: slice, totalCount: titles.length);
  }

  /// Matching shows first, then matching videos. Passport-only videos are not requested.
  Future<List<ReplayTitle>> search(String query) async {
    final body = await _api.search(query);
    final shows = _showTitles(_collection(body, 'show-results')).take(_searchShowLimit);
    final seen = <ReplayRef>{};
    final videos = [
      for (final raw in _collection(body, 'videoasset-results'))
        if (pbsVideoTitle(raw) case final video? when seen.add(video.ref)) video,
    ];
    return [...shows, ...videos];
  }

  Future<ReplayTitle?> show(String slug) async {
    final page = await _pages.show(slug);
    return page == null ? null : pbsShowTitle(page.show);
  }

  Future<ReplayTitle?> season(PbsSeasonId id) async {
    final ref = pbsSeasonRef(id.showSlug, id.seasonKey);
    return (await seasons(id.showSlug)).where((s) => s.ref == ref).firstOrNull;
  }

  /// A video's own page knows its show, season and episode even when the video itself is refused here.
  Future<ReplayTitle?> video(PbsVideoId id) async {
    final html = await _api.page('/video/${id.slug}/');
    if (html == null) return null;
    final records = [
      for (final record in pbsItems(pbsFlightValues(html), 'video'))
        if (record['slug'] == id.slug) record,
    ]..sort((a, b) => b.length.compareTo(a.length));
    return records.isEmpty ? null : pbsVideoTitle(records.first);
  }

  /// Seasons that hold full episodes, clips or previews, oldest first, then the specials.
  Future<List<ReplayTitle>> seasons(String slug) async {
    final page = await _pages.show(slug);
    final show = page == null ? null : pbsShowTitle(page.show);
    if (page == null || show == null) return const [];
    return [
      for (final season in page.seasons)
        if (_hasContent(season)) pbsSeasonTitle(season, show, slug),
      if (page.specials.isNotEmpty) pbsSpecialsTitle(show, slug, page.specials.length),
    ];
  }

  /// Episodes of a season in episode order. A season without full episodes lists its clips and previews instead.
  Future<List<ReplayTitle>> episodes(PbsSeasonId id) async {
    final season = pbsSeasonRef(id.showSlug, id.seasonKey);
    if (id.isSpecials) return _specials(id, season);

    final context = PbsContext(show: pbsShowRef(id.showSlug), season: season, inSeason: true);
    var records = await _api.seasonEpisodes(id.showSlug, id.seasonKey);
    if (records.isEmpty) records = await _api.seasonExtras(id.showSlug, id.seasonKey);
    final titles = _videoTitles(records, context);
    final byNumber = titles.where((t) => t.kind == ReplayKind.episode).toList()..sort(_byEpisode);
    return [...byNumber, ...titles.where((t) => t.kind != ReplayKind.episode)];
  }

  Future<List<ReplayTitle>> _specials(PbsSeasonId id, ReplayRef season) async {
    final page = await _pages.show(id.showSlug);
    if (page == null) return const [];
    final show = pbsShowTitle(page.show);
    final context = PbsContext(
      show: pbsShowRef(id.showSlug),
      showTitle: show?.title,
      season: season,
      seasonNumber: 0,
      inSeason: true,
    );
    return _videoTitles(page.specials, context);
  }

  List<ReplayTitle> _videoTitles(List<Map<String, dynamic>> records, PbsContext context) {
    final seen = <ReplayRef>{};
    return [
      for (final raw in records)
        if (pbsVideoTitle(raw, context: context) case final video? when seen.add(video.ref)) video,
    ];
  }

  Future<List<Map<String, dynamic>>> _allShows() async {
    final distinct = <String, Map<String, dynamic>>{};
    for (final category in pbsCategories) {
      for (final show in (await _pages.genre(category.id)).shows) {
        distinct.putIfAbsent(show['slug'] as String, () => show);
      }
    }
    return distinct.values.toList();
  }

  List<ReplayRail> _rails(String prefix, List<PbsShowRow> rows) => [
    for (var i = 0; i < rows.length; i++)
      if (_showTitles(rows[i].shows) case final titles when titles.isNotEmpty)
        ReplayRail(id: '$prefix-$i', title: rows[i].title, titles: titles),
  ];

  List<ReplayTitle> _showTitles(List<Map<String, dynamic>> records) {
    final seen = <ReplayRef>{};
    return [
      for (final raw in records)
        if (pbsShowTitle(raw) case final show? when seen.add(show.ref)) show,
    ];
  }

  List<Map<String, dynamic>> _collection(Map<String, dynamic> body, String slug) {
    final collections = body['collections'];
    if (collections is! List) return const [];
    for (final collection in collections.whereType<Map<String, dynamic>>()) {
      if (collection['slug'] != slug) continue;
      final content = collection['content'];
      return content is List ? content.whereType<Map<String, dynamic>>().toList() : const [];
    }
    return const [];
  }

  bool _hasContent(Map<String, dynamic> season) {
    final flags = season['flags'] as Map? ?? const {};
    return flags['has_episodes'] == true || flags['has_assets'] == true;
  }

  int _byEpisode(ReplayTitle a, ReplayTitle b) {
    final left = a.episodeNumber;
    final right = b.episodeNumber;
    if (left != null && right != null && left != right) return left.compareTo(right);
    if (left != null && right == null) return -1;
    if (left == null && right != null) return 1;
    final dateA = a.airDate;
    final dateB = b.airDate;
    return dateA != null && dateB != null ? dateA.compareTo(dateB) : 0;
  }
}
