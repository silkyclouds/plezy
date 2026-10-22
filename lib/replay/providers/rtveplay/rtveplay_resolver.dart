import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'rtveplay_api.dart';
import 'rtveplay_catalog.dart';
import 'rtveplay_playback.dart';
import 'rtveplay_stream_urls.dart';

/// Turns a video id into a manifest the player can open, after asking RTVE whether this viewer may watch it.
class RtvePlaybackResolver {
  final RtvePlayApi _api;
  final RtveCatalog _catalog;

  RtvePlaybackResolver(this._api, this._catalog);

  Future<ReplayPlayback> resolve(String videoId) async {
    final String listing;
    try {
      listing = await _api.streamImage(videoId);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
    final manifest = rtvePickManifest(rtveDecodeStreamUrls(listing));
    if (manifest == null) {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.unknown,
        message: 'RTVE gave no stream for this video.',
      );
    }

    final probe = await _api.probe(manifest);
    final refusal = rtveRefusal(probe);
    if (refusal != null) return probe.status == 403 ? await _explainRefusal(videoId, refusal) : refusal;

    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [ReplayStream(url: manifest, label: 'Español')],
      subtitles: await _subtitles(videoId),
    );
  }

  /// A refusal reads as geoblocking, but a video past its end date or withdrawn is refused the same way, and the
  /// catalogue knows which it is. Anything the catalogue cannot settle stays a geoblock.
  Future<ReplayPlayback> _explainRefusal(String videoId, ReplayPlayback refusal) async {
    try {
      final title = await _catalog.video(videoId);
      final reason = title?.availability;
      if (reason == ReplayAvailability.expired || reason == ReplayAvailability.upcoming) {
        return ReplayPlayback.unavailable(reason!);
      }
    } on MediaServerHttpException {
      // The catalogue is only consulted to refine the answer.
    } on RtvePlayRateLimitedException {
      // Same: keep the refusal as it is.
    }
    return refusal;
  }

  Future<List<ReplaySubtitle>> _subtitles(String videoId) async {
    try {
      return rtveParseSubtitles(await _api.catalogue('videos/$videoId/subtitulos.json'));
    } on MediaServerHttpException {
      return const [];
    } on RtvePlayRateLimitedException {
      return const [];
    }
  }
}
