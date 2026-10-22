import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'svtplay_api.dart';
import 'svtplay_browse.dart';
import 'svtplay_catalog.dart';
import 'svtplay_images.dart';
import 'svtplay_mapper.dart';
import 'svtplay_playback.dart';
import 'svtplay_restrictions.dart';

/// SVT Play: clear HLS for the worldwide-licensed fifth of the catalogue, Swedish audio and subtitles.
///
/// The catalogue lists everything and flags Sweden-only and copy-protected titles itself, so a viewer abroad
/// sees those greyed out before pressing play. Playback is never attempted for protected titles.
class SvtPlayProvider implements ReplayProvider, ReplayAvailabilityPredictor {
  static const _source = ReplaySource(
    id: svtPlaySourceId,
    name: 'SVT Play',
    language: 'sv',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 24,
  );

  final SvtPlayRestrictions _restrictions;
  final SvtPlayBrowse _browse;
  final SvtPlayCatalog _catalog;
  final SvtPlayPlayback _playback;

  factory SvtPlayProvider(MediaServerHttpClient http, {DateTime Function()? clock}) =>
      SvtPlayProvider.withApi(SvtPlayApi(http, now: clock), clock: clock);

  /// Test seam: a provider over an API whose responses the caller controls.
  factory SvtPlayProvider.withApi(SvtPlayApi api, {DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;
    final restrictions = SvtPlayRestrictions();
    final mapper = SvtPlayMapper(restrictions, now);
    return SvtPlayProvider._(
      restrictions,
      SvtPlayBrowse(api, mapper, pageSize: _source.listingPageSize),
      SvtPlayCatalog(api, mapper, now),
      SvtPlayPlayback(api, now),
    );
  }

  SvtPlayProvider._(this._restrictions, this._browse, this._catalog, this._playback);

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
      ref.nativeId.contains('/') ? _catalog.episodes(ref) : _catalog.seasons(ref.nativeId);

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) {
    if (ref.nativeId.contains('/')) return Future.value(const ReplayPlayback.unavailable(ReplayAvailability.unknown));
    return _playback.resolve(ref.nativeId);
  }

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async => {
    for (final title in titles) title.ref: ?_restrictions.verdict(title.ref, country),
  };

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      svtPlayImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isSvtPlayImage(reference);

  @override
  void close() {}
}
