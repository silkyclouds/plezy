import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ruv_api.dart';
import 'ruv_ids.dart';
import 'ruv_mapper.dart';
import 'ruv_queries.dart';

/// Where RÚV licenses a programme.
enum RuvScope {
  /// The rights allow the whole world.
  global,

  /// Iceland only; the CDN answers 403 elsewhere.
  domestic;

  static RuvScope? parse(Object? value) => switch (value) {
    'Global' => RuvScope.global,
    'Domestic' => RuvScope.domestic,
    _ => null,
  };
}

/// The scope of a programme's first episode, which tells the programme: scope never differs between its episodes.
RuvScope? ruvScopeOf(Map<String, dynamic> program) {
  final episodes = program['episodes'];
  if (episodes is! List || episodes.isEmpty || episodes.first is! Map) return null;
  return RuvScope.parse((episodes.first as Map)['scope']);
}

/// What the catalogue says about where a programme may be watched, remembered per programme.
///
/// Every card carries the scope of its first episode, so lists feed this as they are mapped and a forecast for the
/// viewer's country is mostly a lookup.
class RuvScopes {
  static const _maxEntries = 4000;

  final Map<int, RuvScope> _seen = {};

  RuvScope? of(int programId) => _seen[programId];

  void note(int programId, RuvScope scope) {
    if (_seen.length >= _maxEntries) _seen.remove(_seen.keys.first);
    _seen[programId] = scope;
  }

  /// Remembers the scope of each programme map that states one.
  void noteAll(Iterable<Map<String, dynamic>> programs) {
    for (final program in programs) {
      final id = ruvProgramId(program);
      final scope = ruvScopeOf(program);
      if (id != null && scope != null) note(id, scope);
    }
  }
}

/// Tells before playing which programmes a viewer's country cannot watch.
class RuvAvailability {
  /// Programmes asked about in one request; RÚV answered 40 aliases without complaint.
  static const _batchSize = 40;
  static const _home = 'IS';

  final RuvApi _api;
  final RuvScopes _scopes;

  RuvAvailability(this._api, this._scopes);

  /// Verdicts for the titles whose programme scope is known or can be fetched. Iceland-only programmes are
  /// geo-blocked outside Iceland; worldwide ones are playable everywhere.
  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    final targets = {
      for (final title in titles)
        if (ruvTarget(title.ref) case final target?) title.ref: target.programId,
    };
    await _learn(targets.values.toSet());
    final inIceland = country.toUpperCase() == _home;
    return {
      for (final MapEntry(:key, :value) in targets.entries)
        if (_scopes.of(value) case final scope?)
          key: scope == RuvScope.domestic && !inIceland ? ReplayAvailability.geoBlocked : ReplayAvailability.playable,
    };
  }

  Future<void> _learn(Set<int> programIds) async {
    final unknown = [
      for (final id in programIds)
        if (_scopes.of(id) == null) id,
    ];
    await Future.wait([
      for (var i = 0; i < unknown.length; i += _batchSize)
        _fetch(unknown.sublist(i, i + _batchSize > unknown.length ? unknown.length : i + _batchSize)),
    ]);
  }

  Future<void> _fetch(List<int> ids) async {
    final data = await _api.query(ruvScopeBatchQuery(ids), ttl: RuvApi.detailsTtl);
    final results = ruvBatchResults(data, ids.length);
    for (var i = 0; i < ids.length; i++) {
      final scope = results[i] == null ? null : ruvScopeOf(results[i]!);
      if (scope != null) _scopes.note(ids[i], scope);
    }
  }
}
