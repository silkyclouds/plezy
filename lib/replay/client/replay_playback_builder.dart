import '../../media/media_item.dart';
import '../../media/media_part.dart';
import '../../media/media_source_info.dart';
import '../../media/media_version.dart';
import '../../mpv/models.dart';
import '../../services/playback_initialization_types.dart';
import '../model/replay_playback.dart';
import '../model/replay_title.dart';

/// Turns a provider's [ReplayPlayback] into what the player consumes.
class ReplayPlaybackBuilder {
  const ReplayPlaybackBuilder();

  /// Throws [PlaybackException] naming the reason when [playback] has nothing to play.
  PlaybackInitializationResult build(MediaItem item, ReplayPlayback playback, int selectedIndex) {
    if (!playback.isPlayable) throw _unavailable(playback);
    final index = selectedIndex.clamp(0, playback.streams.length - 1);
    final stream = playback.streams[index];
    final url = stream.url.toString();
    return PlaybackInitializationResult(
      availableVersions: [
        for (var i = 0; i < playback.streams.length; i++)
          MediaVersion(
            id: '$i',
            name: playback.streams[i].label,
            container: 'm3u8',
            parts: [MediaPart(id: '$i', streamPath: playback.streams[i].url.toString(), container: 'm3u8')],
          ),
      ],
      videoUrl: url,
      mediaInfo: MediaSourceInfo(
        videoUrl: url,
        audioTracks: const [],
        subtitleTracks: const [],
        chapters: const [],
        mediaSourceId: '$index',
        mediaIndex: index,
        partIndex: 0,
      ),
      subtitleSidecars: [for (final s in playback.subtitles) _sidecar(s)],
      selectedMediaIndex: index,
      selectedMediaSourceId: '$index',
    );
  }

  PlaybackSubtitleSidecar _sidecar(ReplaySubtitle s) => PlaybackSubtitleSidecar(
    sourceStreamId: null,
    track: SubtitleTrack.uri(s.url.toString(), title: s.label, language: s.languageCode, isForced: s.forced),
  );

  PlaybackException _unavailable(ReplayPlayback playback) {
    final reason = switch (playback.availability) {
      ReplayAvailability.loginRequired => PlaybackFailureReason.authenticationRequired,
      ReplayAvailability.geoBlocked ||
      ReplayAvailability.timeSlotRestricted => PlaybackFailureReason.playbackNotAllowed,
      _ => PlaybackFailureReason.noPlayableSource,
    };
    return PlaybackException(playback.message ?? playback.availability.name, reason: reason);
  }
}
