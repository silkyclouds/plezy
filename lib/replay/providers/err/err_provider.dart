import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'err_api.dart';
import 'err_availability.dart';
import 'err_catalog.dart';
import 'err_categories.dart';
import 'err_images.dart';
import 'err_listing.dart';
import 'err_page_mapper.dart';
import 'err_playback.dart';
import 'err_rails.dart';
import 'err_refs.dart';

/// ERR Jupiter: clear HLS for the part of the catalogue licensed worldwide, Estonian metadata and subtitles.
class ErrProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: errSourceId,
    name: 'ERR Jupiter',
    language: 'et',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 30,
  );

  final ErrApi _api;
  final ErrCatalog _catalog;
  final ErrListing _listing;
  final ErrPlayback _playback;
  final ErrAvailability _availability;

  ErrProvider(MediaServerHttpClient http) : this.withApi(ErrApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  ErrProvider.withApi(ErrApi api)
    : _api = api,
      _catalog = ErrCatalog(api),
      _listing = ErrListing(api),
      _playback = ErrPlayback(api),
      _availability = ErrAvailability(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => errCategories;

  @override
  Future<List<ReplayRail>> home() => category(errHomeUrl);

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final page = await _api.categoryPage(categoryId);
    if (page == null) return const [];
    final rows = errRailsFromCategory(page);
    return rows.isNotEmpty ? rows : errRailsFromGenre(categoryId, page);
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) =>
      _listing.page(browseId, page: page, size: _source.listingPageSize);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : errTitles(await _api.search(trimmed));
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    if (errSeasonParts(ref) != null) return _catalog.season(ref);
    final id = errContentId(ref);
    if (id == null) return null;
    final page = await _api.contentPage(id);
    final main = page?['mainContent'];
    if (page == null || main is! Map) return null;
    // ERR answers a programme id with its first episode, so only a page about this very id describes an item.
    return (main['id'] as num?)?.toInt() == id ? errTitleFromPage(page) : _catalog.show(id);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) {
    if (errSeasonParts(ref) != null) return _catalog.episodes(ref);
    final id = errContentId(ref);
    return id == null ? Future.value(const []) : _catalog.seasons(id);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) => _playback.resolve(ref);

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _availability.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => errImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isErrImage(reference);

  @override
  void close() {}
}
