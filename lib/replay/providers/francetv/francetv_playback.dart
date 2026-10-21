import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// What the stream-info endpoint said: either a refusal, or the manifest still to be signed.
class FranceTvStreamInfo {
  final ReplayPlayback? refusal;
  final Uri? manifest;

  /// Service that signs [manifest], or null when the address needs no signature.
  final Uri? tokenService;
  final List<ReplaySubtitle> subtitles;
  final ReplayCredits? credits;

  const FranceTvStreamInfo.refused(ReplayPlayback this.refusal)
    : manifest = null,
      tokenService = null,
      subtitles = const [],
      credits = null;

  const FranceTvStreamInfo.ready({
    required Uri this.manifest,
    this.tokenService,
    this.subtitles = const [],
    this.credits,
  }) : refusal = null;

  /// The verdict on the rights, which is all a list badge needs.
  ReplayAvailability get availability => refusal?.availability ?? ReplayAvailability.playable;
}

/// Reads a stream-info answer. Refusals arrive as 4xx with a numeric `code` and a message in the
/// broadcaster's words; protected streams are refused here too, so nothing protected is ever opened.
FranceTvStreamInfo franceTvParseStream(int statusCode, Map<String, dynamic> body) {
  if (statusCode == 404) {
    return const FranceTvStreamInfo.refused(ReplayPlayback.unavailable(ReplayAvailability.expired));
  }
  final code = body['code'];
  if (statusCode >= 400 || code is num) {
    return FranceTvStreamInfo.refused(
      ReplayPlayback.unavailable(_reasonOf(code is num ? code.toInt() : 0), message: body['message'] as String?),
    );
  }

  final video = body['video'];
  if (video is! Map<String, dynamic>) {
    return const FranceTvStreamInfo.refused(ReplayPlayback.unavailable(ReplayAvailability.unknown));
  }
  final token = video['token'];
  if (video['drm'] == true || (token is Map && token.containsKey('drm'))) {
    return const FranceTvStreamInfo.refused(ReplayPlayback.unavailable(ReplayAvailability.drmProtected));
  }
  final manifest = Uri.tryParse(video['url'] as String? ?? '');
  if (manifest == null || !manifest.hasScheme) {
    return const FranceTvStreamInfo.refused(ReplayPlayback.unavailable(ReplayAvailability.unknown));
  }
  final service = switch (token) {
    final String url => url,
    final Map<dynamic, dynamic> map => map['akamai'] as String?,
    _ => null,
  };
  return FranceTvStreamInfo.ready(
    manifest: manifest,
    tokenService: service == null ? null : Uri.tryParse(service),
    subtitles: _subtitles(body['meta']),
    credits: _credits(video),
  );
}

ReplayAvailability _reasonOf(int code) => switch (code) {
  2009 => ReplayAvailability.geoBlocked,
  2003 => ReplayAvailability.expired,
  2004 || 2006 => ReplayAvailability.upcoming,
  2015 => ReplayAvailability.drmProtected,
  _ => ReplayAvailability.unknown,
};

/// Captions come from the metadata, since the manifests carry none. `qsm` is the broadcaster's code for
/// French captions for the deaf and hard of hearing, and is not a language code any player knows.
List<ReplaySubtitle> _subtitles(Object? meta) {
  final raw = meta is Map ? meta['subtitles'] : null;
  if (raw is! List) return const [];
  return [
    for (final entry in raw.whereType<Map<String, dynamic>>())
      if (Uri.tryParse(entry['url'] as String? ?? '') case final url? when url.hasScheme)
        entry['lang'] == 'qsm'
            ? ReplaySubtitle(url: url, languageCode: 'fr', label: 'Français (sourds et malentendants)')
            : ReplaySubtitle(
                url: url,
                languageCode: entry['lang'] as String? ?? 'und',
                label: entry['lang'] as String? ?? 'Sous-titres',
              ),
  ];
}

ReplayCredits? _credits(Map<String, dynamic> video) {
  final start = (video['closing_credits'] as Map?)?['timecode'] ?? (video['coming_next'] as Map?)?['timecode'];
  final duration = video['duration'];
  if (start is! num || duration is! num || start <= 0 || duration < start) return null;
  return ReplayCredits(
    start: Duration(milliseconds: (start * 1000).round()),
    end: Duration(milliseconds: (duration * 1000).round()),
  );
}

/// Builds the playable result from a ready [info] and the address the token service returned.
ReplayPlayback franceTvPlayable(FranceTvStreamInfo info, Uri stream) => ReplayPlayback(
  availability: ReplayAvailability.playable,
  streams: [ReplayStream(url: stream, label: 'VF')],
  subtitles: info.subtitles,
  credits: info.credits,
);
