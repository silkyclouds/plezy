import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'err_api.dart';
import 'err_mapper.dart';
import 'err_refs.dart';

const _geoMessage = 'This programme can only be watched from Estonia.';
const _drmMessage = 'This programme is copy-protected and cannot be played here.';
const _chooseEpisodeMessage = 'Choose an episode to play.';

/// Turns a film, episode or clip into something playable.
///
/// The content page carries the HLS master and the rights flags. Estonia-only masters answer 403 outside Estonia, so
/// when the page says the title is geo-restricted the master is fetched to learn what this viewer gets. Copy-protected
/// titles are never played. There is no login.
class ErrPlayback {
  final ErrApi _api;
  final DateTime Function() _now;

  ErrPlayback(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<ReplayPlayback> resolve(ReplayRef ref) async {
    final id = errContentId(ref);
    if (id == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final page = await _api.freshContentPage(id);
      final main = page?['mainContent'];
      if (page == null || main is! Map<String, dynamic>) {
        return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      }
      if ((main['id'] as num?)?.toInt() != id) {
        return const ReplayPlayback.unavailable(ReplayAvailability.unknown, message: _chooseEpisodeMessage);
      }
      return await _play(main);
    } on ErrRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  Future<ReplayPlayback> _play(Map<String, dynamic> main) async {
    final media = errFirstMedia(main);
    if (media == null) return ReplayPlayback.unavailable(_withoutMedia(main));
    final restrictions = media['restrictions'];
    final src = media['src'];
    final master = src is Map ? errMasterUrl(src) : null;

    if ((restrictions is Map && restrictions['drm'] == true) || (master?.path.contains('/hls/drm/') ?? false)) {
      return const ReplayPlayback.unavailable(ReplayAvailability.drmProtected, message: _drmMessage);
    }
    if (master == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    final stream = ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [ReplayStream(url: master, label: 'ET')],
    );
    if (restrictions is Map && restrictions['geoBlock'] == true) {
      return _afterProbe(stream, await _api.probeManifest(master));
    }
    return stream;
  }

  /// A page with no video is a recording not yet published, or one ERR has taken down.
  ReplayAvailability _withoutMedia(Map<String, dynamic> main) {
    final start = errDate(main['publicStart']);
    return start != null && start.isAfter(_now()) ? ReplayAvailability.upcoming : ReplayAvailability.expired;
  }

  ReplayPlayback _afterProbe(ReplayPlayback stream, ErrManifestProbe probe) => switch (probe.status) {
    403 => const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: _geoMessage),
    404 => const ReplayPlayback.unavailable(ReplayAvailability.expired),
    _ => stream,
  };
}

/// The HLS master of a media. ERR sends protocol-relative addresses (`//vod.err.ee/...`).
Uri? errMasterUrl(Map<dynamic, dynamic> src) {
  for (final key in const ['hls', 'hlsNew', 'hls2']) {
    final raw = src[key];
    if (raw is! String || raw.isEmpty) continue;
    final uri = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return uri;
  }
  return null;
}
