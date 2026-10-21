import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// Turns a Dailymotion player-metadata document into a playback result.
///
/// Dailymotion answers 200 for blocked videos and puts an `error` object where `qualities` would be, so
/// that object decides before the stream list does. The master playlist is handed to the player as is:
/// the signed URL carries its own session value, and sending a Referer to the manifest host gets requests
/// refused, so [ReplayStream.headers] stays empty.
ReplayPlayback dailymotionPlaybackFromMetadata(Map<String, dynamic> metadata, {String label = 'VF'}) {
  final error = metadata['error'];
  if (error is Map<String, dynamic>) return _fromError(error);
  if (metadata['protected_delivery'] == true) {
    return const ReplayPlayback.unavailable(ReplayAvailability.drmProtected);
  }

  final master = _masterUrl(metadata);
  if (master == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: master, label: label)],
  );
}

Uri? _masterUrl(Map<String, dynamic> metadata) {
  final auto = (metadata['qualities'] as Map?)?['auto'];
  if (auto is! List) return null;
  for (final entry in auto.whereType<Map<String, dynamic>>()) {
    final url = entry['url'];
    if (url is String && entry['type'] == 'application/x-mpegURL') return Uri.tryParse(url);
  }
  return null;
}

ReplayPlayback _fromError(Map<String, dynamic> error) {
  final message = error['title'] as String?;
  final reason = switch ((error['code'], (error['status_code'] as num?)?.toInt())) {
    ('DM007', _) => ReplayAvailability.geoBlocked,
    (_, 404) => ReplayAvailability.expired,
    (_, 401) => ReplayAvailability.loginRequired,
    _ => ReplayAvailability.unknown,
  };
  return ReplayPlayback.unavailable(reason, message: message);
}
