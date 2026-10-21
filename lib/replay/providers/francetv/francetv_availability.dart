import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'francetv_api.dart';
import 'francetv_playback.dart';

/// Rights verdicts per video, learned from the broadcaster's own stream-info endpoint.
///
/// Lists carry no rights field, and about nine replays in ten are refused outside France, so a short
/// sample of a season is checked and every playback attempt records its outcome. A verdict is kept for
/// the session: rights change over days, not minutes.
class FranceTvAvailability {
  static const _lifetime = Duration(hours: 6);
  static const _batch = 3;

  final FranceTvApi _api;
  final Duration _batchDelay;
  final Map<String, ({DateTime at, ReplayAvailability verdict})> _verdicts = {};

  FranceTvAvailability(this._api, {this._batchDelay = const Duration(milliseconds: 250)});

  /// The remembered verdict for a video, or null when it is unknown or stale.
  ReplayAvailability? known(String streamId) {
    final entry = _verdicts[streamId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _lifetime) {
      _verdicts.remove(streamId);
      return null;
    }
    return entry.verdict;
  }

  void record(String streamId, ReplayAvailability verdict) {
    _verdicts[streamId] = (at: DateTime.now(), verdict: verdict);
  }

  /// Checks up to [limit] videos whose verdict is unknown, a few at a time, and returns the verdicts
  /// of those the broadcaster answered for. Network failures leave a video unknown.
  Future<Map<String, ReplayAvailability>> probe(Iterable<String> streamIds, {int limit = _batch}) async {
    final pending = [
      for (final id in streamIds)
        if (known(id) == null) id,
    ].take(limit).toList();
    final results = <String, ReplayAvailability>{};
    for (var start = 0; start < pending.length; start += _batch) {
      if (start > 0) await Future<void>.delayed(_batchDelay);
      final batch = pending.skip(start).take(_batch);
      await Future.wait([for (final id in batch) _check(id, results)]);
    }
    return results;
  }

  Future<void> _check(String streamId, Map<String, ReplayAvailability> results) async {
    try {
      final response = await _api.stream(streamId);
      final verdict = franceTvParseStream(response.statusCode, response.body).availability;
      if (verdict != ReplayAvailability.unknown) {
        record(streamId, verdict);
        results[streamId] = verdict;
      }
    } on FranceTvRateLimitedException {
      return;
    } on MediaServerHttpException {
      return;
    }
  }
}
