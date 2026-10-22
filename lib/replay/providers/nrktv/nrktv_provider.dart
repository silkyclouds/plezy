import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'nrktv_api.dart';
import 'nrktv_browse.dart';
import 'nrktv_catalog.dart';
import 'nrktv_geo.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_index.dart';
import 'nrktv_playback.dart';
import 'nrktv_search.dart';

/// NRK TV: the world-licensed part of the catalogue plays as clear HLS, most current drama, sport and children's
/// programmes are limited to Norway and are reported as geo-blocked.
class NrkTvProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: nrkSourceId,
    name: 'NRK TV',
    language: 'no',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 30,
  );

  final NrkApi _api;
  final NrkGeoMemory _geo;
  final NrkCatalog _catalog;
  final NrkBrowse _browse;
  final NrkIndex _index;
  final NrkAvailabilityForecast _forecast;
  final DateTime Function() _now;

  NrkTvProvider(MediaServerHttpClient http) : this.withApi(NrkApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  NrkTvProvider.withApi(NrkApi api, {DateTime Function()? now}) : this._(api, now ?? DateTime.now, NrkGeoMemory());

  NrkTvProvider._(this._api, this._now, NrkGeoMemory geo)
    : _geo = geo,
      _catalog = NrkCatalog(_api, geo, _now),
      _browse = NrkBrowse(_api, _now),
      _index = NrkIndex(_api, _now),
      _forecast = NrkAvailabilityForecast(_api, geo);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() => _browse.categories();

  @override
  Future<List<ReplayRail>> home() => _browse.rails(nrkFrontPage);

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.rails(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) {
    final size = _source.listingPageSize;
    return browseId == replayAllBrowseId ? _index.page(page, size) : _browse.flat(browseId, page, size);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return nrkTitlesFromSearch(await _api.search(trimmed));
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async => switch (parseNrkRef(ref)) {
    NrkSeriesTarget(:final seriesId) => _catalog.show(seriesId),
    NrkSeasonTarget(:final seriesId, :final season) => _catalog.season(seriesId, season),
    NrkProgramTarget(:final programId) => _catalog.program(programId),
    null => null,
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async => switch (parseNrkRef(ref)) {
    NrkSeriesTarget(:final seriesId) => _catalog.seasons(seriesId),
    NrkSeasonTarget(:final seriesId, :final season) => _catalog.episodes(seriesId, season),
    _ => const [],
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = parseNrkRef(ref);
    if (target is! NrkProgramTarget) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final playback = nrkParsePlayback(await _api.manifest(target.programId), _now());
      _noteGeo(target.programId, playback);
      return playback;
    } on NrkRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (nrkIsNotFound(e)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _forecast.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => nrkImageUrl(reference, width: width);

  @override
  bool ownsImage(String reference) => isNrkImage(reference);

  @override
  void close() {}

  /// A manifest is the final word on geography, so what it says is remembered for the lists.
  void _noteGeo(String programId, ReplayPlayback playback) {
    if (playback.availability == ReplayAvailability.geoBlocked) _geo.remember(programId, norwayOnly: true);
    if (playback.isPlayable) _geo.remember(programId, norwayOnly: false);
  }
}
