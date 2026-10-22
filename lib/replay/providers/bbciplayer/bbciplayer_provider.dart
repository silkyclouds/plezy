import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'bbciplayer_api.dart';
import 'bbciplayer_browse.dart';
import 'bbciplayer_catalog.dart';
import 'bbciplayer_images.dart';
import 'bbciplayer_mapper.dart';
import 'bbciplayer_playback.dart';

/// BBC iPlayer: a free catalogue that only streams inside the United Kingdom.
///
/// Browsing and search work from anywhere. Playback resolves the stream through the BBC media selector, which
/// refuses viewers outside the UK; that answer is reported as geo-blocked.
class BbcIplayerProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: bbcIplayerSourceId,
    name: 'BBC iPlayer',
    language: 'en',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 40,
  );

  final BbcIplayerBrowse _browse;
  final BbcIplayerCatalog _catalog;
  final BbcIplayerPlayback _playback;

  factory BbcIplayerProvider(MediaServerHttpClient http, {DateTime Function()? clock}) =>
      BbcIplayerProvider.withApi(BbcIplayerApi(http, now: clock), clock: clock);

  /// Test seam: a provider over an API whose responses the caller controls.
  factory BbcIplayerProvider.withApi(BbcIplayerApi api, {DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    return BbcIplayerProvider._(
      BbcIplayerBrowse(api, now, pageSize: _source.listingPageSize),
      BbcIplayerCatalog(api, now),
      BbcIplayerPlayback(api, now),
    );
  }

  BbcIplayerProvider._(this._browse, this._catalog, this._playback);

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
  Future<List<ReplayTitle>> children(ReplayRef ref) =>
      ref.nativeId.contains('/') ? _catalog.episodes(ref) : _catalog.seasons(ref);

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    if (ref.nativeId.contains('/')) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return await _playback.resolve(ref.nativeId);
    } on BbcIplayerRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => bbcImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isBbcImage(reference);

  @override
  void close() {}
}
