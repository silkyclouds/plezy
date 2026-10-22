import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtveplay_api.dart';
import 'rtveplay_browse.dart';
import 'rtveplay_catalog.dart';
import 'rtveplay_categories.dart';
import 'rtveplay_ids.dart';
import 'rtveplay_images.dart';
import 'rtveplay_resolver.dart';
import 'rtveplay_search.dart';

/// RTVE Play (Spain): clear HLS for most of the free catalogue. Licensed series and sport are limited to Spain or to
/// signed-in viewers and are refused at play time.
class RtvePlayProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: rtveSourceId,
    name: 'RTVE Play',
    language: 'es',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 50,
  );

  final RtveCatalog _catalog;
  final RtveBrowse _browse;
  final RtveSearch _search;
  final RtvePlaybackResolver _resolver;

  RtvePlayProvider(MediaServerHttpClient http) : this.withApi(RtvePlayApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  RtvePlayProvider.withApi(RtvePlayApi api, {DateTime Function()? now}) : this._(api, now ?? _utcNow);

  RtvePlayProvider._(RtvePlayApi api, DateTime Function() now) : this._assembled(api, now, RtveCatalog(api, now));

  RtvePlayProvider._assembled(RtvePlayApi api, DateTime Function() now, this._catalog)
    : _browse = RtveBrowse(api, now, pageSize: _source.listingPageSize),
      _search = RtveSearch(api, now),
      _resolver = RtvePlaybackResolver(api, _catalog);

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => rtveCategories;

  @override
  Future<List<ReplayRail>> home() => _browse.home();

  @override
  Future<List<ReplayRail>> category(String categoryId) => _browse.category(categoryId);

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) => _browse.listing(browseId, page);

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _search.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async => switch (parseRtveRef(ref)) {
    RtveShowTarget(:final programId) => _catalog.show(programId),
    final RtveSeasonTarget season => _season(season),
    RtveVideoTarget(:final videoId) => _catalog.video(videoId),
    null => null,
  };

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async => switch (parseRtveRef(ref)) {
    RtveShowTarget(:final programId) => _catalog.seasons(programId),
    final RtveSeasonTarget season => _catalog.episodes(season),
    _ => const [],
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = parseRtveRef(ref);
    if (target is! RtveVideoTarget) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return await _resolver.resolve(target.videoId);
    } on RtvePlayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => rtveImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isRtveImage(reference);

  @override
  void close() {}

  Future<ReplayTitle?> _season(RtveSeasonTarget target) async {
    final seasons = await _catalog.seasons(target.programId);
    final ref = rtveSeasonRef(target.programId, target.seasonId);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }
}
