import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ceskatelevize_api.dart';
import 'ceskatelevize_browse.dart';
import 'ceskatelevize_catalog.dart';
import 'ceskatelevize_categories.dart';
import 'ceskatelevize_images.dart';
import 'ceskatelevize_mapper.dart';
import 'ceskatelevize_playback.dart';
import 'ceskatelevize_queries.dart';
import 'ceskatelevize_refs.dart';
import 'ceskatelevize_search.dart';

/// Česká televize (iVysílání): clear HLS for the part of the catalogue licensed outside the Czech Republic.
///
/// The catalogue does not say what a viewer's country may watch, so geoblocking shows only at playback.
class CeskaTelevizeProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: ceskatelevizeSourceId,
    name: 'Česká televize',
    language: 'cs',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 100,
  );

  final CeskaTelevizeApi _api;
  final CeskaTelevizeBrowse _browse;
  final CeskaTelevizeCatalog _catalog;
  final CeskaTelevizeSearch _search;

  CeskaTelevizeProvider(MediaServerHttpClient http) : this.withApi(CeskaTelevizeApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  CeskaTelevizeProvider.withApi(CeskaTelevizeApi api, {DateTime Function()? clock})
    : this._(api, CeskaTelevizeMapper(clock: clock));

  CeskaTelevizeProvider._(this._api, CeskaTelevizeMapper mapper)
    : _browse = CeskaTelevizeBrowse(_api, mapper),
      _catalog = CeskaTelevizeCatalog(_api, mapper),
      _search = CeskaTelevizeSearch(_api, mapper);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async =>
      ceskatelevizeCategories(await _api.query(ceskatelevizeMenuQuery, ttl: CeskaTelevizeApi.menuTtl));

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) => _search.run(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) => switch (parseCeskaTelevizeId(ref.nativeId)) {
    CeskaTelevizeShowId(:final sidp) => _catalog.show(sidp),
    CeskaTelevizeFilmId(:final sidp) => _catalog.show(sidp, asShow: false),
    final CeskaTelevizeSeasonId season => _catalog.season(season),
    CeskaTelevizeEpisodeId(:final idec) => _catalog.episode(idec),
    null => Future<ReplayTitle?>.value(),
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) => switch (parseCeskaTelevizeId(ref.nativeId)) {
    CeskaTelevizeShowId(:final sidp) => _catalog.seasons(sidp),
    final CeskaTelevizeSeasonId season => _catalog.episodes(season),
    CeskaTelevizeFilmId() || CeskaTelevizeEpisodeId() || null => Future.value(const <ReplayTitle>[]),
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = parseCeskaTelevizeId(ref.nativeId);
    final idec = switch (id) {
      CeskaTelevizeEpisodeId(:final idec) => idec,
      CeskaTelevizeFilmId(:final sidp) => await _catalog.filmEpisode(sidp),
      _ => null,
    };
    if (idec == null) {
      final isFilm = id is CeskaTelevizeFilmId;
      return ReplayPlayback.unavailable(isFilm ? ReplayAvailability.expired : ReplayAvailability.unknown);
    }
    try {
      return ceskatelevizeParsePlayback(await _api.playlist(idec));
    } on CeskaTelevizeRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => ceskatelevizeImageUrl(reference);

  @override
  bool ownsImage(String reference) => isCeskaTelevizeImage(reference);

  @override
  void close() {}
}
