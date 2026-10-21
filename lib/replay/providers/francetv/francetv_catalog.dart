import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'francetv_api.dart';
import 'francetv_availability.dart';
import 'francetv_mapper.dart';
import 'francetv_numbering.dart';
import 'francetv_refs.dart';

/// Episodes per request, and the cap on requests for one programme (a daily news show has hundreds).
const _pageSize = 100;
const _maxPages = 10;

/// Videos checked per season to guess the rights of the others.
const _sampleSize = 3;

/// Resolves the show -> season -> episode structure of France.tv programmes.
///
/// A programme with season rows gets one season each, read from the page because season paths are
/// irregular. A programme with a single flat list of episodes gets one season, or one per season number
/// when the episodes themselves say they belong to several.
class FranceTvCatalog {
  final FranceTvApi _api;
  final FranceTvAvailability _availability;
  final FranceTvMapper _mapper;

  FranceTvCatalog(this._api, this._availability, this._mapper);

  Future<ReplayTitle?> show(String programPath) async {
    try {
      return _mapper.show(await _api.mobile('apps/program/meta/$programPath'));
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ReplayTitle>> seasons(String showPath) async {
    final page = await _api.mobile('apps/program/$showPath', query: {'size': '1'});
    final show = _mapper.show(page['item'] as Map<String, dynamic>? ?? const {});
    final rows = _seasonRows(page);
    if (rows.isNotEmpty) return _fromRows(rows, showPath, show);

    final episodes = await _flatEpisodes(showPath);
    if (episodes.isEmpty) return const [];
    final numbers = {for (final e in episodes) ?franceTvNumbers(e).season}.toList()..sort();
    if (numbers.length < 2) return [_season(showPath, franceTvAllEpisodesKey, 1, show, count: episodes.length)];
    return [
      for (final n in numbers)
        _season(
          showPath,
          '$franceTvDerivedSeasonPrefix$n',
          n,
          show,
          count: episodes.where((e) => franceTvNumbers(e).season == n).length,
        ),
    ];
  }

  Future<List<ReplayTitle>> episodes(FranceTvSeasonTarget season) async {
    final first = await _api.mobile('apps/program/${season.episodesPath}', query: _pageQuery(0));
    final items = await _allEpisodeItems(season.episodesPath, first);
    final derived = season.derivedNumber;
    final selected = derived == null
        ? items
        : [
            for (final e in items)
              if (franceTvNumbers(e).season == derived) e,
          ];
    if (selected.isEmpty) return const [];

    final pageItem = first['item'] as Map<String, dynamic>? ?? const {};
    final isShowPage = season.episodesPath == season.showPath;
    final showTitle = await _showTitle(season, selected, isShowPage ? pageItem : null);
    final number = derived ?? _seasonNumber(pageItem, isShowPage);
    final context = FranceTvContext(
      show: franceTvShowRef(season.showPath),
      showTitle: showTitle,
      season: franceTvSeasonRef(season.showPath, season.key),
      seasonNumber: number,
    );

    final sample = await _sampleRights(selected);
    final mapper = _mapper.withVerdicts((id) => _availability.known(id) ?? sample);
    return _ordered(mapper.titles(selected, context: context));
  }

  /// Checks a few playable episodes. When every one is geoblocked the rest of the season almost certainly is
  /// too, so it is returned as the guess for videos that were not checked.
  Future<ReplayAvailability?> _sampleRights(List<Map<String, dynamic>> items) async {
    final open = [
      for (final title in _mapper.titles(items))
        if (title.availability == ReplayAvailability.playable) title,
    ];
    if (open.isEmpty) return null;
    final ids = [for (final t in open.take(_sampleSize)) _streamId(t)];
    await _availability.probe(ids, limit: _sampleSize);
    final verdicts = [for (final id in ids) _availability.known(id)];
    final allBlocked = verdicts.every((v) => v == ReplayAvailability.geoBlocked);
    return allBlocked ? ReplayAvailability.geoBlocked : null;
  }

  String _streamId(ReplayTitle title) => (franceTvTarget(title.ref) as FranceTvVideoTarget).streamId;

  Future<List<Map<String, dynamic>>> _flatEpisodes(String path) async {
    final first = await _api.mobile('apps/program/$path', query: _pageQuery(0));
    return _allEpisodeItems(path, first);
  }

  Future<List<Map<String, dynamic>>> _allEpisodeItems(String path, Map<String, dynamic> first) async {
    var items = _episodeRow(first);
    final all = [...items];
    for (var page = 1; items.length >= _pageSize && page < _maxPages; page++) {
      items = _episodeRow(await _api.mobile('apps/program/$path', query: _pageQuery(page)));
      all.addAll(items);
    }
    return all;
  }

  Map<String, String> _pageQuery(int page) => {'page': '$page', 'size': '$_pageSize'};

  /// The first plain video row of a programme page: the programme's own episodes.
  List<Map<String, dynamic>> _episodeRow(Map<String, dynamic> page) {
    final rows = page['collections'];
    if (rows is! List) return const [];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if (row['type'] == 'playlist_video' && row['item'] == null) {
        return (row['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
      }
    }
    return const [];
  }

  List<Map<String, dynamic>> _seasonRows(Map<String, dynamic> page) {
    final rows = page['collections'];
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['type'] == 'playlist_video' && row['item'] is Map && (row['item'] as Map)['program_path'] is String)
          row,
    ];
  }

  List<ReplayTitle> _fromRows(List<Map<String, dynamic>> rows, String showPath, ReplayTitle? show) {
    final seasons = <ReplayTitle>[];
    for (var i = 0; i < rows.length; i++) {
      final item = rows[i]['item'] as Map<String, dynamic>;
      final count = (item['integral_counter'] as num?)?.toInt() ?? (rows[i]['items'] as List?)?.length;
      if (count == 0) continue;
      final number = int.tryParse('${item['saison']}') ?? _numberInLabel(rows[i]['label']) ?? i + 1;
      seasons.add(
        _season(
          showPath,
          item['program_path'] as String,
          number,
          show,
          title: rows[i]['label'] as String?,
          count: count,
        ),
      );
    }
    seasons.sort((a, b) => a.seasonNumber!.compareTo(b.seasonNumber!));
    return seasons;
  }

  ReplayTitle _season(String showPath, String key, int number, ReplayTitle? show, {String? title, int? count}) {
    return ReplayTitle(
      ref: franceTvSeasonRef(showPath, key),
      kind: ReplayKind.season,
      title: title ?? (key == franceTvAllEpisodesKey ? show?.title : null) ?? 'Saison $number',
      posterUrl: show?.posterUrl,
      backdropUrl: show?.backdropUrl,
      seasonNumber: number,
      childCount: count,
      showRef: franceTvShowRef(showPath),
      showTitle: show?.title,
    );
  }

  int? _numberInLabel(Object? label) =>
      label is String ? int.tryParse(RegExp(r'\d+').firstMatch(label)?.group(0) ?? '') : null;

  int _seasonNumber(Map<String, dynamic> pageItem, bool isShowPage) =>
      isShowPage ? 1 : int.tryParse('${pageItem['saison']}') ?? 1;

  Future<String?> _showTitle(
    FranceTvSeasonTarget season,
    List<Map<String, dynamic>> items,
    Map<String, dynamic>? pageItem,
  ) async {
    final fromPage = pageItem?['label'] as String?;
    if (fromPage != null) return fromPage;
    final fromEpisodes = (items.first['program'] as Map?)?['label'] as String?;
    return fromEpisodes ?? (await show(season.showPath))?.title;
  }

  /// Numbered episodes first in order; when none is numbered, the newest first, as a replay shelf reads.
  List<ReplayTitle> _ordered(List<ReplayTitle> titles) {
    final numbered = titles.any((t) => t.episodeNumber != null);
    final sorted = [...titles];
    sorted.sort((a, b) {
      if (numbered) {
        final byNumber = (a.episodeNumber ?? 1 << 30).compareTo(b.episodeNumber ?? 1 << 30);
        if (byNumber != 0) return byNumber;
        return _compareDates(a.airDate, b.airDate);
      }
      return _compareDates(b.airDate, a.airDate);
    });
    return sorted;
  }

  int _compareDates(DateTime? a, DateTime? b) => (a ?? DateTime.utc(0)).compareTo(b ?? DateTime.utc(0));
}
