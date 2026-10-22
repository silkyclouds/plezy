import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'drtv_access.dart';
import 'drtv_alphabet.dart';
import 'drtv_api.dart';
import 'drtv_availability.dart';
import 'drtv_catalog.dart';
import 'drtv_categories.dart';
import 'drtv_images.dart';
import 'drtv_mapper.dart';
import 'drtv_playback.dart';
import 'drtv_rails.dart';
import 'drtv_refs.dart';
import 'drtv_search.dart';

/// DR TV (Denmark): clear HLS for the part of the catalogue licensed worldwide, Denmark-only and DRM titles marked.
class DrtvProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: drtvSourceId,
    name: 'DR TV',
    language: 'da',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 100,
  );
  static const _homeListSize = 24;
  static const _prefetchedLists = 8;

  final DrtvApi _api;
  final DrtvMapper _mapper;
  final DrtvCatalog _catalog;
  final DrtvRails _rails;
  final DrtvAlphabet _alphabet;

  DrtvProvider(MediaServerHttpClient http) : this.withApi(DrtvApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  DrtvProvider.withApi(DrtvApi api, {DateTime Function()? clock})
    : this._(api, DrtvMapper(DrtvAccessBook(), clock: clock), clock);

  DrtvProvider._(this._api, this._mapper, DateTime Function()? clock)
    : _catalog = DrtvCatalog(_api, _mapper),
      _rails = DrtvRails(_api, _mapper),
      _alphabet = DrtvAlphabet(_api, _mapper, clock: clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => drtvCategories;

  @override
  Future<List<ReplayRail>> home() async =>
      _rails.fromPage(await _api.page('/', listPageSize: _homeListSize, maxListPrefetch: _prefetchedLists));

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final path = drtvCategoryPath(categoryId);
    if (path == null) return const [];
    return _rails.fromPage(await _api.page(path, listPageSize: _homeListSize, maxListPrefetch: _prefetchedLists));
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final size = _source.listingPageSize;
    if (browseId == replayAllBrowseId) return _alphabet.page(page, size);
    final listId = DrtvRails.listIdOf(browseId);
    if (listId == null) return const ReplayPage(titles: [], totalCount: 0);

    final body = await _api.list(listId, page: page + 1, pageSize: size);
    final titles = _mapper.titles(body?['items'] as List? ?? const []);
    final seen = page * size + titles.length;
    return ReplayPage(titles: titles, totalCount: DrtvRails.hasMore(body?['paging']) ? seen + 1 : seen);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return drtvSearchResults(await _api.search(trimmed), _mapper);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) => switch (_idOf(ref)) {
    DrtvShowId(:final showId) => _catalog.show(showId),
    DrtvSeasonId(:final seasonId) => _catalog.season(seasonId),
    DrtvAllEpisodesId(:final showId) => _catalog.allSeason(showId),
    DrtvPlayableId(:final itemId) => _catalog.playable(itemId),
    null => Future<ReplayTitle?>.value(),
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) => switch (_idOf(ref)) {
    DrtvShowId(:final showId) => _catalog.seasons(showId),
    DrtvSeasonId(:final seasonId) => _catalog.episodes(seasonId),
    DrtvAllEpisodesId(:final showId) => _catalog.allEpisodes(showId),
    DrtvPlayableId() || null => Future.value(const <ReplayTitle>[]),
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = _idOf(ref);
    if (id is! DrtvPlayableId) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    if (_mapper.book.of(ref)?.drm ?? false) return _protected;
    try {
      final videos = await _api.videos(id.itemId);
      if (videos == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      final plan = drtvParseVideos(videos);
      final probe = plan.geoProbe;
      return probe == null ? plan.playback : await _afterGeoProbe(plan.playback, probe);
    } on DrtvRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async =>
      drtvPredictAvailability(_mapper.book, titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => drtvImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isDrtvImage(reference);

  @override
  void close() {}

  static const _protected = ReplayPlayback.unavailable(ReplayAvailability.drmProtected, message: 'DRM protected');

  /// A Denmark-only stream answers 200 at the resolver and 403 at the CDN when the viewer is abroad.
  Future<ReplayPlayback> _afterGeoProbe(ReplayPlayback playback, Uri manifest) async {
    final status = await _api.manifestStatus(manifest);
    if (status >= 200 && status < 300) return playback;
    return switch (status) {
      403 => const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked, message: 'Only available in Denmark'),
      404 => const ReplayPlayback.unavailable(ReplayAvailability.expired),
      _ => ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'Stream answered HTTP $status'),
    };
  }

  DrtvId? _idOf(ReplayRef ref) => ref.source == drtvSourceId ? parseDrtvId(ref.nativeId) : null;
}
