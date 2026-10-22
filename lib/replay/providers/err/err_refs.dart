import '../../model/replay_ref.dart';

const errSourceId = 'err';

ReplayRef errRef(Object nativeId) => ReplayRef(errSourceId, '$nativeId');

/// The content id of a show, film, episode or clip ref. Null for a season ref.
int? errContentId(ReplayRef ref) => int.tryParse(ref.nativeId);

/// A season ref is `showId/key`, where the key is the season number (or the year, for shows ERR files by month).
ReplayRef errSeasonRef(int showId, int key) => errRef('$showId/$key');

({int showId, int key})? errSeasonParts(ReplayRef ref) {
  final parts = ref.nativeId.split('/');
  if (parts.length != 2) return null;
  final showId = int.tryParse(parts[0]);
  final key = int.tryParse(parts[1]);
  return showId == null || key == null ? null : (showId: showId, key: key);
}
