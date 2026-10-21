import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'dailymotion_ids.dart';
import 'dailymotion_metadata.dart';

/// Fetches the player-metadata document of one video, or null when Dailymotion no longer has it.
///
/// The transport is supplied by the caller. This package only knows how to read the answer, so it never
/// decides on its own to call an endpoint the caller has not approved.
typedef DailymotionMetadataSource = Future<Map<String, dynamic>?> Function(String videoId);

/// Resolves any public Dailymotion video to a clear HLS stream, for broadcasters that embed Dailymotion.
class DailymotionResolver {
  final DailymotionMetadataSource _source;

  const DailymotionResolver(this._source);

  Future<ReplayPlayback> resolve(String videoId, {String label = 'VF'}) async {
    if (!isDailymotionVideoId(videoId)) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    final metadata = await _source(videoId);
    if (metadata == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    return dailymotionPlaybackFromMetadata(metadata, label: label);
  }
}
