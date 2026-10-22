import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';

/// What the catalogue says about where a title may be played, remembered per title.
///
/// Lists carry `onlyAvailableInSweden` and `drmCopyProtection` on every item, so the mapper notes them as titles
/// go by and a later forecast for the viewer's country is a lookup, not a request.
class SvtPlayRestrictions {
  static const _maxEntries = 30000;
  static const _home = 'SE';

  final Map<ReplayRef, ({bool swedenOnly, bool drm})> _seen = {};

  void note(ReplayRef ref, {required bool swedenOnly, required bool drm}) {
    if (_seen.length >= _maxEntries) _seen.remove(_seen.keys.first);
    _seen[ref] = (swedenOnly: swedenOnly, drm: drm);
  }

  /// Gives [child] (a season) the flags already noted for [parent] (its show).
  void inherit(ReplayRef child, ReplayRef parent) {
    final seen = _seen[parent];
    if (seen != null) note(child, swedenOnly: seen.swedenOnly, drm: seen.drm);
  }

  /// A reason the viewer in [country] cannot play [ref], or null when nothing is known against it.
  ReplayAvailability? verdict(ReplayRef ref, String country) {
    final seen = _seen[ref];
    if (seen == null) return null;
    if (seen.drm) return ReplayAvailability.drmProtected;
    if (seen.swedenOnly && country.toUpperCase() != _home) return ReplayAvailability.geoBlocked;
    return null;
  }
}
