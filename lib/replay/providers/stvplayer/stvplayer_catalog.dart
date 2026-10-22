import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'stvplayer_api.dart';
import 'stvplayer_mapper.dart';
import 'stvplayer_numbering.dart';
import 'stvplayer_refs.dart';

/// Resolves the show -> season -> episode structure of STV Player.
///
/// A programme lists its series (`Series 3`, `Episodes 26 - 50`, `USA`); each is a season, and a series' episodes are
/// the ones filtered on `playerSeries.guid`. A programme that lists none (soaps, daily news, one-off films) gets one
/// synthetic season holding every episode, newest first.
class StvPlayerCatalog {
  final StvPlayerApi _api;
  final StvPlayerMapper _mapper;

  StvPlayerCatalog(this._api, this._mapper);

  Future<ReplayTitle?> title(ReplayRef ref) async {
    final target = StvTarget.parse(ref.nativeId);
    return switch (target.kind) {
      StvTargetKind.show => _show(target.programme!),
      StvTargetKind.season => _season(ref, target),
      StvTargetKind.episode => _episode(target.id!),
      StvTargetKind.clip => _clip(target.id!),
    };
  }

  Future<List<ReplayTitle>> children(ReplayRef ref) {
    final target = StvTarget.parse(ref.nativeId);
    return switch (target.kind) {
      StvTargetKind.show => seasons(target.programme!),
      StvTargetKind.season => episodes(target),
      StvTargetKind.episode || StvTargetKind.clip => Future.value(const []),
    };
  }

  Future<List<ReplayTitle>> seasons(String programmeGuid) async {
    final programme = await _api.programme(programmeGuid);
    return programme == null ? const [] : _seasonsOf(programme);
  }

  Future<List<ReplayTitle>> episodes(StvTarget season) async {
    final programme = await _api.programme(season.programme!);
    if (programme == null) return const [];

    final query = {'programme.guid': season.programme!, 'orderBy': 'number'};
    if (season.isAllEpisodes) {
      final raw = await _api.allEpisodes(query);
      return [for (final e in _newestFirst(raw)) _mapper.episode(e, seasonNumber: 1)];
    }
    final raw = await _api.allEpisodes({...query, 'playerSeries.guid': season.series!});
    final number = _seriesNumbers(programme)[season.series];
    return [for (final e in _inSeasonOrder(raw)) _mapper.episode(e, seasonNumber: number)];
  }

  Future<ReplayTitle?> _show(String guid) async {
    final programme = await _api.programme(guid);
    return programme == null ? null : _mapper.show(programme);
  }

  Future<ReplayTitle?> _season(ReplayRef ref, StvTarget target) async {
    final all = await seasons(target.programme!);
    return all.where((s) => s.ref == ref).firstOrNull;
  }

  Future<ReplayTitle?> _episode(String id) async {
    final episode = await _api.episode(id);
    if (episode == null) return null;
    final guid = (episode['programme'] as Map?)?['guid'] as String?;
    final series = (episode['playerSeries'] as Map?)?['guid'] as String?;
    final programme = guid == null || series == null ? null : await _api.programme(guid);
    return _mapper.episode(episode, seasonNumber: programme == null ? null : _seriesNumbers(programme)[series]);
  }

  Future<ReplayTitle?> _clip(String id) async {
    final clip = await _api.clip(id);
    return clip == null ? null : _mapper.clip(clip);
  }

  List<ReplayTitle> _seasonsOf(Map<String, dynamic> programme) {
    final show = _mapper.show(programme);
    final series = _seriesOf(programme);
    if (series.isEmpty) return [_mapper.allEpisodesSeason(show, episodes: programme['availableEpisodes'] as int?)];

    final numbers = stvSeasonNumbers([for (final s in series) s['name'] as String? ?? '']);
    final single = series.length == 1 ? programme['availableEpisodes'] as int? : null;
    return [
      for (var i = 0; i < series.length; i++)
        _mapper.season(
          show,
          seriesGuid: series[i]['guid'] as String,
          name: series[i]['name'] as String? ?? '',
          number: numbers[i],
          episodes: single,
        ),
    ];
  }

  Map<String, int> _seriesNumbers(Map<String, dynamic> programme) {
    final series = _seriesOf(programme);
    final numbers = stvSeasonNumbers([for (final s in series) s['name'] as String? ?? '']);
    return {for (var i = 0; i < series.length; i++) series[i]['guid'] as String: numbers[i]};
  }

  List<Map<String, dynamic>> _seriesOf(Map<String, dynamic> programme) {
    final series = programme['series'];
    return series is List
        ? series.whereType<Map<String, dynamic>>().where((s) => s['guid'] is String).toList()
        : const [];
  }
}

/// Episodes of a season in viewing order: by their number in the series, then by running number.
List<Map<String, dynamic>> _inSeasonOrder(List<Map<String, dynamic>> episodes) {
  int index(Map<String, dynamic> e) => ((e['playerSeries'] as Map?)?['episodeIndex'] as num?)?.toInt() ?? 1 << 30;
  int running(Map<String, dynamic> e) => (e['number'] as num?)?.toInt() ?? 1 << 30;
  return [...episodes]..sort((a, b) {
    final byIndex = index(a).compareTo(index(b));
    return byIndex != 0 ? byIndex : running(a).compareTo(running(b));
  });
}

/// Episodes of a programme without series, latest broadcast first. Their guids carry the date; those without one go last.
List<Map<String, dynamic>> _newestFirst(List<Map<String, dynamic>> episodes) {
  final epoch = DateTime.utc(1970);
  DateTime date(Map<String, dynamic> e) => stvAirDateFromGuid(e['guid'] as String?) ?? epoch;
  int running(Map<String, dynamic> e) => (e['number'] as num?)?.toInt() ?? 0;
  return [...episodes]..sort((a, b) {
    final byDate = date(b).compareTo(date(a));
    return byDate != 0 ? byDate : running(b).compareTo(running(a));
  });
}
