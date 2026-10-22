import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'threecat_api.dart';

/// What the media resolver says about a video.
class ThreeCatMedia {
  final bool active;
  final bool spainOnly;

  /// The broadcaster's notice about where the video may be watched, when it gave one.
  final String? rights;
  final List<ReplayStream> streams;
  final List<ReplaySubtitle> subtitles;

  const ThreeCatMedia({
    required this.active,
    required this.spainOnly,
    required this.rights,
    required this.streams,
    required this.subtitles,
  });
}

ThreeCatMedia threeCatParseMedia(Map<String, dynamic> answer) {
  final media = _field(answer, 'media');
  final rights = _field(_field(answer, 'informacio'), 'drets');
  final text = rights['text'];
  final notice = text is String && text.trim().isNotEmpty ? text.trim() : null;
  return ThreeCatMedia(
    active: _field(_field(answer, 'informacio'), 'estat')['actiu'] != false,
    spainOnly: media['geo'] == 'ESPANYA' || notice != null,
    rights: notice,
    streams: _streams(media['url']),
    subtitles: _subtitles(answer['subtitols']),
  );
}

Map<dynamic, dynamic> _field(Map<dynamic, dynamic> parent, String name) {
  final value = parent[name];
  return value is Map ? value : const {};
}

/// `media.url` is a list of files, or a bare address on some videos.
List<ReplayStream> _streams(Object? raw) {
  final entries = raw is List ? raw : [raw];
  return [for (final entry in entries) ?_stream(entry)];
}

ReplayStream? _stream(Object? entry) {
  final file = entry is Map ? entry['file'] : entry;
  final uri = file is String ? Uri.tryParse(file) : null;
  if (uri == null || !uri.hasScheme) return null;
  final label = entry is Map && entry['label'] is String ? entry['label'] as String : 'MP4';
  return ReplayStream(url: uri, label: label);
}

/// `subtitols` is a list of files, or a single object.
List<ReplaySubtitle> _subtitles(Object? raw) {
  final entries = raw is List ? raw : [raw];
  return [
    for (final entry in entries.whereType<Map>())
      if (entry['url'] is String && Uri.tryParse(entry['url'] as String) != null)
        ReplaySubtitle(
          url: Uri.parse(entry['url'] as String),
          languageCode: entry['iso'] as String? ?? 'ca',
          label: entry['text'] as String? ?? 'Català',
        ),
  ];
}

/// Plays a video from its media answer.
///
/// The answer is 200 with addresses even for videos limited to Spain; the hosts then refuse viewers elsewhere. For
/// those, one byte of the stream is requested, so a viewer in Spain plays and any other viewer is told why.
class ThreeCatPlayback {
  final ThreeCatApi _api;

  ThreeCatPlayback(this._api);

  Future<ReplayPlayback> resolve(String videoId) async {
    final Map<String, dynamic> answer;
    try {
      answer = await _api.media(videoId);
    } on ThreeCatRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
    final media = threeCatParseMedia(answer);
    if (!media.active) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    if (media.streams.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    if (media.spainOnly) {
      final refusal = await _refusal(media);
      if (refusal != null) return refusal;
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: media.streams,
      subtitles: media.subtitles,
    );
  }

  Future<ReplayPlayback?> _refusal(ThreeCatMedia media) async {
    final stream = media.streams.where((s) => s.label != 'DASH').firstOrNull ?? media.streams.first;
    try {
      final status = await _api.probe(stream.url);
      if (status == 401 || status == 403) {
        return ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: media.rights);
      }
      if (status >= 400) return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'HTTP $status');
    } on ThreeCatRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
    return null;
  }
}
