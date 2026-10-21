import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// Reads a player configuration. ARTE answers 200 for geoblocked, expired and
/// time-restricted programs, so the `error` object and the stream list decide.
ReplayPlayback arteParsePlayback(Map<String, dynamic> config) {
  final attributes = (config['data'] as Map?)?['attributes'] as Map<String, dynamic>?;
  if (attributes == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

  final error = attributes['error'];
  if (error is Map<String, dynamic>) return _fromError(error);

  final streams = [
    for (final raw in (attributes['streams'] as List? ?? const []))
      if (raw is Map<String, dynamic> && raw['url'] is String)
        ReplayStream(url: Uri.parse(raw['url'] as String), label: _label(raw)),
  ];
  if (streams.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: streams,
    credits: _credits((attributes['streams'] as List).first as Map<String, dynamic>),
  );
}

ReplayPlayback _fromError(Map<String, dynamic> error) {
  final code = error['code'] as String? ?? '';
  final message = error['title'] as String?;
  final reason = switch (code) {
    'ERROR_GEOLOCATION' => ReplayAvailability.geoBlocked,
    'ERROR_NO_RIGHTS' => ReplayAvailability.expired,
    _ when code.startsWith('ERROR_AGE_RESTRICTION') => ReplayAvailability.timeSlotRestricted,
    _ => ReplayAvailability.unknown,
  };
  return ReplayPlayback.unavailable(reason, message: message);
}

String _label(Map<String, dynamic> stream) {
  final versions = stream['versions'];
  if (versions is! List || versions.isEmpty) return 'ARTE';
  final names = [
    for (final v in versions.whereType<Map<String, dynamic>>())
      if (v['shortLabel'] is String) v['shortLabel'] as String,
  ];
  return names.isEmpty ? 'ARTE' : names.join(', ');
}

ReplayCredits? _credits(Map<String, dynamic> stream) {
  final segments = stream['segments'];
  if (segments is! List) return null;
  for (final segment in segments.whereType<Map<String, dynamic>>()) {
    if (segment['type'] == 'END_CREDITS' || segment['code'] == 'END_CREDITS') {
      final begin = (segment['begin'] as num?)?.toInt();
      final end = (segment['end'] as num?)?.toInt();
      if (begin != null && end != null) {
        return ReplayCredits(
          start: Duration(seconds: begin),
          end: Duration(seconds: end),
        );
      }
    }
  }
  return null;
}
