import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'tvlocales_api.dart';

/// What the Freecaster player configuration says about one video.
class FreecasterVideo {
  final Uri? hls;

  /// Progressive MP4 renditions, lowest quality first.
  final List<Uri> mp4;
  final List<ReplaySubtitle> subtitles;
  final int? durationSeconds;

  /// Poster address: a size template when every size is rendered, else the one poster that exists.
  final String? poster;

  const FreecasterVideo({this.hls, this.mp4 = const [], this.subtitles = const [], this.durationSeconds, this.poster});
}

/// Reads the `video` object of a player configuration. Returns null when the document has none.
FreecasterVideo? parseFreecasterConfig(Map<String, dynamic> config) {
  final video = config['video'];
  if (video is! Map<String, dynamic>) return null;
  final sources = [for (final s in (video['src'] as List? ?? const []).whereType<Map<String, dynamic>>()) s];
  return FreecasterVideo(
    hls: _firstSource(sources, 'application/x-mpegurl'),
    mp4: [
      for (final s in sources)
        if (s['type'] == 'video/mp4' && _uri(s['src']) != null) _uri(s['src'])!,
    ],
    subtitles: _subtitles(video['tracks']),
    durationSeconds: (video['duration'] as num?)?.round(),
    poster: _poster(video),
  );
}

/// The HLS master, which adapts to the connection, or the best MP4 file when the video has no master.
ReplayPlayback freecasterPlayback(FreecasterVideo video) {
  final urls = video.hls != null ? [video.hls!] : video.mp4.reversed.take(1).toList();
  if (urls.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [for (final url in urls) ReplayStream(url: url, label: 'VF')],
    subtitles: video.subtitles,
  );
}

/// Turns an episode's video id into streams through the public Freecaster player configuration.
class FreecasterResolver {
  final TvLocalesApi _api;

  FreecasterResolver(this._api);

  /// The configuration of a video, or null when Freecaster answers with something that is not one.
  Future<FreecasterVideo?> video(String videoId) async => parseFreecasterConfig(await _api.embed(videoId));

  /// Never throws for the broadcaster's own refusals: they come back as an unavailable result.
  Future<ReplayPlayback> playback(String videoId) async {
    try {
      final video = await this.video(videoId);
      return video == null ? const ReplayPlayback.unavailable(ReplayAvailability.unknown) : freecasterPlayback(video);
    } on TvLocalesRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
        return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      }
      rethrow;
    }
  }
}

Uri? _firstSource(List<Map<String, dynamic>> sources, String type) {
  for (final source in sources) {
    if (source['type'] == type) return _uri(source['src']);
  }
  return null;
}

Uri? _uri(Object? value) => value is String ? Uri.tryParse(value) : null;

List<ReplaySubtitle> _subtitles(Object? tracks) {
  if (tracks is! List) return const [];
  return [
    for (final track in tracks.whereType<Map<String, dynamic>>())
      if ((track['kind'] == 'subtitles' || track['kind'] == 'captions') && _uri(track['src']) != null)
        ReplaySubtitle(
          url: _uri(track['src'])!,
          languageCode: track['lang'] as String? ?? 'fr',
          label: track['label'] as String? ?? 'Français',
        ),
  ];
}

/// The template only when 1280x720 exists; older videos stop at 640x360 and would answer 404 above it.
String? _poster(Map<String, dynamic> video) {
  final template = video['poster_template'] as String?;
  final renditions = video['poster_renditions'];
  final hasHd = renditions is List && renditions.any((r) => r is Map && r['size'] == '1280x720');
  return template != null && hasHd ? template : video['poster'] as String?;
}
