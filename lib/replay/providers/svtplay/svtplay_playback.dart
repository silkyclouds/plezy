import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'svtplay_api.dart';
import 'svtplay_dates.dart';

/// Resolves a video id to clear HLS streams, or says why it cannot be played.
///
/// The video API answers 200 for titles that are Sweden-only or protected, so the `rights` object and the CDN decide.
/// DRM titles are reported, never attempted.
class SvtPlayPlayback {
  final SvtPlayApi _api;
  final DateTime Function() _now;

  SvtPlayPlayback(this._api, this._now);

  Future<ReplayPlayback> resolve(String svtId) async {
    final Map<String, dynamic> video;
    try {
      video = await _api.video(svtId);
    } on SvtPlayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }

    final blocked = svtPlaybackBlock(video, _now());
    if (blocked != null) return blocked;
    final streams = svtStreams(video);
    if (streams.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

    if (svtIsSwedenOnly(video) && !await _api.manifestReachable(streams.first.url)) {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.geoBlocked,
        message: 'This programme can only be watched in Sweden.',
      );
    }
    return ReplayPlayback(availability: ReplayAvailability.playable, streams: streams);
  }
}

/// A reason the video cannot be played, read from the response alone, or null when the streams may be used.
ReplayPlayback? svtPlaybackBlock(Map<String, dynamic> video, DateTime now) {
  if (video['live'] == true) {
    return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'Live streams are not supported.');
  }
  final rights = video['rights'];
  if (rights is! Map) {
    // A Sweden-only title seen from abroad can come back with no rights and no streams at all.
    return svtStreams(video).isEmpty
        ? const ReplayPlayback.unavailable(
            ReplayAvailability.geoBlocked,
            message: 'This programme can only be watched in Sweden.',
          )
        : null;
  }
  if (rights['drmCopyProtection'] == true) {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.drmProtected,
      message: 'This programme is copy protected and cannot be played here.',
    );
  }
  final until = svtDate(rights['validTo']);
  if (until != null && until.isBefore(now)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  final from = svtDate(rights['validFrom']);
  if (from != null && from.isAfter(now)) return const ReplayPlayback.unavailable(ReplayAvailability.upcoming);
  return null;
}

/// Whether the rights restrict the title to Sweden, which only the CDN can say is a problem for this viewer.
bool svtIsSwedenOnly(Map<String, dynamic> video) => (video['rights'] as Map?)?['geoBlockedSweden'] == true;

/// The HLS master of the default version, then of the audio-described and sign-language versions when they exist.
List<ReplayStream> svtStreams(Map<String, dynamic> video) {
  final variants = video['variants'];
  final versions = <(String, Object?)>[
    ('Standard', variants is Map && variants['default'] is Map ? variants['default'] : video),
    if (variants is Map) ('AD', variants['audioDescribed']),
    if (variants is Map) ('Sign language', variants['signInterpreted']),
  ];
  return [
    for (final (label, version) in versions)
      if (_manifest(version) case final url?) ReplayStream(url: url, label: label),
  ];
}

// H.264 with AAC plays everywhere; the "full" ladders add H.265 and Atmos renditions.
const _preferredFormats = ['hls-cmaf-avc', 'hls'];

Uri? _manifest(Object? version) {
  final references = version is Map ? version['videoReferences'] : null;
  if (references is! List) return null;
  for (final format in _preferredFormats) {
    for (final reference in references.whereType<Map>()) {
      final url = reference['url'];
      if (reference['format'] == format && url is String) return Uri.tryParse(url);
    }
  }
  return null;
}
