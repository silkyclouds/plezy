import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// Stream types the player can open, best first.
const _streamPreference = ['hls', 'dash', 'mp4'];

/// Turns the stream service's answer into a playback.
///
/// The documented shape is `{video: {streams: [{type, url, drm?}], subtitles: [{language, url}]}}`; a refusal is
/// `{type, code}` with the service's own codes. Only streams without a `drm` entry are offered: a protected
/// stream is reported, never played.
ReplayPlayback rtlPlayPlaybackFromConfig(int status, Object? body) {
  final map = body is Map<String, dynamic> ? body : null;
  final video = map?['video'];
  if (video is Map<String, dynamic>) return _fromVideo(video);
  return _refusal(status, map?['code']);
}

ReplayPlayback _fromVideo(Map<String, dynamic> video) {
  final streams = [
    for (final raw in (video['streams'] as List? ?? const []).whereType<Map<String, dynamic>>())
      ?_Candidate.tryParse(raw),
  ];
  final clear = streams.where((s) => !s.protected).toList()
    ..sort((a, b) => _streamPreference.indexOf(a.type).compareTo(_streamPreference.indexOf(b.type)));
  if (clear.isNotEmpty) {
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [for (final s in clear) ReplayStream(url: s.url, label: s.type.toUpperCase())],
      subtitles: _subtitles(video['subtitles']),
    );
  }
  if (streams.isNotEmpty) {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.drmProtected,
      message: 'RTL Play protects this stream with DRM',
    );
  }
  return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'RTL Play returned no stream');
}

class _Candidate {
  final String type;
  final Uri url;
  final bool protected;

  const _Candidate(this.type, this.url, {required this.protected});

  static _Candidate? tryParse(Map<String, dynamic> raw) {
    final type = (raw['type'] as String?)?.toLowerCase();
    final url = Uri.tryParse(raw['url'] as String? ?? '');
    if (type == null || !_streamPreference.contains(type) || url == null || !url.isAbsolute) return null;
    return _Candidate(type, url, protected: raw['drm'] != null);
  }
}

/// A language ending in `-tt` is the closed-caption track for the hard of hearing.
List<ReplaySubtitle> _subtitles(Object? raw) {
  final subtitles = <ReplaySubtitle>[];
  for (final item in (raw as List? ?? const []).whereType<Map<String, dynamic>>()) {
    final language = item['language'] as String?;
    final url = Uri.tryParse(item['url'] as String? ?? '');
    if (language == null || url == null || !url.isAbsolute) continue;
    final captions = language.toLowerCase().endsWith('-tt');
    final code = captions ? language.substring(0, language.length - 3) : language;
    subtitles.add(
      ReplaySubtitle(
        url: url,
        languageCode: code,
        label: captions ? '${code.toUpperCase()} (SDH)' : code.toUpperCase(),
      ),
    );
  }
  return subtitles;
}

/// What the service's error codes mean for the viewer; the code wins over the HTTP status when present.
ReplayPlayback _refusal(int status, Object? code) {
  return switch (code is int ? code : status) {
    103 || 104 || 404 => const ReplayPlayback.unavailable(
      ReplayAvailability.expired,
      message: 'This programme is no longer available on RTL Play',
    ),
    106 || 401 => const ReplayPlayback.unavailable(
      ReplayAvailability.loginRequired,
      message: 'RTL Play did not accept the account, sign in again',
    ),
    110 => const ReplayPlayback.unavailable(
      ReplayAvailability.geoBlocked,
      message: 'RTL Play streams are only available in Belgium',
    ),
    113 => const ReplayPlayback.unavailable(
      ReplayAvailability.geoBlocked,
      message: 'RTL Play refuses connections through a VPN or proxy',
    ),
    111 || 429 => const ReplayPlayback.unavailable(
      ReplayAvailability.unknown,
      message: 'RTL Play is rate limiting this connection, try again later',
    ),
    _ => ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'RTL Play refused playback (HTTP $status)'),
  };
}
