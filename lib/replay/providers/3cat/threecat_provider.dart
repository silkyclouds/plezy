import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'threecat_api.dart';
import 'threecat_browse.dart';
import 'threecat_catalog.dart';
import 'threecat_geo.dart';
import 'threecat_ids.dart';
import 'threecat_images.dart';
import 'threecat_index.dart';
import 'threecat_mapper.dart';
import 'threecat_playback.dart';
import 'threecat_search.dart';

/// 3Cat, the Catalan public broadcaster: clear DASH and MP4 for the catalogue, with about one video in five limited to
/// Spain. Those are flagged in the lists, so a viewer elsewhere sees them greyed out before pressing play.
class ThreeCatProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: threeCatSourceId,
    name: '3Cat',
    language: 'ca',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: ThreeCatBrowse.pageSize,
  );

  final ThreeCatApi _api;
  final DateTime Function() _now;
  final ThreeCatGeoMemory _geo = ThreeCatGeoMemory();
  late final ThreeCatMapper _mapper = ThreeCatMapper(_geo, _now);
  late final ThreeCatCatalog _catalog = ThreeCatCatalog(_api, _mapper);
  late final ThreeCatBrowse _browse = ThreeCatBrowse(_api, _mapper, ThreeCatIndex(_api, _now));
  late final ThreeCatSearch _search = ThreeCatSearch(_api, _mapper);
  late final ThreeCatPlayback _playback = ThreeCatPlayback(_api);
  late final ThreeCatAvailabilityForecast _forecast = ThreeCatAvailabilityForecast(_api, _geo);

  ThreeCatProvider(MediaServerHttpClient http) : this.withApi(ThreeCatApi(http));

  /// Test seam: a provider over an API whose responses the caller controls, with its own clock.
  ThreeCatProvider.withApi(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => threeCatCategories;

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) => _search.run(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    switch (parseThreeCatRef(ref)) {
      case ThreeCatShowTarget(:final programmeId):
        return _catalog.show(programmeId);
      case ThreeCatSeasonTarget(:final programmeId):
        final seasons = await _catalog.seasons(programmeId);
        return seasons.where((s) => s.ref == ref).firstOrNull;
      case ThreeCatVideoTarget(:final videoId):
        return _video(videoId);
      case null:
        return null;
    }
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    switch (parseThreeCatRef(ref)) {
      case ThreeCatShowTarget(:final programmeId):
        return _catalog.seasons(programmeId);
      case ThreeCatSeasonTarget(:final programmeId, :final seasonKey):
        return _catalog.episodes(programmeId, seasonKey);
      case ThreeCatVideoTarget() || null:
        return const [];
    }
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async => switch (parseThreeCatRef(ref)) {
    ThreeCatVideoTarget(:final videoId) => await _playback.resolve(videoId),
    _ => const ReplayPlayback.unavailable(ReplayAvailability.unknown),
  };

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _forecast.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => threeCatImageUrl(reference);

  @override
  bool ownsImage(String reference) => isThreeCatImage(reference);

  @override
  void close() {}

  Future<ReplayTitle?> _video(String videoId) async {
    try {
      return threeCatVideoFromMedia(await _api.media(videoId), now: _now());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
