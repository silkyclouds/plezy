import 'dart:collection';

import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_api.dart';
import 'nrktv_ids.dart';

/// Whether each programme seen so far is limited to Norway.
///
/// Only catalogue episodes and programme pages are recorded: their `usageRights.geoBlock` matches the playback
/// manifest. The flags on page rails and in the A-Z index do not, so they are never read.
class NrkGeoMemory {
  static const _capacity = 4000;
  final LinkedHashMap<String, bool> _norwayOnly = LinkedHashMap();

  /// Remembers whether [programId] is restricted to Norway.
  void remember(String programId, {required bool norwayOnly}) {
    _norwayOnly.remove(programId);
    _norwayOnly[programId] = norwayOnly;
    if (_norwayOnly.length > _capacity) _norwayOnly.remove(_norwayOnly.keys.first);
  }

  bool? norwayOnly(String programId) => _norwayOnly[programId];
}

/// The geographic flag of a catalogue episode or programme page, or null when it carries none.
bool? nrkNorwayOnly(Object? usageRights) {
  final block = usageRights is Map ? usageRights['geoBlock'] : null;
  final flag = block is Map ? block['isGeoBlocked'] : null;
  return flag is bool ? flag : null;
}

/// Tells a viewer outside Norway which programmes of a list they cannot watch.
///
/// Programmes met in a catalogue answer from memory. A few others are looked up one by one, which is one small request
/// each, so a list never costs more than [maxLookups]. Series are not judged: no cheap signal exists for them.
class NrkAvailabilityForecast {
  static const maxLookups = 16;

  final NrkApi _api;
  final NrkGeoMemory _memory;

  NrkAvailabilityForecast(this._api, this._memory);

  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    if (country.toUpperCase() == 'NO') return const {};
    final programs = <String, ReplayRef>{};
    for (final title in titles) {
      final target = title.isPlayable ? parseNrkRef(title.ref) : null;
      if (target is NrkProgramTarget) programs[target.programId] = title.ref;
    }
    final unknown = [
      for (final id in programs.keys)
        if (_memory.norwayOnly(id) == null) id,
    ];
    await Future.wait([for (final id in unknown.take(maxLookups)) _lookUp(id)]);

    return {
      for (final entry in programs.entries)
        if (_memory.norwayOnly(entry.key) case final blocked?)
          entry.value: blocked ? ReplayAvailability.geoBlocked : ReplayAvailability.playable,
    };
  }

  Future<void> _lookUp(String programId) async {
    try {
      final page = await _api.program(programId);
      final flag = nrkNorwayOnly((page['moreInformation'] as Map?)?['usageRights']);
      if (flag != null) _memory.remember(programId, norwayOnly: flag);
    } on MediaServerHttpException {
      return; // The title stays unjudged; playback gives the final answer.
    } on NrkRateLimitedException {
      return;
    }
  }
}
