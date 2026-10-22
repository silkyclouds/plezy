import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'aljazeera_api.dart';

const _hlsType = 'application/x-mpegURL';

/// Reads Brightcove's answer for a video.
///
/// Brightcove reports a removed video as 404 and a restricted one as 403 with an `error_code`. A source with
/// `key_systems` is encrypted and is never offered. The HLS master carries the English audio and the captions
/// itself, so external captions are added only when the video falls back to a plain MP4.
ReplayPlayback aljazeeraParsePlayback(AljazeeraVideoReply reply) {
  final body = reply.body;
  if (reply.statusCode != 200 || body is! Map<String, dynamic>) return _refusal(reply);

  final sources = [
    for (final raw in (body['sources'] as List? ?? const []))
      if (raw is Map<String, dynamic> && raw['src'] is String && (raw['src'] as String).startsWith('https://')) raw,
  ];
  final clear = [
    for (final source in sources)
      if (!_isProtected(source)) source,
  ];
  final hls = _hls(clear);
  final mp4 = _mp4(clear);
  if (hls == null && mp4 == null) {
    return ReplayPlayback.unavailable(
      sources.isEmpty ? ReplayAvailability.unknown : ReplayAvailability.drmProtected,
      message: sources.isEmpty ? 'No stream is published for this video' : 'This video is encrypted',
    );
  }

  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [
      if (hls != null) ReplayStream(url: Uri.parse(hls['src'] as String), label: 'EN'),
      if (mp4 != null) ReplayStream(url: Uri.parse(mp4['src'] as String), label: 'MP4 ${mp4['height']}p'),
    ],
    subtitles: hls == null ? _captions(body) : const [],
  );
}

ReplayPlayback _refusal(AljazeeraVideoReply reply) {
  final error = _firstError(reply.body);
  final code = error?['error_code'] as String? ?? '';
  final message = error?['message'] as String?;
  final reason = switch (code) {
    'CLIENT_GEO' => ReplayAvailability.geoBlocked,
    'VIDEO_NOT_FOUND' || 'RESOURCE_NOT_FOUND' || 'NOT_FOUND' => ReplayAvailability.expired,
    _ when reply.statusCode == 404 => ReplayAvailability.expired,
    _ => ReplayAvailability.unknown,
  };
  return ReplayPlayback.unavailable(reason, message: message);
}

Map<String, dynamic>? _firstError(Object? body) {
  if (body is! List) return null;
  return body.whereType<Map<String, dynamic>>().firstOrNull;
}

bool _isProtected(Map<String, dynamic> source) {
  final systems = source['key_systems'];
  return systems is Map && systems.isNotEmpty;
}

/// The HLS master of the newest generation, or any HLS master.
Map<String, dynamic>? _hls(List<Map<String, dynamic>> sources) {
  final masters = [
    for (final s in sources)
      if (s['type'] == _hlsType) s,
  ];
  return masters.where((s) => (s['src'] as String).contains('/hls/v4/')).firstOrNull ?? masters.firstOrNull;
}

/// The MP4 file with the highest bitrate.
Map<String, dynamic>? _mp4(List<Map<String, dynamic>> sources) {
  final files = [
    for (final s in sources)
      if (s['container'] == 'MP4' && s['height'] is num) s,
  ]..sort((a, b) => ((b['avg_bitrate'] as num?) ?? 0).compareTo((a['avg_bitrate'] as num?) ?? 0));
  return files.firstOrNull;
}

List<ReplaySubtitle> _captions(Map<String, dynamic> body) {
  final tracks = body['text_tracks'];
  if (tracks is! List) return const [];
  final subtitles = <ReplaySubtitle>[];
  for (final track in tracks.whereType<Map<String, dynamic>>()) {
    final url = track['kind'] == 'captions' ? _trackUrl(track) : null;
    if (url != null) {
      subtitles.add(ReplaySubtitle(url: url, languageCode: _language(track['srclang'] as String?), label: 'English'));
    }
  }
  return subtitles;
}

Uri? _trackUrl(Map<String, dynamic> track) {
  final sources = track['sources'];
  final candidates = [
    if (sources is List)
      for (final s in sources.whereType<Map<String, dynamic>>()) s['src'],
    track['src'],
  ];
  final https = candidates.whereType<String>().where((u) => u.startsWith('https://')).firstOrNull;
  return https == null ? null : Uri.parse(https);
}

String _language(String? tag) => (tag == null || tag.isEmpty) ? 'en' : tag.split('-').first;
