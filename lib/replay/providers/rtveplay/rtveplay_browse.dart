import 'dart:math';

import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtveplay_api.dart';
import 'rtveplay_categories.dart';
import 'rtveplay_mapper.dart';
import 'rtveplay_pages.dart';
import 'rtveplay_programs.dart';

const _railLength = 30;
const _typeRails = 8;
const _channelPages = 8;

/// The landing page, the channel pages and the flat listings.
///
/// RTVE has no home-row endpoint, so rows are derived: the newest full episodes (one per programme, so a children's
/// channel cannot fill every row), the newest programmes, and a channel's programmes grouped by type.
class RtveBrowse {
  final RtvePlayApi _api;
  final DateTime Function() _now;
  final int pageSize;

  RtveBrowse(this._api, this._now, {required this.pageSize});

  Future<List<ReplayRail>> home() async {
    final fetched = await Future.wait([_latestEpisodes(), _newestPrograms()]);
    final episodes = fetched[0];
    return [..._episodeRails(episodes, moreLatest: true), _programRail(fetched[1])].where(_hasTitles).toList();
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId == rtveLatestBrowseId) return _episodeRails(await _latestEpisodes(), moreLatest: false);
    if (!isRtveChannelId(categoryId)) return const [];
    final programs = await _channelPrograms(categoryId);
    final newest = [...programs.where(rtveIsListable)]..sort(_newestFirst);
    final rails = [
      ReplayRail(id: 'new', title: 'Novedades', titles: rtveShows(newest.take(_railLength)), moreBrowseId: categoryId),
      for (final group in rtveGroupByType(programs).take(_typeRails))
        ReplayRail(id: 'type-${group.key}', title: group.key, titles: rtveShows(group.value.take(_railLength))),
    ];
    return rails.where(_hasTitles).toList();
  }

  Future<ReplayPage> listing(String browseId, int page) async {
    if (browseId == rtveLatestBrowseId) return _latestPage(page);
    final path = browseId == replayAllBrowseId
        ? 'programas.json'
        : isRtveChannelId(browseId)
        ? 'cadenas/$browseId/programas.json'
        : null;
    if (path == null) return const ReplayPage(titles: [], totalCount: 0);
    final body = await _api.catalogue(path, query: {'page': '${page + 1}', 'size': '$pageSize'});
    return ReplayPage(titles: rtveShows(rtveItems(body)), totalCount: rtveTotal(body));
  }

  /// RTVE serves only the first two pages of the global video list, so the newest 200 videos is all there is.
  Future<ReplayPage> _latestPage(int page) async {
    const apiPageSize = 100;
    const reachable = 2 * apiPageSize;
    final offset = page * pageSize;
    if (offset >= reachable) return const ReplayPage(titles: [], totalCount: reachable);
    final body = await _latestVideos(offset ~/ apiPageSize + 1);
    final start = offset % apiPageSize;
    final items = rtveItems(body).skip(start).take(pageSize);
    return ReplayPage(titles: _episodes(items), totalCount: min(rtveTotal(body), reachable));
  }

  Future<Map<String, dynamic>> _latestVideos(int page) =>
      _api.catalogue('videos.json', query: {'size': '100', 'type': '$rtveFullEpisodeType', 'page': '$page'});

  Future<List<Map<String, dynamic>>> _latestEpisodes() async {
    final pages = await Future.wait([_latestVideos(1), _latestVideos(2)]);
    return [for (final page in pages) ...rtveItems(page)];
  }

  Future<List<Map<String, dynamic>>> _newestPrograms() async {
    final body = await _api.catalogue('programas.json', query: {'page': '1', 'size': '50'});
    return rtveItems(body);
  }

  /// Every programme of a channel. The channel list is alphabetical and long, so a handful of pages is read at once.
  Future<List<Map<String, dynamic>>> _channelPrograms(String channelId) async {
    Future<Map<String, dynamic>> page(int n) =>
        _api.catalogue('cadenas/$channelId/programas.json', query: {'page': '$n', 'size': '100'});
    final first = await page(1);
    final last = min(rtveTotalPages(first), _channelPages);
    final rest = await Future.wait([for (var n = 2; n <= last; n++) page(n)]);
    return [...rtveItems(first), for (final body in rest) ...rtveItems(body)];
  }

  List<ReplayRail> _episodeRails(List<Map<String, dynamic>> videos, {required bool moreLatest}) {
    final rails = [
      ReplayRail(
        id: rtveLatestBrowseId,
        title: 'Última hora',
        titles: _episodes(_onePerProgram(videos).take(_railLength)),
        moreBrowseId: moreLatest ? rtveLatestBrowseId : null,
      ),
    ];
    for (final channel in rtveHomeChannels) {
      final own = videos.where((v) => (v['programInfo'] as Map?)?['channelPermalink'] == channel.permalink);
      rails.add(
        ReplayRail(
          id: 'new-${channel.permalink}',
          title: channel.title,
          titles: _episodes(_onePerProgram(own).take(_railLength)),
        ),
      );
    }
    return rails.where(_hasTitles).toList();
  }

  ReplayRail _programRail(List<Map<String, dynamic>> programs) => ReplayRail(
    id: 'new-programs',
    title: 'Programas nuevos',
    titles: rtveShows(programs).take(_railLength).toList(),
    moreBrowseId: replayAllBrowseId,
  );

  Iterable<Map<String, dynamic>> _onePerProgram(Iterable<Map<String, dynamic>> videos) {
    final seen = <String>{};
    return videos.where((v) => seen.add((v['programInfo'] as Map?)?['id']?.toString() ?? v['id'].toString()));
  }

  List<ReplayTitle> _episodes(Iterable<Map<String, dynamic>> videos) => [
    for (final video in videos) ?rtveTitleFromVideo(video, now: _now()),
  ];

  int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) =>
      ((b['publicationDateTimestamp'] as num?) ?? 0).compareTo((a['publicationDateTimestamp'] as num?) ?? 0);

  bool _hasTitles(ReplayRail rail) => rail.titles.isNotEmpty;
}
