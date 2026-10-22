import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'stvplayer_access.dart';
import 'stvplayer_api.dart';
import 'stvplayer_browse.dart';
import 'stvplayer_catalog.dart';
import 'stvplayer_images.dart';
import 'stvplayer_mapper.dart';
import 'stvplayer_playback.dart';
import 'stvplayer_refs.dart';

/// STV Player (Scotland, UK): an open catalogue and Brightcove streams that only play inside the United Kingdom.
///
/// Browsing and search work from anywhere. Each episode lists where it may be watched, so a viewer abroad sees
/// UK-only episodes greyed out before pressing play; playback outside the UK ends in a geo-block verdict.
class StvPlayerProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: stvPlayerSourceId,
    name: 'STV Player',
    language: 'en',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 24,
  );

  final StvPlayerRestrictions _restrictions;
  final StvPlayerBrowse _browse;
  final StvPlayerCatalog _catalog;
  final StvPlayerPlayback _playback;

  factory StvPlayerProvider(MediaServerHttpClient http, {DateTime Function()? clock}) =>
      StvPlayerProvider.withApi(StvPlayerApi(http, now: clock), http, clock: clock);

  /// Test seam: a provider over an API whose responses the caller controls.
  factory StvPlayerProvider.withApi(StvPlayerApi api, MediaServerHttpClient http, {DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    final restrictions = StvPlayerRestrictions();
    final mapper = StvPlayerMapper(restrictions, now);
    return StvPlayerProvider._(
      restrictions,
      StvPlayerBrowse(api, mapper, pageSize: _source.listingPageSize),
      StvPlayerCatalog(api, mapper),
      StvPlayerPlayback(http, api, now),
    );
  }

  StvPlayerProvider._(this._restrictions, this._browse, this._catalog, this._playback);

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
  Future<List<ReplayTitle>> search(String query) => _browse.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) => _catalog.title(ref);

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) => _catalog.children(ref);

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) => _playback.resolve(ref);

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async => {
    for (final title in titles) title.ref: ?_restrictions.verdict(title.ref, country),
  };

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      stvPlayerImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isStvPlayerImage(reference);

  @override
  void close() {}
}
