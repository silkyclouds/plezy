import 'dart:collection';

import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';

/// The only country ORF's `austria` right can be watched from.
const orfHomeCountry = 'AT';

/// Whether each programme seen in a list is limited to Austria.
///
/// ORF puts the rule on every list item (`right`), but the neutral title has no field for it, so it is kept here
/// until the forecast asks.
class OrfGeoMemory {
  static const _capacity = 4000;
  final LinkedHashMap<String, bool> _austriaOnly = LinkedHashMap();

  void remember(ReplayRef ref, {required bool austriaOnly}) {
    _austriaOnly.remove(ref.nativeId);
    _austriaOnly[ref.nativeId] = austriaOnly;
    if (_austriaOnly.length > _capacity) _austriaOnly.remove(_austriaOnly.keys.first);
  }

  bool? austriaOnly(ReplayRef ref) => _austriaOnly[ref.nativeId];
}

/// Tells a viewer outside Austria which programmes of a list ORF keeps to Austria.
///
/// The verdict comes from the list items the provider has already mapped, so it costs no request. Shows, seasons and
/// programmes it has not seen are left out of the answer.
class OrfAvailabilityForecast {
  final OrfGeoMemory _memory;

  const OrfAvailabilityForecast(this._memory);

  Map<ReplayRef, ReplayAvailability> predict(List<ReplayTitle> titles, String country) {
    if (country.toUpperCase() == orfHomeCountry) return const {};
    return {
      for (final title in titles)
        if (title.isPlayable)
          if (_memory.austriaOnly(title.ref) case final blocked?)
            title.ref: blocked ? ReplayAvailability.geoBlocked : ReplayAvailability.playable,
    };
  }
}
