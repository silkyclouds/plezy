import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'stvr_api.dart';

const _streamLabel = 'STVR';
const _geoMessage = 'This programme is licensed for viewers in Slovakia only.';

/// Turns a recording id into a stream, or into the reason there is none.
///
/// A recording that is blocked for the viewer's country still resolves to a normal master playlist. Only its media
/// playlist gives it away: it lists a short slate called `geolock` instead of the programme. So the first media
/// playlist is read before the recording is reported playable.
class StvrPlaybackResolver {
  final StvrApi _api;

  StvrPlaybackResolver(this._api);

  Future<ReplayPlayback> resolve(String programId) async {
    final Map<String, dynamic> stream;
    try {
      stream = await _api.stream(programId);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }

    final master = stvrMasterUrl(stream);
    if (master == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

    final masterPlaylist = await _api.playlist(master);
    final media = stvrFirstMediaUrl(masterPlaylist.body, master);
    // A master that lists no variants is already a media playlist.
    final probe = media == null ? masterPlaylist : await _api.playlist(media);
    if (stvrIsGeolockSlate(probe)) {
      return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage);
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [ReplayStream(url: master, label: _streamLabel)],
    );
  }
}

/// The HLS master address in a stream description, or null when the recording has no source.
Uri? stvrMasterUrl(Map<String, dynamic> stream) {
  final sources = (stream['clip'] as Map?)?['sources'];
  if (sources is! List) return null;
  for (final source in sources.whereType<Map<String, dynamic>>()) {
    final src = source['src'];
    if (src is String && src.isNotEmpty) return Uri.tryParse(src);
  }
  return null;
}

/// The first variant address of a master playlist, resolved against the master's own address.
Uri? stvrFirstMediaUrl(String master, Uri masterUrl) {
  final lines = master.split('\n').map((l) => l.trim()).toList();
  for (var i = 0; i < lines.length - 1; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    final next = lines[i + 1];
    if (next.isNotEmpty && !next.startsWith('#')) return masterUrl.resolve(next);
  }
  return null;
}

/// Whether a media playlist is the placeholder shown instead of a blocked programme, either because the CDN redirected
/// to it or because its segments live under `geolock`.
bool stvrIsGeolockSlate(StvrPlaylist playlist) =>
    playlist.finalUri.path.contains('geolock') ||
    playlist.body.split('\n').any((line) => !line.startsWith('#') && line.contains('geolock'));
