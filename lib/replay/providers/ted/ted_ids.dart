import '../../model/replay_ref.dart';

const tedSourceId = 'ted';

/// Native id of the season that holds every talk of a playlist.
const tedAllTalksSeason = '_all';

enum TedRefKind { talk, playlist, season }

/// What a ref points at. Native ids are `talk/<slug>`, `playlist/<slug>` and `playlist/<slug>/_all`.
typedef TedTarget = ({TedRefKind kind, String slug});

ReplayRef tedTalkRef(String slug) => ReplayRef(tedSourceId, 'talk/$slug');

ReplayRef tedPlaylistRef(String slug) => ReplayRef(tedSourceId, 'playlist/$slug');

ReplayRef tedSeasonRef(String slug) => ReplayRef(tedSourceId, 'playlist/$slug/$tedAllTalksSeason');

TedTarget? tedTarget(ReplayRef ref) {
  if (ref.source != tedSourceId) return null;
  final parts = ref.nativeId.split('/');
  if (parts.length == 2 && parts[1].isNotEmpty) {
    if (parts[0] == 'talk') return (kind: TedRefKind.talk, slug: parts[1]);
    if (parts[0] == 'playlist') return (kind: TedRefKind.playlist, slug: parts[1]);
  }
  if (parts.length == 3 && parts[0] == 'playlist' && parts[1].isNotEmpty && parts[2] == tedAllTalksSeason) {
    return (kind: TedRefKind.season, slug: parts[1]);
  }
  return null;
}
