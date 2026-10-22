import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'orftvthek_api.dart';
import 'orftvthek_json.dart';
import 'orftvthek_mapper.dart';
import 'orftvthek_profiles.dart';
import 'orftvthek_shows.dart';

/// Searches ORF's programmes and chapters, and adds the shows whose name matches.
///
/// ORF's search returns no shows, so those come from the profile index.
class OrfSearch {
  static const _maxShows = 10;
  static const _maxChapters = 10;

  final OrfApi _api;
  final OrfProfileIndex _index;
  final OrfMapper _mapper;

  OrfSearch(this._api, this._index, this._mapper);

  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final (shows, reply) = await (_shows(trimmed), _api.search(trimmed)).wait;
    final results = orfMap(reply['search']) ?? const <String, dynamic>{};

    final seen = <String>{};
    return [
      for (final title in [
        ...shows,
        ..._section(results, 'episodes', null),
        ..._section(results, 'segments', _maxChapters),
        ..._section(results, 'history', _maxChapters),
      ])
        if (seen.add(title.ref.nativeId)) title,
    ];
  }

  Iterable<ReplayTitle> _section(Map<String, dynamic> results, String name, int? limit) sync* {
    final items = orfMaps(orfMap(results[name])?['items']).where((item) => item['is_oegs'] != true);
    for (final item in limit == null ? items : items.take(limit)) {
      final title = _mapper.listed(item);
      if (title != null) yield title;
    }
  }

  Future<List<ReplayTitle>> _shows(String query) async {
    final wanted = orfSeriesKey(query);
    try {
      final groups = await _index.groups();
      final matches = [
        for (final group in groups)
          if (orfSeriesKey(group.title).contains(wanted)) group,
      ];
      final leading = matches.where((g) => orfSeriesKey(g.title).startsWith(wanted));
      final ranked = [...leading, ...matches.where((g) => !orfSeriesKey(g.title).startsWith(wanted))];
      return [for (final group in ranked.take(_maxShows)) _mapper.groupShow(group)];
    } on MediaServerHttpException {
      return const [];
    } on OrfRateLimitedException {
      return const [];
    }
  }
}
