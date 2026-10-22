import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ruv_api.dart';
import 'ruv_browse.dart';
import 'ruv_catalog.dart';
import 'ruv_films.dart';
import 'ruv_ids.dart';
import 'ruv_images.dart';
import 'ruv_playback.dart';
import 'ruv_scope.dart';

/// RÚV (Iceland): clear HLS up to 1080p for the programmes licensed worldwide, Icelandic audio and subtitles.
///
/// About two thirds of the catalogue is licensed worldwide. The rest is Iceland-only: the catalogue flags it per
/// episode, so a viewer abroad sees those titles greyed out before pressing play.
class RuvProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: ruvSourceId,
    name: 'RÚV',
    language: 'is',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 40,
  );

  final RuvBrowse _browse;
  final RuvCatalog _catalog;
  final RuvPlayback _playback;
  final RuvAvailability _availability;

  factory RuvProvider(MediaServerHttpClient http, {DateTime Function()? clock}) =>
      RuvProvider.withApi(RuvApi(http, now: clock), clock: clock);

  /// Test seam: a provider over an API whose responses the caller controls.
  factory RuvProvider.withApi(RuvApi api, {DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    final scopes = RuvScopes();
    return RuvProvider._(
      RuvBrowse(api, scopes, RuvFilmCheck(api, now), now, pageSize: _source.listingPageSize),
      RuvCatalog(api, scopes, now),
      RuvPlayback(api, now),
      RuvAvailability(api, scopes),
    );
  }

  RuvProvider._(this._browse, this._catalog, this._playback, this._availability);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() => _browse.categories();

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) => _browse.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) => _catalog.title(ref);

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) => _catalog.children(ref);

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) => _playback.resolve(ref);

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) =>
      _availability.predict(titles, country);

  @override
  String imageUrl(String reference, {int? width, int? height}) => ruvImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isRuvImage(reference);

  @override
  void close() {}
}
