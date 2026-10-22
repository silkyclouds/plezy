import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ruv_api.dart';
import 'ruv_ids.dart';
import 'ruv_mapper.dart';
import 'ruv_queries.dart';
import 'ruv_scope.dart';

/// Resolves the show -> season -> episode structure of RÚV programmes.
///
/// A programme is a show with one season ([ruvOnlySeason]); that season holds the programme's episodes. A film
/// is a movie and has no children.
class RuvCatalog {
  final RuvApi _api;
  final RuvScopes _scopes;
  final DateTime Function() _now;

  RuvCatalog(this._api, this._scopes, this._now);

  Future<ReplayTitle?> title(ReplayRef ref) async {
    final target = ruvTarget(ref);
    if (target == null) return null;
    final program = await _program(target.programId);
    if (program == null) return null;
    final part = target.part;
    if (part == null) return ruvTitleFromProgram(program, now: _now());
    if (part == ruvOnlySeason) return ruvSeasonFromProgram(program);
    return ruvEpisodesFromProgram(program, now: _now()).where((e) => e.ref == ref).firstOrNull;
  }

  /// The season of a show, or the episodes of that season.
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final target = ruvTarget(ref);
    if (target == null) return const [];
    final program = await _program(target.programId);
    if (program == null) return const [];
    if (target.part == ruvOnlySeason) return ruvEpisodesFromProgram(program, now: _now());
    if (target.part != null || ruvIsFilm(program)) return const [];
    final season = ruvSeasonFromProgram(program);
    return season == null ? const [] : [season];
  }

  Future<Map<String, dynamic>?> _program(int programId) async {
    final data = await _api.query(ruvProgramQuery, variables: {'p': programId}, ttl: RuvApi.detailsTtl);
    final program = data['Program'];
    if (program is! Map<String, dynamic>) return null;
    _scopes.noteAll([program]);
    return program;
  }
}
