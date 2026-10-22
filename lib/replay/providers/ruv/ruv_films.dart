import 'ruv_api.dart';
import 'ruv_mapper.dart';
import 'ruv_queries.dart';

/// Tells films from series among programmes that came out of a list.
///
/// Lists carry a programme's latest episode only, and RÚV files some series under films. A programme filed there is
/// asked for by id once, so that its episodes can be counted before it is shown as a movie.
class RuvFilmCheck {
  static const _batchSize = 40;
  static const _maxEntries = 400;

  final RuvApi _api;
  final DateTime Function() _now;
  final Map<int, ({DateTime at, Map<String, dynamic> program})> _checked = {};

  RuvFilmCheck(this._api, this._now);

  /// [programs] with every film candidate replaced by its fuller record. The rest pass through untouched.
  Future<List<Map<String, dynamic>>> settle(List<Map<String, dynamic>> programs) async {
    final wanted = <int>{
      for (final program in programs)
        if (ruvFiledAsFilm(program)) ?ruvProgramId(program),
    };
    final missing = [
      for (final id in wanted)
        if (!_isFresh(id)) id,
    ];
    await Future.wait([
      for (var i = 0; i < missing.length; i += _batchSize)
        _load(missing.sublist(i, i + _batchSize > missing.length ? missing.length : i + _batchSize)),
    ]);
    return [for (final program in programs) _checked[ruvProgramId(program)]?.program ?? program];
  }

  bool _isFresh(int id) {
    final hit = _checked[id];
    return hit != null && _now().difference(hit.at) < RuvApi.listTtl;
  }

  Future<void> _load(List<int> ids) async {
    final data = await _api.query(ruvCardsBatchQuery(ids), ttl: RuvApi.listTtl);
    final results = ruvBatchResults(data, ids.length);
    for (var i = 0; i < ids.length; i++) {
      final program = results[i];
      if (program == null) continue;
      if (_checked.length >= _maxEntries) _checked.remove(_checked.keys.first);
      _checked[ids[i]] = (at: _now(), program: program);
    }
  }
}
