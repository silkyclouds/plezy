import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'threecat_api.dart';
import 'threecat_ids.dart';

/// Whether an item is limited to Spain, as the broadcaster flags it: `ESPANYA`, or `TOTS` for everywhere.
/// Null when the item carries no flag, which is the case for search results.
bool? threeCatSpainOnly(Object? flags) {
  if (flags is! List) return null;
  final ids = [for (final f in flags.whereType<Map>()) f['id']];
  if (ids.contains('TOTS')) return false;
  return ids.contains('ESPANYA') ? true : null;
}

/// The Spain-only flag of every video met in a list, so lists can be judged without asking again.
class ThreeCatGeoMemory {
  static const _capacity = 4000;
  final LinkedHashMap<String, bool> _spainOnly = LinkedHashMap();

  void remember(String videoId, {required bool spainOnly}) {
    _spainOnly.remove(videoId);
    _spainOnly[videoId] = spainOnly;
    if (_spainOnly.length > _capacity) _spainOnly.remove(_spainOnly.keys.first);
  }

  bool? spainOnly(String videoId) => _spainOnly[videoId];
}

/// Tells a viewer outside Spain which videos of a list are limited to Spain.
///
/// Videos met in a catalogue answer from memory. A few others (search results carry no flag) are looked up one by one,
/// so a list never costs more than [maxLookups] small requests. Only blocked videos are named.
class ThreeCatAvailabilityForecast {
  static const maxLookups = 12;

  final ThreeCatApi _api;
  final ThreeCatGeoMemory _memory;

  ThreeCatAvailabilityForecast(this._api, this._memory);

  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    if (country.toUpperCase() == 'ES') return const {};
    final videos = <String, ReplayRef>{};
    for (final title in titles) {
      final target = title.isPlayable ? parseThreeCatRef(title.ref) : null;
      if (target is ThreeCatVideoTarget) videos[target.videoId] = title.ref;
    }
    final unknown = [
      for (final id in videos.keys)
        if (_memory.spainOnly(id) == null) id,
    ];
    await Future.wait([for (final id in unknown.take(maxLookups)) _lookUp(id)]);

    return {
      for (final entry in videos.entries)
        if (_memory.spainOnly(entry.key) == true) entry.value: ReplayAvailability.geoBlocked,
    };
  }

  Future<void> _lookUp(String videoId) async {
    try {
      final media = await _api.media(videoId);
      final flag = media['media'] is Map ? (media['media'] as Map)['geo'] : null;
      if (flag is String) _memory.remember(videoId, spainOnly: flag == 'ESPANYA');
    } on MediaServerHttpException {
      return;
    } on ThreeCatRateLimitedException {
      return;
    }
  }
}
