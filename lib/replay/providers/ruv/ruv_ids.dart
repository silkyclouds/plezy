import '../../model/replay_ref.dart';

const ruvSourceId = 'ruv';

/// Native id suffix of the season that holds every episode of a programme. RÚV has no seasons: a programme is
/// one season, and a sequel is another programme.
const ruvOnlySeason = '_all';

/// `ruv:<programID>` is a programme (a show, or a film).
ReplayRef ruvShowRef(int programId) => ReplayRef(ruvSourceId, '$programId');

/// `ruv:<programID>/_all` is the single season of a programme.
ReplayRef ruvSeasonRef(int programId) => ReplayRef(ruvSourceId, '$programId/$ruvOnlySeason');

/// `ruv:<programID>/<episodeId>` is one episode. The programme is part of the id because RÚV resolves episodes
/// through their programme only.
ReplayRef ruvEpisodeRef(int programId, String episodeId) => ReplayRef(ruvSourceId, '$programId/$episodeId');

/// A parsed native id: the programme, and what follows the slash when there is one.
typedef RuvTarget = ({int programId, String? part});

/// Splits a ref into its programme and part, or null when it is not one of ours.
RuvTarget? ruvTarget(ReplayRef ref) {
  if (ref.source != ruvSourceId) return null;
  final cut = ref.nativeId.indexOf('/');
  final head = cut < 0 ? ref.nativeId : ref.nativeId.substring(0, cut);
  final programId = int.tryParse(head);
  if (programId == null) return null;
  final part = cut < 0 ? null : ref.nativeId.substring(cut + 1);
  return (programId: programId, part: part == null || part.isEmpty ? null : part);
}
