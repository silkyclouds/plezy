import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'err_api.dart';
import 'err_mapper.dart';
import 'err_refs.dart';

/// Tells which titles of a list a viewer cannot play, from the rights flags on each content page.
///
/// Lists carry no flags, so each title costs one page request. Verdicts are kept for a while, and only some new
/// lookups are made per call, within a time budget, so the rest of a long list is answered by the next call.
class ErrAvailability {
  static const maxLookups = 24;
  static const _parallel = 6;
  static const _budget = Duration(seconds: 4);
  static const _lookupTimeout = Duration(seconds: 4);
  static const _ttl = Duration(minutes: 30);
  static const _home = 'EE';
  static const _maxKnown = 1000;

  final ErrApi _api;
  final DateTime Function() _now;
  final Map<int, ({DateTime at, bool drm, bool estoniaOnly})> _known = {};

  ErrAvailability(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Estonia-only titles are blocked outside Estonia; copy-protected titles are blocked everywhere. A title with no
  /// verdict yet, or none of these, is left out.
  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    final ids = {
      for (final t in titles)
        if (_isAsked(t)) t.ref: errContentId(t.ref)!,
    };
    final unknown = [
      for (final id in ids.values.toSet())
        if (_flags(id) == null) id,
    ].take(maxLookups).toList();
    final clock = Stopwatch()..start();
    for (var i = 0; i < unknown.length && clock.elapsed < _budget; i += _parallel) {
      await Future.wait([for (final id in unknown.skip(i).take(_parallel)) _lookup(id)]);
    }

    final outside = country.toUpperCase() != _home;
    final verdicts = <ReplayRef, ReplayAvailability>{};
    for (final MapEntry(:key, :value) in ids.entries) {
      final flags = _flags(value);
      if (flags == null) continue;
      if (flags.drm) {
        verdicts[key] = ReplayAvailability.drmProtected;
      } else if (flags.estoniaOnly && outside) {
        verdicts[key] = ReplayAvailability.geoBlocked;
      }
    }
    return verdicts;
  }

  bool _isAsked(ReplayTitle title) => title.kind != ReplayKind.season && errContentId(title.ref) != null;

  ({bool drm, bool estoniaOnly})? _flags(int id) {
    final hit = _known[id];
    return hit == null || _now().difference(hit.at) >= _ttl ? null : (drm: hit.drm, estoniaOnly: hit.estoniaOnly);
  }

  Future<void> _lookup(int id) async {
    try {
      final page = await _api.freshContentPage(id, timeout: _lookupTimeout);
      final main = page?['mainContent'];
      final media = main is Map<String, dynamic> ? errFirstMedia(main) : null;
      if (media == null) return;
      final restrictions = media['restrictions'];
      if (_known.length >= _maxKnown) _known.remove(_known.keys.first);
      _known[id] = (
        at: _now(),
        drm: restrictions is Map && restrictions['drm'] == true,
        estoniaOnly: restrictions is Map && restrictions['geoBlock'] == true,
      );
    } on MediaServerHttpException {
      return;
    } on ErrRateLimitedException {
      return;
    }
  }
}
