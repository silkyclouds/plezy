import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'france24_models.dart';

/// Format codes from best to worst, with the label shown to the user. `MP4` is the broadcaster's name for
/// its default file, which for most items is the same file as `MP4-FULL-HD`.
const _formats = [('MP4-FULL-HD', '1080p'), ('MP4', 'MP4'), ('MP4-HD', '720p'), ('MP4-SD', '576p')];

/// End dates further away than this are placeholders for "no expiry".
const _openEnded = Duration(days: 365 * 5);

/// Whether a video can be played at [now], from its rights window and the files it lists.
ReplayAvailability france24Availability(France24Video video, DateTime now) {
  final end = video.validUntil;
  if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
  final start = video.validFrom;
  if (start != null && start.isAfter(now)) return ReplayAvailability.upcoming;
  return video.formats.isEmpty ? ReplayAvailability.unknown : ReplayAvailability.playable;
}

/// The date a video stops being available, or null when the end date only means "no expiry".
DateTime? france24AvailableUntil(France24Video video, DateTime now) {
  final end = video.validUntil;
  return end != null && end.difference(now) < _openEnded ? end : null;
}

/// Progressive MP4 files, best first, one stream per distinct file.
ReplayPlayback france24Playback(France24Video? video, DateTime now) {
  if (video == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  final availability = france24Availability(video, now);
  if (availability != ReplayAvailability.playable) {
    return ReplayPlayback.unavailable(
      availability,
      message: availability == ReplayAvailability.unknown ? 'The video lists no file' : null,
    );
  }

  final seen = <String>{};
  final streams = <ReplayStream>[];
  for (final (code, label) in _formats) {
    final url = video.formats[code];
    if (url != null && seen.add(url)) streams.add(ReplayStream(url: Uri.parse(url), label: label));
  }
  if (streams.isEmpty) {
    return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'The video lists no known file');
  }
  return ReplayPlayback(availability: ReplayAvailability.playable, streams: streams);
}
