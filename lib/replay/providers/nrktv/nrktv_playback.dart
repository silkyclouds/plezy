import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'nrktv_dates.dart';
import 'nrktv_json.dart';

/// Reads a playback manifest. NRK answers 200 for every programme, so `playability` and `nonPlayable` decide.
ReplayPlayback nrkParsePlayback(Map<String, dynamic> manifest, DateTime now) {
  final playable = manifest['playable'];
  if (manifest['playability'] == 'playable' && playable is Map<String, dynamic>) {
    return _fromPlayable(playable);
  }
  final blocked = manifest['nonPlayable'];
  final message = blocked is Map ? _message(blocked) : null;
  return ReplayPlayback.unavailable(_reason(manifest, blocked, now), message: message);
}

ReplayPlayback _fromPlayable(Map<String, dynamic> playable) {
  final assets = (playable['assets'] as List? ?? const []).whereType<Map>();
  final asset = assets.where((a) => a['url'] is String).firstOrNull;
  if (asset == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  final encrypted = asset['encrypted'] == true || (asset['encryptionScheme'] ?? 'none') != 'none';
  if (encrypted) return const ReplayPlayback.unavailable(ReplayAvailability.drmProtected);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: nrkStreamUrl(asset['url'] as String), label: 'NRK')],
    subtitles: _subtitles(playable['subtitles']),
    credits: _credits(playable),
  );
}

/// The master playlist without its query. With `adap=small` it lists three renditions up to 720p; without, it lists
/// them all, up to 1080p.
Uri nrkStreamUrl(String url) {
  final uri = Uri.parse(url);
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: uri.path);
}

List<ReplaySubtitle> _subtitles(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final entry in raw.whereType<Map>())
      if (entry['webVtt'] is String)
        ReplaySubtitle(
          url: Uri.parse(entry['webVtt'] as String),
          languageCode: entry['language'] as String? ?? 'nb',
          label: entry['label'] as String? ?? 'Norsk',
        ),
  ];
}

/// `endSequenceStartTime` is when the credits begin; they run to the end of the programme.
ReplayCredits? _credits(Map<String, dynamic> playable) {
  final start = nrkParseDuration(playable['endSequenceStartTime']);
  final end = nrkParseDuration(playable['duration']);
  if (start == null || end == null || end <= start) return null;
  return ReplayCredits(start: start, end: end);
}

String? _message(Map blocked) {
  final text = blocked['endUserMessage'];
  return text is String && text.trim().isNotEmpty ? text.trim() : null;
}

ReplayAvailability _reason(Map<String, dynamic> manifest, Object? blocked, DateTime now) {
  final availability = manifest['availability'];
  if (availability is Map && availability['isGeoBlocked'] == true) return ReplayAvailability.geoBlocked;
  final messageType = nrkField(blocked, 'messageType');
  final type = messageType is String ? messageType.toLowerCase() : '';
  if (type.contains('geoblock')) return ReplayAvailability.geoBlocked;
  if (type.contains('notstarted')) return ReplayAvailability.upcoming;
  if (type.contains('expired') || type.contains('rightsended')) return ReplayAvailability.expired;
  if (type.contains('login') || type.contains('signin')) return ReplayAvailability.loginRequired;
  if (type.contains('agerestrict') || type.contains('timeslot')) return ReplayAvailability.timeSlotRestricted;
  return _byWindow(availability, now);
}

/// With no message type to go by, the on-demand window says whether the programme is early or late.
ReplayAvailability _byWindow(Object? availability, DateTime now) {
  final window = availability is Map ? availability['onDemand'] : null;
  final from = nrkParseDate(window is Map ? window['from'] : null);
  final to = nrkParseDate(window is Map ? window['to'] : null);
  if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
  if (to != null && !to.isAfter(now)) return ReplayAvailability.expired;
  return ReplayAvailability.unknown;
}
