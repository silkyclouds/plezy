import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'nfb_api.dart';
import 'nfb_browse.dart';
import 'nfb_catalog.dart';
import 'nfb_categories.dart';
import 'nfb_film_page.dart';
import 'nfb_ids.dart';
import 'nfb_images.dart';
import 'nfb_playback.dart';

/// National Film Board of Canada (nfb.ca): clear HLS for most of its English catalogue of animation, documentary
/// and short films. Titles the viewer's country cannot stream are marked geo-blocked in lists.
class NfbProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: nfbSourceId,
    name: 'NFB',
    language: 'en',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: NfbBrowse.pageSize,
  );

  final NfbApi _api;
  final NfbCatalog _catalog;
  final NfbBrowse _browse;

  NfbProvider(MediaServerHttpClient http) : this.withApi(NfbApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  NfbProvider.withApi(NfbApi api, {DateTime Function()? now}) : this._(api, NfbCatalog(api, now: now), now);

  NfbProvider._(this._api, this._catalog, DateTime Function()? now) : _browse = NfbBrowse(_api, _catalog, now: now);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => nfbCategories;

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) => _browse.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final series = parseNfbSeriesId(ref.nativeId);
    if (series != null) return series.season == null ? _catalog.show(series.slug) : _catalog.season(ref);
    final html = await _api.filmPage(ref.nativeId);
    return html == null ? null : nfbTitleFromFilmPage(html, slug: ref.nativeId);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final series = parseNfbSeriesId(ref.nativeId);
    if (series == null) return const [];
    return series.season == null ? _catalog.seasons(series.slug) : _catalog.episodes(ref);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    if (parseNfbSeriesId(ref.nativeId) != null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final html = await _api.playerPage(ref.nativeId);
      if (html == null) {
        return const ReplayPlayback.unavailable(
          ReplayAvailability.expired,
          message: 'This film is no longer on nfb.ca.',
        );
      }
      return nfbParsePlayback(html);
    } on NfbRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => nfbImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isNfbImage(reference);

  @override
  void close() {}
}
