import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'urplay_api.dart';

/// The refusal UR gives, in the `message` field, for programmes kept to viewers in Sweden.
const urSwedenOnlyMessage = 'restricted_to_sweden_only';

/// What the master playlist announces: whether it is encrypted, and the choices it carries by itself.
class UrMaster {
  final bool encrypted;
  final bool hasVideo;
  final List<String> subtitleNames;

  const UrMaster({required this.encrypted, required this.hasVideo, required this.subtitleNames});

  /// Reads an HLS master. Subtitles and audio renditions stay inside it; the player offers them.
  factory UrMaster.parse(String playlist) {
    var encrypted = false;
    var variants = 0;
    var withPicture = 0;
    final subtitles = <String>[];
    for (final line in playlist.split('\n').map((l) => l.trim())) {
      if (line.startsWith('#EXT-X-KEY') || line.startsWith('#EXT-X-SESSION-KEY')) {
        encrypted = encrypted || _attribute(line, 'METHOD') != 'NONE';
      } else if (line.startsWith('#EXT-X-STREAM-INF')) {
        variants++;
        if (line.contains('RESOLUTION=')) withPicture++;
      } else if (line.startsWith('#EXT-X-MEDIA') && _attribute(line, 'TYPE') == 'SUBTITLES') {
        final name = _attribute(line, 'NAME') ?? _attribute(line, 'LANGUAGE');
        if (name != null && name.isNotEmpty) subtitles.add(name);
      }
    }
    // A master without variants is not understood well enough to call it audio only.
    return UrMaster(encrypted: encrypted, hasVideo: variants == 0 || withPicture > 0, subtitleNames: subtitles);
  }
}

String? _attribute(String line, String name) {
  final match = RegExp('[,:]$name=("([^"]*)"|[^,]*)').firstMatch(line);
  return match == null ? null : (match.group(2) ?? match.group(1));
}

/// Turns the stream endpoint's answer into a playback result.
///
/// [fetchMaster] reads the master playlist of the chosen stream; it is only asked for once a clear stream URL exists,
/// and a null answer (playlist unreachable) leaves the stream as it is.
Future<ReplayPlayback> urParsePlayback(UrSourcesReply reply, Future<String?> Function(Uri master) fetchMaster) async {
  switch (reply.statusCode) {
    case 200:
      break;
    case 403 when reply.message == urSwedenOnlyMessage:
      return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: 'Only available in Sweden');
    case 400 || 404:
      return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    default:
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: reply.message);
  }

  final sources = reply.body['sources'];
  final raw = sources is Map ? (sources['hls'] ?? sources['dash']) : null;
  final url = raw is String ? Uri.tryParse(raw) : null;
  if (url == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

  final text = await fetchMaster(url);
  final master = text == null || !text.startsWith('#EXTM3U') ? null : UrMaster.parse(text);
  if (master != null && master.encrypted) {
    return const ReplayPlayback.unavailable(ReplayAvailability.drmProtected);
  }
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: url, label: _label(master))],
  );
}

String _label(UrMaster? master) {
  final base = master != null && !master.hasVideo ? 'Ljud' : 'UR Play';
  if (master == null || master.subtitleNames.isEmpty) return base;
  return '$base (undertexter: ${master.subtitleNames.join(', ')})';
}
