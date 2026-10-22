import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_api.dart';
import 'ardmediathek_item.dart';
import 'ardmediathek_playback.dart';
import 'ardmediathek_refs.dart';
import 'ardmediathek_region.dart';

/// Tells, from the video pages, which videos a viewer's country cannot watch.
///
/// Lists carry no rights information, so each card costs one small page request. A video whose region excludes
/// the viewer is then checked once against its CDN, because the region flag is not always right. Answers are
/// remembered, and a lookup that outlives the caller's patience keeps running and fills the memory for the next list.
class ArdMediathekForecast {
  static const _memory = Duration(minutes: 30);
  static const _parallel = 4;
  static const _perCall = 40;
  static const _remembered = 400;

  final ArdMediathekApi _api;
  final DateTime Function() _clock;
  final Map<String, ({DateTime at, Future<ArdItemFacts?> facts})> _pages = {};
  final Map<String, ({DateTime at, Future<bool?> refused})> _cdn = {};

  ArdMediathekForecast(this._api, this._clock);

  /// Verdicts for the videos among [titles]. Shows and seasons are not judged, and neither is a video whose page
  /// could not be read.
  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    final asked = <String, ReplayRef>{};
    for (final title in titles) {
      final target = ardTarget(title.ref);
      if (target is ArdItemTarget && title.availability == ReplayAvailability.playable && asked.length < _perCall) {
        asked[target.id] = title.ref;
      }
    }
    final verdicts = <ReplayRef, ReplayAvailability>{};
    final ids = asked.keys.toList();
    for (var start = 0; start < ids.length; start += _parallel) {
      final batch = ids.skip(start).take(_parallel).toList();
      final judged = await Future.wait([for (final id in batch) _judge(id, country)]);
      for (final (index, id) in batch.indexed) {
        final verdict = judged[index];
        if (verdict != null) verdicts[asked[id]!] = verdict;
      }
    }
    return verdicts;
  }

  Future<ReplayAvailability?> _judge(String id, String country) async {
    final facts = await _factsOf(id);
    if (facts == null) return null;
    if (!facts.isPlayable) {
      return facts.availability == ReplayAvailability.unknown ? ReplayAvailability.playable : facts.availability;
    }
    if (ardRegionAllows(facts.region, country)) return ReplayAvailability.playable;
    final refused = await _refusedByCdn(id, facts);
    return refused == false ? ReplayAvailability.playable : ReplayAvailability.geoBlocked;
  }

  Future<ArdItemFacts?> _factsOf(String id) {
    final hit = _pages[id];
    if (hit != null && _clock().difference(hit.at) < _memory) return hit.facts;
    final lookup = _readPage(id);
    if (_pages.length >= _remembered) _pages.remove(_pages.keys.first);
    _pages[id] = (at: _clock(), facts: lookup);
    return lookup;
  }

  Future<bool?> _refusedByCdn(String id, ArdItemFacts facts) {
    final hit = _cdn[id];
    if (hit != null && _clock().difference(hit.at) < _memory) return hit.refused;
    final probe = _probe(facts);
    if (_cdn.length >= _remembered) _cdn.remove(_cdn.keys.first);
    _cdn[id] = (at: _clock(), refused: probe);
    return probe;
  }

  Future<ArdItemFacts?> _readPage(String id) async {
    try {
      return ardReadItem(await _api.item(id), now: _clock());
    } on MediaServerHttpException {
      _pages.remove(id);
      return null;
    } on ArdMediathekRateLimitedException {
      _pages.remove(id);
      return null;
    }
  }

  // Null when the CDN could not be reached: the region rule then stands.
  Future<bool?> _probe(ArdItemFacts facts) async {
    final status = await _api.streamStatus(facts.main!);
    return status == null ? null : ardStatusRefusesCountry(status);
  }
}
