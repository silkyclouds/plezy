import '../../model/replay_ref.dart';

/// Countries each `geoLocation` flag of a ZDF video is cleared for. `none` is worldwide and needs no entry.
const _clearedIn = {
  'dach': {'DE', 'AT', 'CH'},
  'de': {'DE'},
};

/// Whether a video flagged [geo] cannot be watched from [country]. A missing or unknown flag blocks nothing.
bool zdfBlockedIn(String? geo, String country) {
  final cleared = _clearedIn[geo];
  return cleared != null && !cleared.contains(country.toUpperCase());
}

/// Remembers the `geoLocation` flag of the videos the provider has listed, so a list can be checked against the
/// viewer's country without another request per title.
class ZdfGeoLedger {
  static const _capacity = 4000;
  static const _evictCount = 1000;

  final Map<ReplayRef, String> _flags = {};

  void record(ReplayRef ref, Object? geo) {
    if (geo is! String || geo.isEmpty) return;
    if (_flags.length >= _capacity) _flags.keys.take(_evictCount).toList().forEach(_flags.remove);
    _flags[ref] = geo;
  }

  String? flagOf(ReplayRef ref) => _flags[ref];
}
