import '../../model/replay_title.dart';
import 'dw_api.dart';
import 'dw_ids.dart';
import 'dw_mapper.dart';
import 'dw_search.dart';

/// First year DW English has videos in the search index; earlier years are never asked for.
const _firstYear = 2005;

/// Episodes returned for one season. A news programme has thousands a year, so the newest are kept.
const dwMaxEpisodesPerSeason = 300;
const _pageSize = 100;

/// A slice of a larger list, with the size of the whole.
typedef DwPage = ({List<ReplayTitle> titles, int total});

/// Resolves the show -> season -> episode structure of DW's English video programmes.
///
/// A programme is a show, a season is one calendar year of it, and its episodes are the videos published that year.
class DwCatalog {
  final DwApi _api;
  final DateTime Function() _clock;

  DwCatalog(this._api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Every video programme, A to Z.
  Future<List<ReplayTitle>> programmes() async {
    final document = await _api.graph('programs-overview');
    final list = dwMap(dwMap(document?['data'])?['programsOverview'])?['videoPrograms'];
    final shows = [
      for (final p in (list is List ? list : const []).whereType<Map<String, dynamic>>()) ?dwShowFromProgramme(p),
    ];
    shows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return shows;
  }

  /// One programme by id, or null when [id] is not a programme.
  Future<ReplayTitle?> show(int id) async {
    final document = await _api.graph('content/unified-program/$id');
    final content = dwMap(dwMap(document?['data'])?['content']);
    if (content == null || content['__typename'] != 'UnifiedProgram') return null;
    return dwShowFromProgramme(content);
  }

  /// One video by id, or null when DW has no such video.
  Future<ReplayTitle?> video(int id) async {
    final document = await _api.graph('content/video/$id');
    final content = dwMap(dwMap(document?['data'])?['content']);
    return content == null ? null : dwVideoFromContent(content);
  }

  Future<List<ReplayTitle>> seasons(int programme) async {
    final parent = await show(programme);
    if (parent == null) return const [];
    final counts = dwYearCounts(
      await _api.search(dwYearCountsQuery(programme: programme, firstYear: _firstYear, lastYear: _clock().year)),
    );
    return [
      for (final year in counts.keys.toList()..sort())
        ReplayTitle(
          ref: dwRef(dwSeasonId(programme, year)),
          kind: ReplayKind.season,
          title: '$year',
          posterUrl: parent.posterUrl,
          backdropUrl: parent.backdropUrl,
          seasonNumber: year,
          childCount: counts[year],
          showRef: parent.ref,
          showTitle: parent.title,
        ),
    ];
  }

  /// The videos of one year of a programme in broadcast order, newest [dwMaxEpisodesPerSeason] at most.
  Future<List<ReplayTitle>> episodes(int programme, int year) async {
    final titles = <ReplayTitle>[];
    for (var page = 1; titles.length < dwMaxEpisodesPerSeason; page++) {
      final response = await _api.search(dwVideoQuery(programme: programme, year: year, page: page, size: _pageSize));
      final hits = dwHits(response);
      titles.addAll(_titles(hits, programme: programme));
      if (hits.length < _pageSize || titles.length >= dwTotalHits(response)) break;
    }
    final kept = titles.take(dwMaxEpisodesPerSeason).toList();
    return kept.reversed.toList();
  }

  /// A zero-based [page] of videos, newest first, across every programme or inside one.
  Future<DwPage> videos({int? programme, int page = 0, int size = 30}) async {
    if ((page + 1) * size > dwSearchWindow) return (titles: const <ReplayTitle>[], total: 0);
    final response = await _api.search(dwVideoQuery(programme: programme, page: page + 1, size: size));
    return (titles: _titles(dwHits(response), programme: programme), total: dwTotalHits(response));
  }

  /// Programmes whose name contains [query], then the best matching videos.
  Future<List<ReplayTitle>> search(String query) async {
    final needle = query.toLowerCase();
    final shows = [
      for (final show in await programmes())
        if ('${show.title} ${show.subtitle ?? ''}'.toLowerCase().contains(needle)) show,
    ];
    final response = await _api.search(dwVideoQuery(query: query));
    return [...shows, ..._titles(dwHits(response))];
  }

  List<ReplayTitle> _titles(List<Map<String, dynamic>> hits, {int? programme}) => [
    for (final hit in hits) ?dwVideoFromHit(hit, programme: programme),
  ];
}
