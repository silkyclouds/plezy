import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtsplay_api.dart';
import 'rtsplay_catalog.dart';
import 'rtsplay_ids.dart';
import 'rtsplay_images.dart';
import 'rtsplay_mapper.dart';
import 'rtsplay_playback.dart';
import 'rtsplay_shows.dart';

/// RTS Play (Swiss public television): clear HLS for the part of the catalogue licensed outside Switzerland.
class RtsPlayProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: rtsPlaySourceId,
    name: 'RTS Play',
    language: 'fr',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 100,
  );

  final RtsPlayApi _api;
  final RtsPlayCatalog _catalog;
  final RtsPlayShows _shows;

  RtsPlayProvider(MediaServerHttpClient http) : this.withApi(RtsPlayApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  RtsPlayProvider.withApi(RtsPlayApi api) : _api = api, _catalog = RtsPlayCatalog(api), _shows = RtsPlayShows(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() => _catalog.categories();

  @override
  Future<List<ReplayRail>> home() => _catalog.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _catalog.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _catalog.listing(browseId, page: page);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _catalog.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    switch (RtsId.tryParse(ref.nativeId)) {
      case RtsShowId(:final showId):
        return _shows.show(showId);
      case final RtsSeasonId id:
        return (await _shows.seasons(id.showId)).where((s) => s.ref == ref).firstOrNull;
      case RtsVideoId(:final videoId):
        final composition = await _api.mediaComposition(videoId);
        return composition == null ? null : rtsTitleFromComposition(composition);
      case null:
        return null;
    }
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    return switch (RtsId.tryParse(ref.nativeId)) {
      RtsShowId(:final showId) => _shows.seasons(showId),
      final RtsSeasonId id => _shows.episodes(id),
      _ => const [],
    };
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = RtsId.tryParse(ref.nativeId);
    if (id is! RtsVideoId) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final composition = await _api.mediaComposition(id.videoId);
      if (composition == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      return rtsParsePlayback(composition);
    } on RtsPlayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      rtsPlayImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isRtsPlayImage(reference);

  @override
  void close() {}
}
