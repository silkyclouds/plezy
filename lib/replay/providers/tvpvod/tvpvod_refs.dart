import '../../model/replay_ref.dart';

const tvpvodSourceId = 'tvpvod';

/// A show, film or episode is addressed by its product id.
ReplayRef tvpRef(Object productId) => ReplayRef(tvpvodSourceId, '$productId');

/// A season is `serialId/seasonId`: the seasons endpoint is keyed by both.
ReplayRef tvpSeasonRef(Object serialId, Object seasonId) => ReplayRef(tvpvodSourceId, '$serialId/$seasonId');

/// The two halves of a season ref, or null when [ref] is not one.
({String serialId, String seasonId})? tvpSeasonParts(ReplayRef ref) {
  final parts = ref.nativeId.split('/');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) return null;
  return (serialId: parts[0], seasonId: parts[1]);
}
