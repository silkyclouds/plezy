import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'tvpvod_api.dart';

/// Reads a playlist answer. Streams are clear HLS (or DASH when no HLS is offered); refusals come as a 4xx whose
/// JSON body holds a code and no readable text.
ReplayPlayback tvpParsePlayback(TvpPlaylistReply reply, {ReplayCredits? credits}) {
  final body = reply.body;
  if (reply.statusCode >= 400) return _refusal(reply.statusCode, body);
  if (body is! Map<String, dynamic>) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

  final streams = _streams(body['sources']);
  if (streams.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: streams,
    subtitles: _subtitles(body['subtitles']),
    credits: credits,
  );
}

List<ReplayStream> _streams(Object? sources) {
  if (sources is! Map) return const [];
  for (final kind in ['HLS', 'DASH']) {
    final list = sources[kind];
    if (list is! List) continue;
    final streams = [
      for (final entry in list.whereType<Map>())
        if (entry['src'] is String && (entry['src'] as String).isNotEmpty)
          ReplayStream(url: Uri.parse(entry['src'] as String), label: 'PL'),
    ];
    if (streams.isNotEmpty) return streams;
  }
  return const [];
}

List<ReplaySubtitle> _subtitles(Object? list) {
  if (list is! List) return const [];
  return [
    for (final entry in list.whereType<Map>())
      if (entry['url'] is String)
        ReplaySubtitle(
          url: Uri.parse(entry['url'] as String),
          languageCode: _language(entry['isoCode'] as String?),
          label: _subtitleLabel(entry['language'] as String?),
        ),
  ];
}

/// The site names languages with ISO 639-2 codes; the player wants the two-letter form.
String _language(String? iso) {
  final code = iso?.toUpperCase() ?? 'POL';
  return switch (code) {
    'POL' => 'pl',
    'ENG' => 'en',
    'UKR' => 'uk',
    'BEL' => 'be',
    _ => code.toLowerCase(),
  };
}

String _subtitleLabel(String? language) {
  if (language != null && language.toUpperCase().contains('NIESLYSZACYCH')) return 'Polski (dla niesłyszących)';
  return 'Polski';
}

ReplayPlayback _refusal(int status, Object? body) {
  final code = body is Map ? body['code'] as String? ?? '' : '';
  final reason = switch (code) {
    'GEOIP_FILTER_FAILED' => ReplayAvailability.geoBlocked,
    'ITEM_NOT_EXISTS' || 'ITEM_NOT_AVAILABLE' => ReplayAvailability.expired,
    _ when _mentions(code, const ['PAY', 'LOGIN', 'AUTH', 'SUBSCRIPTION', 'PURCHASE']) =>
      ReplayAvailability.loginRequired,
    _ when status == 401 || status == 402 => ReplayAvailability.loginRequired,
    _ when status == 404 => ReplayAvailability.expired,
    _ => ReplayAvailability.unknown,
  };
  return ReplayPlayback.unavailable(
    reason,
    message: reason == ReplayAvailability.unknown && code.isNotEmpty ? code : null,
  );
}

bool _mentions(String code, List<String> words) => words.any(code.contains);
