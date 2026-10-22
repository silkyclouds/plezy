import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'pbs_api.dart';
import 'pbs_catalog.dart';
import 'pbs_categories.dart';
import 'pbs_ids.dart';
import 'pbs_images.dart';
import 'pbs_pages.dart';
import 'pbs_playback.dart';

/// PBS (United States): clear HLS for the part of the catalogue PBS licenses outside the country.
///
/// Whether a given video plays from abroad is only known when it is played, so lists carry no geoblock forecast.
class PbsProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: pbsSourceId,
    name: 'PBS',
    language: 'en',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 60,
  );

  final PbsCatalog _catalog;
  final PbsPlayback _playback;

  PbsProvider(MediaServerHttpClient http) : this.withApi(PbsApi(http));

  /// Test seam: a provider over an API whose pacing and responses the caller controls.
  PbsProvider.withApi(PbsApi api) : _catalog = PbsCatalog(api, PbsPages(api)), _playback = PbsPlayback(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => pbsCategories;

  @override
  Future<List<ReplayRail>> home() => _catalog.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _catalog.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) =>
      _catalog.listing(browseId, page: page, pageSize: _source.listingPageSize);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _catalog.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    switch (PbsId.tryParse(ref.nativeId)) {
      case PbsShowId(:final slug):
        return _catalog.show(slug);
      case final PbsSeasonId id:
        return _catalog.season(id);
      case final PbsVideoId id:
        return _catalog.video(id);
      case null:
        return null;
    }
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    switch (PbsId.tryParse(ref.nativeId)) {
      case PbsShowId(:final slug):
        return _catalog.seasons(slug);
      case final PbsSeasonId id:
        return _catalog.episodes(id);
      case PbsVideoId() || null:
        return const [];
    }
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = PbsId.tryParse(ref.nativeId);
    if (id is! PbsVideoId) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return await _playback.resolve(id.mediaId);
    } on PbsRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => pbsImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isPbsImage(reference);

  @override
  void close() {}
}
