import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nhkworld_api.dart';
import 'nhkworld_ids.dart';
import 'nhkworld_mapper.dart';
import 'nhkworld_numbering.dart';

/// Resolves the show -> season -> episode structure of NHK programmes.
///
/// The API has programmes and episodes only. A season is the year of first broadcast, see `nhkNumberSeason`.
class NhkWorldCatalog {
  final NhkWorldApi _api;
  final DateTime Function() _clock;

  NhkWorldCatalog(this._api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Programmes that have at least one episode online, in alphabetical order, optionally of one category.
  Future<List<ReplayTitle>> programmes({String? categoryId}) async {
    final index = await _index(categoryId: categoryId);
    return [for (final program in index) nhkShowTitle(program)];
  }

  /// Programmes whose title (first) or synopsis contains every word of [query].
  Future<List<ReplayTitle>> search(String query) async {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final inTitle = <ReplayTitle>[];
    final inSynopsis = <ReplayTitle>[];
    for (final program in await _index()) {
      final title = _words(program['title'] as String? ?? '');
      if (words.every((w) => title.any((t) => t.contains(w)))) {
        inTitle.add(nhkShowTitle(program));
      } else if (_containsAll(program['description'] as String? ?? '', words)) {
        inSynopsis.add(nhkShowTitle(program));
      }
    }
    return [...inTitle, ...inSynopsis];
  }

  Future<ReplayTitle?> show(String programId) async {
    final program = await _api.programme(programId);
    return program == null || !nhkProgramHasVideo(program) ? null : nhkShowTitle(program);
  }

  /// One season per year with an episode online, oldest first.
  Future<List<ReplayTitle>> seasons(String programId) async {
    final program = await _api.programme(programId);
    if (program == null) return const [];
    final show = nhkShowTitle(program);
    final byYear = _groupByYear(await _episodes(programId));
    return [
      for (final year in byYear.keys.toList()..sort())
        ReplayTitle(
          ref: nhkSeasonRef(programId, year),
          kind: ReplayKind.season,
          title: '$year',
          posterUrl: show.posterUrl,
          backdropUrl: show.backdropUrl,
          seasonNumber: year,
          childCount: byYear[year]!.length,
          showRef: show.ref,
          showTitle: show.title,
        ),
    ];
  }

  /// The episodes of a season ref (`p/<programme>/<year>`), numbered.
  Future<List<ReplayTitle>> episodes(ReplayRef season) async {
    final target = parseNhkNativeId(season.nativeId);
    if (target == null || target.kind != NhkTargetKind.season) return const [];
    final inYear = _groupByYear(await _episodes(target.id))[target.year];
    if (inYear == null) return const [];
    final now = _clock();
    return [for (final e in nhkNumberSeason(inYear)) nhkEpisodeTitle(e.item, now: now, episodeNumber: e.number)];
  }

  /// One episode with the number its season gives it, or null when the broadcaster no longer lists it.
  Future<ReplayTitle?> episode(String id) async {
    final item = await _api.item(clip: false, id: id, ttl: NhkWorldApi.listTtl);
    if (item == null) return null;
    final now = _clock();
    final programId = (item['video_program'] as Map?)?['id'] as String?;
    if (programId == null) return nhkEpisodeTitle(item, now: now);
    final siblings = _groupByYear(await _episodes(programId))[nhkSeasonYear(item, now)] ?? const [];
    final numbered = nhkNumberSeason(siblings).where((e) => e.item['id'] == id).firstOrNull;
    return nhkEpisodeTitle(item, now: now, episodeNumber: numbered?.number);
  }

  Future<ReplayTitle?> clip(String id) async {
    final item = await _api.item(clip: true, id: id, ttl: NhkWorldApi.listTtl);
    return item == null ? null : nhkEpisodeTitle(item, now: _clock());
  }

  Future<List<Map<String, dynamic>>> _index({String? categoryId}) async {
    final path = categoryId == null ? 'video_programs' : 'categories/$categoryId/video_programs';
    try {
      final all = await _api.allItems(path, ttl: NhkWorldApi.indexTtl);
      return [
        for (final program in all)
          if (nhkProgramHasVideo(program)) program,
      ]..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _episodes(String programId) =>
      _api.allItems('video_programs/$programId/video_episodes', query: {'sort': 'date'});

  Map<int, List<Map<String, dynamic>>> _groupByYear(List<Map<String, dynamic>> episodes) {
    final now = _clock();
    final byYear = <int, List<Map<String, dynamic>>>{};
    for (final episode in episodes) {
      byYear.putIfAbsent(nhkSeasonYear(episode, now), () => []).add(episode);
    }
    return byYear;
  }

  String _sortKey(Map<String, dynamic> program) =>
      (program['sort_key'] as String? ?? program['title'] as String? ?? '').toUpperCase();

  bool _containsAll(String text, List<String> words) {
    final haystack = _words(text).join(' ');
    return words.every(haystack.contains);
  }

  List<String> _words(String text) => [
    for (final word in text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
      if (word.isNotEmpty) word,
  ];
}
