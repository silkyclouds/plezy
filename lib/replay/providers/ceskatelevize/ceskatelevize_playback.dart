import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'ceskatelevize_api.dart';
import 'ceskatelevize_text.dart';

const _languages = {
  'cze': 'Czech',
  'ces': 'Czech',
  'eng': 'English',
  'slo': 'Slovak',
  'slk': 'Slovak',
  'ger': 'German',
};
const _isoCodes = {'cze': 'cs', 'ces': 'cs', 'eng': 'en', 'slo': 'sk', 'slk': 'sk', 'ger': 'de', 'deu': 'de'};

/// Reads the playlist answer. Refusals arrive as 403 or 404 with a JSON reason; a 200 carries the stream.
ReplayPlayback ceskatelevizeParsePlayback(CeskaTelevizePlaylistReply reply) {
  final body = reply.body is Map<String, dynamic> ? reply.body as Map<String, dynamic> : const <String, dynamic>{};
  if (reply.status == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  if (reply.status == 403) return _unavailable(body['message']);

  final streams = body['streams'];
  final first = streams is List ? streams.whereType<Map<String, dynamic>>().firstOrNull : null;
  final url = first?['url'];
  if (first == null || url is! String) return _unavailable({'status': (body['playability'] as Map?)?['status']});

  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [
      ReplayStream(url: Uri.parse(url), label: _audioLabel(first)),
      if (first['audioDescriptionUrl'] case final String ad when ad.isNotEmpty)
        ReplayStream(url: Uri.parse(ad), label: 'Czech (audio description)'),
    ],
    subtitles: _subtitles(first),
  );
}

/// Maps the status name of a refusal. The Czech short text is kept as the message because it says it best.
ReplayPlayback _unavailable(Object? message) {
  final fields = message is Map ? message : const {};
  final status = fields['status'];
  final name = status is Map ? status['name'] : null;
  final labels = fields['labels'];
  final text = labels is Map ? ceskatelevizeLabel(labels['textShort']) : null;
  final reason = switch (name) {
    'UNSUPPORTED_GEOLOCATION' => ReplayAvailability.geoBlocked,
    'UNSUPPORTED_DRM' => ReplayAvailability.drmProtected,
    'MISSING_LICENCE_NOW' || 'OTHER' => ReplayAvailability.expired,
    'EMBARGO' => ReplayAvailability.upcoming,
    _ => ReplayAvailability.unknown,
  };
  return ReplayPlayback.unavailable(reason, message: text);
}

String _audioLabel(Map<String, dynamic> stream) {
  final tracks = stream['audioTracks'];
  final names = <String>{
    if (tracks is List)
      for (final t in tracks.whereType<Map<String, dynamic>>())
        if (t['ad'] != true) _languages[t['language']] ?? '${t['language']}',
  };
  return names.isEmpty ? 'Czech' : names.join(', ');
}

List<ReplaySubtitle> _subtitles(Map<String, dynamic> stream) {
  final entries = stream['subtitles'];
  if (entries is! List) return const [];
  final result = <ReplaySubtitle>[];
  for (final entry in entries.whereType<Map<String, dynamic>>()) {
    final files = entry['files'];
    final vtt = files is List
        ? files.whereType<Map<String, dynamic>>().where((f) => f['format'] == 'vtt' && f['url'] is String).firstOrNull
        : null;
    if (vtt == null) continue;
    final language = '${entry['language']}';
    final name = _languages[language] ?? language;
    result.add(
      ReplaySubtitle(
        url: Uri.parse(vtt['url'] as String),
        languageCode: _isoCodes[language] ?? language,
        label: entry['kind'] == 'captions' ? '$name (captions)' : name,
      ),
    );
  }
  return result;
}
