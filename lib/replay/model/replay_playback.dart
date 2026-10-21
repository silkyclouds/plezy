import 'replay_title.dart';

/// One playable rendition of a title. HLS masters carry their own audio and subtitle choices.
class ReplayStream {
  final Uri url;

  /// Short label for the choice, such as "VF", "VOSTF", "AD".
  final String label;
  final Map<String, String> headers;

  const ReplayStream({required this.url, required this.label, this.headers = const {}});
}

/// A subtitle file delivered next to the video rather than inside the playlist.
class ReplaySubtitle {
  final Uri url;
  final String languageCode;
  final String label;
  final bool forced;

  const ReplaySubtitle({required this.url, required this.languageCode, required this.label, this.forced = false});
}

/// Where credits start, so the player can offer to skip them.
class ReplayCredits {
  final Duration start;
  final Duration end;

  const ReplayCredits({required this.start, required this.end});
}

/// Result of asking a broadcaster how to play a title.
///
/// When [availability] is not [ReplayAvailability.playable], [streams] is empty
/// and [message] says why in the broadcaster's own words when it gave any.
class ReplayPlayback {
  final ReplayAvailability availability;
  final List<ReplayStream> streams;
  final List<ReplaySubtitle> subtitles;
  final ReplayCredits? credits;
  final String? message;

  const ReplayPlayback({
    required this.availability,
    this.streams = const [],
    this.subtitles = const [],
    this.credits,
    this.message,
  });

  const ReplayPlayback.unavailable(ReplayAvailability reason, {String? message})
    : this(availability: reason, message: message);

  bool get isPlayable => availability == ReplayAvailability.playable && streams.isNotEmpty;
}
