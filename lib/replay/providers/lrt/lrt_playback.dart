import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'lrt_api.dart';
import 'lrt_json.dart';

/// Where the stream lookup points when a recording is licensed for Lithuania only. The answer is still HTTP 200.
const lrtGeoPlaceholderPath = '/static/mp4/tikLT.mp4';

/// What the stream lookup decided: a file to open, or the reason there is none.
typedef LrtStreamTarget = ({Uri? stream, ReplayPlayback? refusal});

/// Reads the stream lookup. A recording the site does not know still gets a generic playlist URL, but no title or
/// address, so that case counts as gone.
LrtStreamTarget parseLrtMediaInfo(Object? body) {
  final json = lrtJsonObject(body);
  if (json == null) return _refuse(ReplayAvailability.unknown);
  final item = json['playlist_item'];
  final file = item is Map<String, dynamic> ? lrtString(item['file']) : null;
  if (lrtString(json['title']) == null && lrtString(json['url']) == null) return _refuse(ReplayAvailability.expired);
  final uri = file == null ? null : Uri.tryParse(file);
  if (uri == null || !uri.hasScheme || !uri.host.contains('.')) return _refuse(ReplayAvailability.unknown);
  if (uri.path.toLowerCase().endsWith(lrtGeoPlaceholderPath.toLowerCase())) {
    return _refuse(ReplayAvailability.geoBlocked, 'This programme is only available in Lithuania.');
  }
  return (stream: uri, refusal: null);
}

bool lrtIsPlaylist(Uri stream) => stream.path.toLowerCase().endsWith('.m3u8');

/// The outcome for [stream] once its playlist was fetched ([probe], null for files that are not playlists). Expired
/// recordings keep their lookup but their files answer 404.
ReplayPlayback lrtPlaybackFromProbe(Uri stream, LrtManifestProbe? probe) {
  if (probe != null) {
    final status = probe.status;
    if (status == 404 || status == 410) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    if (status == 401 || status == 403) return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked);
    if (status >= 400) return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'HTTP $status');
    if (!probe.body.contains('#EXTM3U')) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  }
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: stream, label: 'LT')],
  );
}

LrtStreamTarget _refuse(ReplayAvailability reason, [String? message]) =>
    (stream: null, refusal: ReplayPlayback.unavailable(reason, message: message));
