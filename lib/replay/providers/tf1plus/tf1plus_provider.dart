import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../auth/replay_auth.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'tf1plus_api.dart';
import 'tf1plus_authenticator.dart';
import 'tf1plus_catalog.dart';
import 'tf1plus_images.dart';
import 'tf1plus_media_title.dart';
import 'tf1plus_mapper.dart';
import 'tf1plus_playback.dart';
import 'tf1plus_refs.dart';
import 'tf1plus_sections.dart';
import 'tf1plus_session.dart';

/// TF1+: complete browsing and search, but every stream seen so far is DRM protected or needs an account,
/// so nothing is known to play here. Playback reports the reason instead of a stream. Signing in changes
/// who asks for playback, not what the broadcaster delivers: protected streams stay protected.
class Tf1PlusProvider implements ReplayProvider, ReplayAccountSupport {
  static const _source = ReplaySource(
    id: tf1SourceId,
    name: 'TF1+',
    language: 'fr',
    support: ReplayPlaybackSupport.browseOnly,
  );

  /// Videos listed next to the programmes of a search.
  static const _searchVideoLimit = 20;

  final Tf1Api _api;
  final Tf1Catalog _catalog;
  final Tf1Authenticator _authenticator;
  final Tf1SessionHolder _session;

  Tf1PlusProvider(MediaServerHttpClient http) : this.withApi(Tf1Api(http));

  /// Test seam: a provider over an API whose responses and pacing the caller controls.
  Tf1PlusProvider.withApi(Tf1Api api) : this._(api, Tf1Authenticator(api.http));

  Tf1PlusProvider._(this._api, this._authenticator)
    : _catalog = Tf1Catalog(_api),
      _session = Tf1SessionHolder(_authenticator);

  @override
  ReplayAuthenticator get authenticator => _authenticator;

  /// Only playback acts as the user: the catalogue is the same for everyone, so its caches stay.
  @override
  void useSession(ReplaySession? session) => _session.use(session);

  @override
  set onSessionRenewed(void Function(ReplaySession session)? listener) => _session.onRenewed = listener;

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => [for (final section in tf1Sections) section.category];

  @override
  Future<List<ReplayRail>> home() async {
    final sections = tf1Sections.where((s) => s.onHome);
    final rails = await Future.wait([for (final section in sections) _rail(section)]);
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final section = tf1Sections.where((s) => s.id == categoryId).firstOrNull;
    if (section == null) return const [];
    final rail = await _rail(section);
    return rail.titles.isEmpty ? const [] : [rail];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final filter = browseId == replayAllBrowseId ? const <String, String>{} : tf1FilterFor(browseId);
    if (filter == null) return const ReplayPage(titles: [], totalCount: 0);
    final programs = await _api.programs(filter, page: page, limit: _source.listingPageSize);
    return ReplayPage(
      titles: tf1ProgramTitles(programs?['items']),
      totalCount: (programs?['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final (programs, videos) = await (
      _api.searchPrograms(trimmed, limit: _source.listingPageSize),
      _api.searchVideos(trimmed, limit: _searchVideoLimit),
    ).wait;
    return [...tf1ProgramTitles(programs?['items']), ...tf1VideoTitles(videos?['items'])];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (tf1IsVideoId(id)) return _videoTitle(id);
    if (tf1IsSeasonId(id)) {
      final seasons = await _catalog.seasons(tf1SplitSeasonId(id).programSlug);
      return seasons.where((s) => s.ref == ref).firstOrNull;
    }
    return _catalog.program(id);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = ref.nativeId;
    if (tf1IsVideoId(id)) return const [];
    return tf1IsSeasonId(id) ? _catalog.episodes(ref) : _catalog.seasons(id);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = ref.nativeId;
    if (tf1IsSeasonId(id)) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    final videoId = tf1IsVideoId(id) ? id : await _filmVideoId(id);
    if (videoId == null) return _notAFilm(id);
    try {
      final playback = tf1ParsePlayback(await _api.mediaInfo(videoId, bearerToken: await _session.bearer()));
      return _session.isSignedIn ? _explainRefusalToAccount(playback) : playback;
    } on Tf1RateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => tf1ImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isTf1Image(reference);

  @override
  void close() {}

  /// A signed-in user told to log in would be misled: the account just has no right to this video.
  ReplayPlayback _explainRefusalToAccount(ReplayPlayback playback) {
    if (playback.availability != ReplayAvailability.loginRequired) return playback;
    return const ReplayPlayback.unavailable(
      ReplayAvailability.loginRequired,
      message: 'The signed-in TF1+ account is not entitled to this video.',
    );
  }

  Future<ReplayRail> _rail(Tf1Section section) async {
    final programs = await _api.programs(section.filter, limit: _source.listingPageSize);
    return ReplayRail(
      id: section.id,
      title: section.title,
      titles: tf1ProgramTitles(programs?['items']),
      moreBrowseId: section.id,
    );
  }

  Future<ReplayTitle?> _videoTitle(String videoId) async {
    try {
      return tf1TitleFromMediaInfo(videoId, await _api.mediaInfo(videoId));
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// A programme ref is playable only as a film, whose single replay is the video.
  Future<String?> _filmVideoId(String slug) async => (await _catalog.singleReplay(slug)).videoId;

  /// The programme has no single replay: none left means it is gone, several means it is a show.
  Future<ReplayPlayback> _notAFilm(String slug) async {
    final replay = await _catalog.singleReplay(slug);
    final reason = replay.total == 0 ? ReplayAvailability.expired : ReplayAvailability.unknown;
    return ReplayPlayback.unavailable(reason);
  }
}
