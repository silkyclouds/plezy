import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ted_api.dart';
import 'ted_home.dart';
import 'ted_ids.dart';
import 'ted_images.dart';
import 'ted_playback.dart';
import 'ted_playlists.dart';
import 'ted_talks.dart';
import 'ted_topics.dart';

/// TED: clear HLS for every talk, with up to 27 subtitle languages. Talks are movies; playlists are shows with one season.
class TedProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: tedSourceId,
    name: 'TED',
    language: 'en',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: tedPageSize,
  );

  final TedApi _api;
  final TedTalks _talks;
  final TedPlaylists _playlists;

  /// [language] limits the latest and full listings to talks translated into it, with titles in that language.
  TedProvider(MediaServerHttpClient http, {String? language}) : this.withApi(TedApi(http), language: language);

  /// Test seam: a provider over an API whose responses the caller controls.
  TedProvider.withApi(TedApi api, {String? language})
    : _api = api,
      _talks = TedTalks(api, language: language),
      _playlists = TedPlaylists(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => tedCategories();

  @override
  Future<List<ReplayRail>> home() => tedHomeRails(_talks, _playlists);

  @override
  Future<List<ReplayRail>> category(String categoryId) => tedCategoryRails(_talks, _playlists, categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) {
    final topic = tedTopicOfBrowseId(browseId);
    if (browseId == tedLatestBrowseId) return _talks.latest(page: page);
    if (browseId == tedPlaylistsBrowseId) return _playlists.list(page: page);
    if (topic != null) return _talks.topic(topic, page: page);
    return Future.value(const ReplayPage(titles: [], totalCount: 0));
  }

  @override
  Future<List<ReplayTitle>> search(String query) => _talks.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final target = tedTarget(ref);
    if (target == null) return null;
    return switch (target.kind) {
      TedRefKind.talk => _talks.talk(target.slug),
      TedRefKind.playlist => _playlists.show(target.slug),
      TedRefKind.season => _playlists.season(target.slug),
    };
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final target = tedTarget(ref);
    if (target == null) return const [];
    switch (target.kind) {
      case TedRefKind.talk:
        return const [];
      case TedRefKind.playlist:
        final season = await _playlists.season(target.slug);
        return season == null ? const [] : [season];
      case TedRefKind.season:
        return _playlists.episodes(target.slug);
    }
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = tedTarget(ref);
    if (target == null || target.kind != TedRefKind.talk) {
      return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    }
    try {
      final node = await _talks.node(target.slug);
      if (node == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      final hls = node['hlsUrl'];
      if (hls is! String || hls.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
      final master = Uri.parse(hls);
      return tedPlaybackFromMaster(master, await _api.master(master));
    } on TedRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
        return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      }
      if (e.statusCode == 403 || e.statusCode == 451) {
        return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked);
      }
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => tedImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isTedImage(reference);

  @override
  void close() => _api.clearCache();
}
