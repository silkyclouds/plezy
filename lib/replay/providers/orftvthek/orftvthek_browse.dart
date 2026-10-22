import 'dart:async';

import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'orftvthek_api.dart';
import 'orftvthek_json.dart';
import 'orftvthek_mapper.dart';
import 'orftvthek_profiles.dart';

const _recent = 'recent';
const _lanePrefix = 'lane:';
const _genreEpisodesPrefix = 'genre-episodes:';
const _genreShowsPrefix = 'genre-shows:';

/// The landing page, the genre pages and the flat listings behind their "see all" links.
class OrfBrowse {
  static const pageSize = 30;
  static const _railSize = 20;
  static const _maxLanes = 7;

  final OrfApi _api;
  final OrfProfileIndex _index;
  final OrfMapper _mapper;

  OrfBrowse(this._api, this._index, this._mapper);

  Future<List<ReplayCategory>> categories() async {
    final page = await _api.genres();
    return [
      for (final genre in orfItems(page))
        if (orfInt(genre['id']) case final id? when orfString(genre['title']) != null)
          ReplayCategory(id: '$id', title: orfString(genre['title'])!),
    ];
  }

  /// The hero row, the newest programmes and ORF's editorial lanes, in the order the web app shows them.
  Future<List<ReplayRail>> home() async {
    final rows = orfMaps(await _api.pageStart());
    final lanes = [
      for (final row in rows)
        if (row['type'] == 'lane' || row['type'] == 'mostviewed') row,
    ].take(_maxLanes);
    final hero = rows.any((row) => row['type'] == 'hero');
    final rails = await Future.wait([
      if (hero) _tolerated(_highlights),
      _tolerated(_recentRail),
      for (final lane in lanes) _tolerated(() => _laneRail(lane)),
    ]);
    return [
      for (final rail in rails)
        if (rail != null && rail.titles.isNotEmpty) rail,
    ];
  }

  Future<List<ReplayRail>> category(String genreId) async {
    final rails = await Future.wait([
      _tolerated(() async {
        final page = await _api.genreEpisodes(genreId, limit: _railSize);
        return ReplayRail(
          id: 'genre-episodes',
          title: 'Neueste Folgen',
          titles: _programmes(orfItems(page)),
          moreBrowseId: '$_genreEpisodesPrefix$genreId',
        );
      }),
      _tolerated(() async {
        final page = await _api.genreProfiles(genreId, limit: _railSize);
        return ReplayRail(
          id: 'genre-shows',
          title: 'Sendungen',
          titles: _shows(orfItems(page)),
          moreBrowseId: '$_genreShowsPrefix$genreId',
        );
      }),
    ]);
    return [
      for (final rail in rails)
        if (rail != null && rail.titles.isNotEmpty) rail,
    ];
  }

  /// One page of a flat listing; [page] is zero-based.
  Future<ReplayPage> listing(String browseId, int page) async {
    final number = page + 1;
    if (browseId == replayAllBrowseId) return _allShows(page);
    if (browseId == _recent) return _programmePage(await _api.episodes(page: number, limit: pageSize));
    if (browseId.startsWith(_lanePrefix)) {
      final lane = await _api.lane(browseId.substring(_lanePrefix.length), page: number, limit: pageSize);
      return _programmePage(lane);
    }
    if (browseId.startsWith(_genreEpisodesPrefix)) {
      final id = browseId.substring(_genreEpisodesPrefix.length);
      return _programmePage(await _api.genreEpisodes(id, page: number, limit: pageSize));
    }
    if (browseId.startsWith(_genreShowsPrefix)) {
      final id = browseId.substring(_genreShowsPrefix.length);
      final profiles = await _api.genreProfiles(id, page: number, limit: pageSize);
      return ReplayPage(titles: _shows(orfItems(profiles)), totalCount: orfTotal(profiles) ?? 0);
    }
    return const ReplayPage(titles: [], totalCount: 0);
  }

  Future<ReplayPage> _allShows(int page) async {
    final groups = await _index.groups();
    final start = page * pageSize;
    final slice = start >= groups.length ? const <OrfShowGroup>[] : groups.skip(start).take(pageSize);
    return ReplayPage(titles: [for (final group in slice) _mapper.groupShow(group)], totalCount: groups.length);
  }

  ReplayPage _programmePage(Map<String, dynamic> page) {
    final titles = _programmes(orfItems(page));
    return ReplayPage(titles: titles, totalCount: orfTotal(page) ?? titles.length);
  }

  Future<ReplayRail> _highlights() async {
    final items = [
      for (final row in orfMaps(await _api.highlights()))
        ?orfMap(orfMap(orfMap(orfMap(row['_embedded'])?['video_item'])?['_embedded'])?['item']),
    ];
    return ReplayRail(id: 'highlights', title: 'Highlights', titles: _programmes(items));
  }

  Future<ReplayRail> _recentRail() async {
    final page = await _api.episodes(limit: _railSize);
    return ReplayRail(id: _recent, title: 'Neueste Folgen', titles: _programmes(orfItems(page)), moreBrowseId: _recent);
  }

  Future<ReplayRail> _laneRail(Map<String, dynamic> row) async {
    final id = '${row['id']}';
    final lane = await _api.lane(id, limit: _railSize);
    return ReplayRail(
      id: 'lane-$id',
      title: orfString(lane['title']) ?? orfString(row['title']) ?? 'Derzeit beliebt',
      titles: _programmes(orfItems(lane)),
      moreBrowseId: '$_lanePrefix$id',
    );
  }

  /// Programmes and chapters of a list, without the sign-language versions that repeat a plain programme.
  List<ReplayTitle> _programmes(List<Map<String, dynamic>> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (item['is_oegs'] != true)
          if (_mapper.listed(item) case final title? when seen.add(title.ref.nativeId)) title,
    ];
  }

  List<ReplayTitle> _shows(List<Map<String, dynamic>> profiles) {
    final seen = <String>{};
    return [
      for (final profile in profiles)
        if (_mapper.profileShow(profile) case final show? when seen.add(show.ref.nativeId)) show,
    ];
  }

  /// A row that fails (a lane ORF removed, a rate limit) must not take the whole page with it.
  Future<ReplayRail?> _tolerated(Future<ReplayRail> Function() build) async {
    try {
      return await build();
    } on MediaServerHttpException {
      return null;
    } on OrfRateLimitedException {
      return null;
    }
  }
}
