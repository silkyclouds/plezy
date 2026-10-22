import 'dart:async';

import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'lrt_api.dart';
import 'lrt_playback.dart';
import 'lrt_refs.dart';

/// Tells which recordings of a list are licensed for Lithuania only.
///
/// The site flags nothing in its lists, so each recording costs one stream lookup. Verdicts are kept for a while and at
/// most [maxLookups] new ones are made per call, so the rest of a long list is answered by the next call.
class LrtForecast {
  static const maxLookups = 18;
  static const _parallel = 6;
  static const _ttl = Duration(minutes: 30);
  static const _home = 'LT';

  final LrtApi _api;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, ReplayAvailability verdict})> _known = {};

  LrtForecast(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    if (country.toUpperCase() == _home) return const {};
    final recordings = {
      for (final t in titles)
        if (t.isPlayable && lrtPostIdOfNative(t.ref.nativeId) != null) t.ref: lrtPostIdOfNative(t.ref.nativeId)!,
    };
    final unknown = [
      for (final id in recordings.values)
        if (_verdict(id) == null) id,
    ].take(maxLookups).toList();
    for (var i = 0; i < unknown.length; i += _parallel) {
      await Future.wait([for (final id in unknown.skip(i).take(_parallel)) _lookup(id)]);
    }
    return {for (final MapEntry(:key, :value) in recordings.entries) key: ?_verdict(value)};
  }

  ReplayAvailability? _verdict(String postId) {
    final hit = _known[postId];
    return hit == null || _now().difference(hit.at) >= _ttl ? null : hit.verdict;
  }

  Future<void> _lookup(String postId) async {
    try {
      final target = parseLrtMediaInfo(await _api.mediaInfo(postId));
      final refusal = target.refusal;
      if (refusal != null && refusal.availability != ReplayAvailability.geoBlocked) return;
      _known[postId] = (at: _now(), verdict: refusal?.availability ?? ReplayAvailability.playable);
    } on MediaServerHttpException {
      return;
    } on LrtRateLimitedException {
      return;
    }
  }
}
