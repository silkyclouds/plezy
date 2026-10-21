import '../../model/replay_title.dart';
import 'tf1plus_images.dart';
import 'tf1plus_json.dart';
import 'tf1plus_numbering.dart';
import 'tf1plus_playback.dart';
import 'tf1plus_refs.dart';

/// Builds a title for a bare video id from its media info, the only record that can be fetched by id.
///
/// Returns null when TF1+ does not know the video. The answer carries the title and duration even when it
/// refuses playback, and its refusal becomes the title's availability.
ReplayTitle? tf1TitleFromMediaInfo(String videoId, Map<String, dynamic> info) {
  final media = info['media'];
  if (media is! Map<String, dynamic>) return null;
  final fullTitle = tf1Text(media['title']) ?? tf1Text(media['shortTitle']);
  if (fullTitle == null || tf1Text(media['id']) == null) return null;

  final programName = tf1Text(media['programName']);
  final programSlug = tf1Text(media['programSlug']);
  final spelled = tf1NumbersFromLabel(fullTitle);

  return ReplayTitle(
    ref: tf1Ref(videoId),
    kind: ReplayKind.episode,
    title: tf1EpisodeTitle(fullTitle, programName: programName, episode: spelled.episode),
    backdropUrl: _preview(media['preview']),
    durationSeconds: (media['duration'] as num?)?.toInt(),
    availability: tf1AvailabilityOfMediaInfo(info),
    seasonNumber: spelled.season,
    episodeNumber: spelled.episode,
    showRef: programSlug == null ? null : tf1Ref(programSlug),
    showTitle: programName,
  );
}

String? _preview(Object? url) => url is String && isTf1Image(url) ? url : null;
