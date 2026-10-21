import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'm6plus_account.dart';
import 'm6plus_api.dart';
import 'm6plus_authenticator.dart';
import 'm6plus_availability.dart';
import 'm6plus_categories.dart';
import 'm6plus_directory.dart';
import 'm6plus_geo.dart';
import 'm6plus_images.dart';
import 'm6plus_mapper.dart';
import 'm6plus_playback.dart';
import 'm6plus_shows.dart';

/// M6, W9, 6ter, Gulli, Téva and Paris Première. Browsing is open, but long-form video is DRM-protected and
/// mostly limited to France, so only a few extracts and podcasts can be played.
class M6plusProvider implements ReplayProvider, ReplayAccountSupport {
  static const _source = ReplaySource(
    id: m6plusSourceId,
    name: 'M6+',
    language: 'fr',
    support: ReplayPlaybackSupport.browseOnly,
    listingPageSize: M6plusApi.pageSize,
  );

  final M6plusApi _api;
  final M6plusGeo _geo;
  final M6plusDirectory _directory;
  final M6plusShows _shows;
  final DateTime Function() _clock;
  final ReplayAuthenticator _authenticator;
  final M6plusAccount _account;

  M6plusProvider(MediaServerHttpClient http) : this.withApi(M6plusApi(http));

  /// Test seam: a provider over an API whose pacing and responses the caller controls.
  M6plusProvider.withApi(M6plusApi api, {DateTime Function()? clock, ReplayAuthenticator? authenticator})
    : this._(api, M6plusGeo(), clock ?? DateTime.now, authenticator ?? M6plusAuthenticator(api.http));

  M6plusProvider._(this._api, this._geo, this._clock, this._authenticator)
    : _directory = M6plusDirectory(_api),
      _shows = M6plusShows(_api, _geo, clock: _clock),
      _account = M6plusAccount(_authenticator, clock: _clock);

  @override
  ReplaySource get source => _source;

  @override
  ReplayAuthenticator get authenticator => _authenticator;

  @override
  set onSessionRenewed(void Function(ReplaySession session)? listener) => _account.onRenewed = listener;

  @override
  void useSession(ReplaySession? session) {
    _account.use(session);
    _api.useBearer(session == null ? null : _account.bearer);
  }

  @override
  Future<List<ReplayCategory>> categories() async => m6plusCategories;

  @override
  Future<List<ReplayRail>> home() => _directory.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _directory.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _directory.listing(browseId, page);

  @override
  Future<List<ReplayTitle>> search(String query) => _directory.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (id.startsWith('clip_')) return _shows.video(id);
    if (id.contains('/')) {
      final seasons = await _shows.seasons(id.split('/').first);
      return seasons.where((s) => s.ref == ref).firstOrNull;
    }
    return _shows.show(id);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) {
    final id = ref.nativeId;
    if (id.startsWith('clip_')) return Future.value(const []);
    return id.contains('/') ? _shows.episodes(ref) : _shows.seasons(id);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    try {
      final video = await _videoFor(ref.nativeId);
      if (video == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      return await _resolve(video);
    } on M6plusRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => m6plusImageUrl(reference);

  @override
  bool ownsImage(String reference) => isM6plusImage(reference);

  @override
  void close() {}

  /// The video to play for a reference: a clip itself, or the only full video of a single-work programme.
  Future<Map<String, dynamic>?> _videoFor(String nativeId) async {
    if (nativeId.startsWith('clip_')) return _api.video(nativeId);
    if (nativeId.contains('/')) return null;
    final videos = await _api.videos(nativeId, type: 'vi');
    return videos.length == 1 ? videos.single : null;
  }

  Future<ReplayPlayback> _resolve(Map<String, dynamic> video) async {
    final plan = m6plusPlanPlayback(video, country: _geo.country, now: _clock());
    final verdict = plan.verdict;
    if (verdict != null) return verdict;

    // Audio files are not probed: fetching one would download the whole episode.
    final first = plan.candidates.first;
    if (!first.isAudio) {
      final probe = await _api.probeManifest(first.url);
      final blocked = probe.statusCode == 403 ? m6plusParseGeoBlock(probe.body) : null;
      if (blocked != null) {
        _geo.learn(blocked.country);
        return ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: blocked.message);
      }
      if (probe.statusCode == 404 || probe.statusCode == 410) {
        return ReplayPlayback.unavailable(
          ReplayAvailability.expired,
          message: m6plusUnavailableMessage(ReplayAvailability.expired),
        );
      }
      if (probe.statusCode >= 400) {
        return ReplayPlayback.unavailable(
          ReplayAvailability.unknown,
          message: 'Le serveur de M6+ a répondu ${probe.statusCode}.',
        );
      }
    }
    return plan.playback;
  }
}
