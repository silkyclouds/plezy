import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'nhkworld_availability.dart';

/// Reads one episode or clip of the catalogue into a playback answer.
///
/// The `video.url` is an HLS master that already carries the audio and the WebVTT subtitle renditions, so it is
/// returned as the only stream. Playlists are not encrypted with DRM: clips use plain AES-128 with an open key.
ReplayPlayback nhkParsePlayback(Map<String, dynamic>? item, DateTime now) {
  if (item == null) return _gone();
  final video = item['video'];
  switch (nhkAvailability(video, now)) {
    case ReplayAvailability.upcoming:
      return const ReplayPlayback.unavailable(
        ReplayAvailability.upcoming,
        message: 'This programme is not online yet.',
      );
    case ReplayAvailability.playable:
      break;
    default:
      return _gone();
  }
  final url = Uri.tryParse((video as Map)['url'] as String);
  if (url == null || !url.hasScheme) {
    return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  }
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: url, label: 'English')],
  );
}

ReplayPlayback _gone() =>
    const ReplayPlayback.unavailable(ReplayAvailability.expired, message: 'This programme is no longer available.');
