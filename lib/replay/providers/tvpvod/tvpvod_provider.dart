import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'tvpvod_api.dart';
import 'tvpvod_browse.dart';
import 'tvpvod_catalog.dart';
import 'tvpvod_categories.dart';
import 'tvpvod_images.dart';
import 'tvpvod_playback.dart';
import 'tvpvod_refs.dart';
import 'tvpvod_rights.dart';

/// TVP VOD: Polish public television. Streams are clear HLS, but most of the catalogue is licensed for Poland only.
class TvpVodProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: tvpvodSourceId,
    name: 'TVP VOD',
    language: 'pl',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: tvpPageSize,
  );

  final TvpVodApi _api;
  final TvpRights _rights;
  final TvpCatalog _catalog;
  final TvpBrowse _browse;

  TvpVodProvider(MediaServerHttpClient http) : this.withApi(TvpVodApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  TvpVodProvider.withApi(TvpVodApi api) : this._(api, TvpRights(api));

  TvpVodProvider._(this._api, this._rights) : _catalog = TvpCatalog(_api, _rights), _browse = TvpBrowse(_api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => tvpCategories;

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
    final season = tvpSeasonParts(ref);
    if (season != null) return _catalog.season(season.serialId, season.seasonId);
    return _catalog.title(ref.nativeId);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final season = tvpSeasonParts(ref);
    if (season != null) return _catalog.episodes(season.serialId, season.seasonId);
    return _catalog.seasons(ref.nativeId);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    if (tvpSeasonParts(ref) != null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    final id = ref.nativeId;
    try {
      final reply = await _api.playlist(id);
      final playback = tvpParsePlayback(reply);
      if (playback.availability == ReplayAvailability.geoBlocked) _rights.markRefused(id);
      if (!playback.isPlayable) return playback;
      return tvpParsePlayback(reply, credits: await _catalog.credits(id));
    } on TvpVodRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _rights.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => tvpImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isTvpImage(reference);

  @override
  void close() {}
}
