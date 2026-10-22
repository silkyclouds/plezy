import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'orftvthek_api.dart';
import 'orftvthek_browse.dart';
import 'orftvthek_catalog.dart';
import 'orftvthek_episodes.dart';
import 'orftvthek_geo.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_images.dart';
import 'orftvthek_mapper.dart';
import 'orftvthek_playback.dart';
import 'orftvthek_profiles.dart';
import 'orftvthek_search.dart';

/// ORF ON (formerly ORF TVthek): clear HLS for the part of the catalogue ORF licenses worldwide, which is most news,
/// regional, magazine, talk and archive programmes. Films, series and sport are mostly limited to Austria, and the few
/// protected titles are reported as such.
class OrfTvthekProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: orfSourceId,
    name: 'ORF ON',
    language: 'de',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: OrfBrowse.pageSize,
  );

  final OrfCatalog _catalog;
  final OrfBrowse _browse;
  final OrfSearch _search;
  final OrfPlaybackResolver _playback;
  final OrfAvailabilityForecast _forecast;

  OrfTvthekProvider(MediaServerHttpClient http) : this.withApi(OrfApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  OrfTvthekProvider.withApi(OrfApi api, {DateTime Function()? now}) : this._(api, now ?? DateTime.now, OrfGeoMemory());

  OrfTvthekProvider._(OrfApi api, DateTime Function() now, OrfGeoMemory geo)
    : this._wired(api, now, geo, OrfProfileIndex(api, now), OrfMapper(now, geo));

  OrfTvthekProvider._wired(
    OrfApi api,
    DateTime Function() now,
    OrfGeoMemory geo,
    OrfProfileIndex index,
    OrfMapper mapper,
  ) : _catalog = OrfCatalog(api, index, OrfEpisodeLoader(api, now), mapper),
      _browse = OrfBrowse(api, index, mapper),
      _search = OrfSearch(api, index, mapper),
      _playback = OrfPlaybackResolver(api, now),
      _forecast = OrfAvailabilityForecast(geo);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() => _browse.categories();

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page);

  @override
  Future<List<ReplayTitle>> search(String query) => _search.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async => switch (parseOrfRef(ref)) {
    OrfEpisodeTarget(:final id) => _catalog.episode(id),
    OrfSegmentTarget(:final id) => _catalog.clip(id),
    OrfProfileTarget() || OrfSeriesTarget() => _catalog.show(ref),
    OrfSeasonTarget() => _catalog.season(ref),
    null => null,
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async => switch (parseOrfRef(ref)) {
    OrfProfileTarget() || OrfSeriesTarget() => _catalog.seasons(ref),
    OrfSeasonTarget() => _catalog.episodes(ref),
    _ => const [],
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) => _playback.resolve(parseOrfRef(ref));

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async =>
      _forecast.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => orfImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isOrfImage(reference);

  @override
  void close() {}
}
