import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';

/// What the catalogue says about playing a title outside Switzerland, remembered per title.
///
/// Every media object carries `playableAbroad`, so the mapper notes it as titles go by and a later forecast for
/// a viewer's country is a lookup, not a request.
class SrgGeoMemory {
  static const _maxEntries = 30000;
  static const _homeCountry = 'CH';

  final Map<ReplayRef, bool> _playableAbroad = {};

  void note(ReplayRef ref, {required bool playableAbroad}) {
    _playableAbroad.remove(ref);
    _playableAbroad[ref] = playableAbroad;
    if (_playableAbroad.length > _maxEntries) _playableAbroad.remove(_playableAbroad.keys.first);
  }

  /// A reason the viewer in [country] cannot play [ref], or null when nothing is known against it.
  ReplayAvailability? verdict(ReplayRef ref, String country) {
    if (country.toUpperCase() == _homeCountry) return null;
    return _playableAbroad[ref] == false ? ReplayAvailability.geoBlocked : null;
  }
}
