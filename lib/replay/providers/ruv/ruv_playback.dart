import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ruv_api.dart';
import 'ruv_dates.dart';
import 'ruv_ids.dart';
import 'ruv_queries.dart';

const _geoMessage = 'This programme can only be watched from Iceland.';

/// Turns an episode into something playable.
///
/// RÚV has no resolve step: the catalogue gives the HLS master of the episode. Iceland-only masters sit in a
/// different folder and the CDN answers 403 outside Iceland, so the master is fetched to learn what this viewer
/// gets. Streams are clear; there is no DRM and no login.
class RuvPlayback {
  final RuvApi _api;
  final DateTime Function() _now;

  RuvPlayback(this._api, this._now);

  Future<ReplayPlayback> resolve(ReplayRef ref) async {
    final target = ruvTarget(ref);
    if (target == null || target.part == ruvOnlySeason) {
      return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    }
    try {
      final episodeId = target.part ?? await _onlyEpisode(target.programId);
      if (episodeId == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
      final episode = await _episode(target.programId, episodeId);
      return episode == null ? const ReplayPlayback.unavailable(ReplayAvailability.expired) : await _play(episode);
    } on RuvRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  /// The id of the one episode of a film. A programme with several episodes is not played as a whole.
  Future<String?> _onlyEpisode(int programId) async {
    final data = await _api.fetch(ruvCardsBatchQuery([programId]));
    final episodes = (data['a0'] as Map?)?['episodes'];
    if (episodes is! List || episodes.length != 1) return null;
    return (episodes.single as Map)['id'] as String?;
  }

  Future<Map<String, dynamic>?> _episode(int programId, String episodeId) async {
    final document = ruvEpisodeQuery(episodeId);
    if (document == null) return null;
    final data = await _api.fetch(document, variables: {'p': programId});
    final episodes = (data['Program'] as Map?)?['episodes'];
    return episodes is List && episodes.isNotEmpty ? episodes.first as Map<String, dynamic> : null;
  }

  Future<ReplayPlayback> _play(Map<String, dynamic> episode) async {
    final now = _now();
    final until = ruvExpiry(episode['file_expires']);
    if (until != null && until.isBefore(now)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);

    final master = Uri.tryParse(episode['file'] as String? ?? '');
    if (master == null || !master.hasScheme) {
      final start = ruvDateTime(episode['firstrun']);
      final reason = start != null && start.isAfter(now) ? ReplayAvailability.upcoming : ReplayAvailability.unknown;
      return ReplayPlayback.unavailable(reason);
    }
    return ruvPlaybackFromProbe(episode, master, await _api.probeManifest(master));
  }
}

/// The outcome of asking the CDN for [master]: a refusal explains itself, a playlist becomes a stream.
ReplayPlayback ruvPlaybackFromProbe(Map<String, dynamic> episode, Uri master, RuvManifestProbe probe) {
  switch (probe.status) {
    case 401 || 403:
      return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage);
    case 404:
      return const ReplayPlayback.unavailable(ReplayAvailability.expired);
  }
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: master, label: 'IS')],
    subtitles: probe.body.contains('TYPE=SUBTITLES') ? const [] : _sidecarSubtitles(episode),
  );
}

/// Subtitle files listed in the catalogue. They are only offered when the playlist does not already carry them,
/// so the player never shows the same track twice.
List<ReplaySubtitle> _sidecarSubtitles(Map<String, dynamic> episode) {
  final listed = episode['subtitles'];
  if (listed is! List) return const [];
  return [
    for (final entry in listed.whereType<Map<String, dynamic>>())
      if (Uri.tryParse(entry['value'] as String? ?? '') case final url? when url.hasScheme)
        _subtitle(url, entry['name'] as String? ?? 'is'),
  ];
}

ReplaySubtitle _subtitle(Uri url, String language) =>
    ReplaySubtitle(url: url, languageCode: language, label: language == 'is' ? 'Íslenska' : language);
