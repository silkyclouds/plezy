import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';

/// Reason an item cannot be played whoever the viewer is, or [ReplayAvailability.playable].
///
/// [item] is a programme, an episode or a clip. Episodes embed a short copy of their programme, which carries the
/// protection flag. Geography is not judged here: it depends on the viewer.
ReplayAvailability stvPlayerAvailability(Map<String, dynamic> item, DateTime now) {
  final programme = item['programme'];
  final parent = programme is Map<String, dynamic> ? programme : const <String, dynamic>{};
  if (item['drmEnabled'] == true || parent['drmEnabled'] == true) return ReplayAvailability.drmProtected;
  if (_needsAccount(item) || _needsAccount(parent)) return ReplayAvailability.loginRequired;

  final window = item['availability'];
  if (window is Map<String, dynamic>) {
    final until = _time(window['until']);
    if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
    final from = _time(window['from']);
    if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
  }
  return ReplayAvailability.playable;
}

DateTime? stvPlayerTime(Object? iso) => _time(iso);

bool _needsAccount(Map<String, dynamic> item) =>
    item['vipExclusive'] == true || item['svodExclusive'] == true || item['premierSportsExclusive'] == true;

DateTime? _time(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

/// Where each episode may be watched, as the catalogue states it, so a list can be greyed out for viewers abroad
/// without a request per episode.
///
/// An episode's allow list names the whole UK (`uk`, `itv`, `utv`) or STV's regions; every token is inside the
/// United Kingdom, so the list either admits Great Britain or says nothing about it.
class StvPlayerRestrictions {
  static const _maxEntries = 30000;
  static const _home = 'GB';

  final Map<ReplayRef, bool> _ukOnly = {};

  /// Remembers an episode's allow list. An absent or empty list means the catalogue states no restriction.
  void note(ReplayRef ref, Object? locations) {
    if (_ukOnly.length >= _maxEntries) _ukOnly.remove(_ukOnly.keys.first);
    _ukOnly[ref] = locations is List && locations.isNotEmpty;
  }

  /// [ReplayAvailability.geoBlocked] when [ref] is limited to the UK and the viewer in [country] is elsewhere, else null.
  ReplayAvailability? verdict(ReplayRef ref, String country) {
    if (_ukOnly[ref] != true) return null;
    final code = country.toUpperCase();
    return code == _home || code == 'UK' ? null : ReplayAvailability.geoBlocked;
  }
}
