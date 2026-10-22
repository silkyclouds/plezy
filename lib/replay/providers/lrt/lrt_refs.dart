import '../../model/replay_ref.dart';

const lrtSourceId = 'lrt';
const lrtOrigin = 'https://www.lrt.lt';

/// Season id of a programme that publishes no seasons: every recording of the programme.
const lrtAllVideosSeason = '_all';

const _recordingPrefix = 'rec:';
final _recordingId = RegExp(r'^rec:(\d+)$');

/// What a native id names. LRT has no series ids, so the id itself carries the level.
enum LrtRefKind { show, season, recording }

ReplayRef lrtShowRef(String slug) => ReplayRef(lrtSourceId, slug);

ReplayRef lrtSeasonRef(String showSlug, String seasonSlug) => ReplayRef(lrtSourceId, '$showSlug/$seasonSlug');

/// A recording's id is its post id behind a prefix, since post ids run from 5 to 10 digits and a programme slug can be
/// all digits too.
ReplayRef lrtRecordingRef(String postId) => ReplayRef(lrtSourceId, '$_recordingPrefix$postId');

/// The post id inside a recording's native id, or null when [nativeId] is not one.
String? lrtPostIdOfNative(String nativeId) => _recordingId.firstMatch(nativeId)?.group(1);

/// A recording is `rec:` and its post id, a season is `showSlug/seasonSlug`, a show is its slug.
LrtRefKind lrtRefKind(String nativeId) {
  if (lrtPostIdOfNative(nativeId) != null) return LrtRefKind.recording;
  return nativeId.contains('/') ? LrtRefKind.season : LrtRefKind.show;
}

/// The two halves of a season id, or null when [nativeId] is not one.
({String show, String season})? lrtSplitSeasonId(String nativeId) {
  final cut = nativeId.indexOf('/');
  if (cut <= 0 || cut == nativeId.length - 1) return null;
  return (show: nativeId.substring(0, cut), season: nativeId.substring(cut + 1));
}

final _recordingPath = RegExp(r'/mediateka/irasas/(\d+)');
final _showPath = RegExp(r'/mediateka/video/([^/?#\s]+)');
final _seasonPath = RegExp(r'/mediateka/video/[^/?#\s]+/([^/?#\s]+)');

/// The post id in `/mediateka/irasas/{postId}/{slug}`, relative or absolute.
String? lrtPostIdOf(String? url) => url == null ? null : _recordingPath.firstMatch(url)?.group(1);

/// The programme slug in `/mediateka/video/{slug}[/{season}]`.
String? lrtShowSlugOf(String? url) => url == null ? null : _showPath.firstMatch(url)?.group(1);

/// The season slug in `/mediateka/video/{slug}/{season}`.
String? lrtSeasonSlugOf(String? url) => url == null ? null : _seasonPath.firstMatch(url)?.group(1);
