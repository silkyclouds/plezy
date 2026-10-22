import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'nhkworld_api.dart';
import 'nhkworld_catalog.dart';
import 'nhkworld_ids.dart';
import 'nhkworld_images.dart';
import 'nhkworld_mapper.dart';
import 'nhkworld_playback.dart';

/// NHK WORLD-JAPAN on demand: English programmes about Japan as clear HLS, no account, no DRM.
///
/// The API has no search, so [search] filters the cached list of programmes.
class NhkWorldProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: nhkWorldSourceId,
    name: 'NHK WORLD-JAPAN',
    language: 'en',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 24,
  );

  static const _railSize = '15';
  static const _categoryRailPrograms = 24;

  final NhkWorldApi _api;
  final NhkWorldCatalog _catalog;
  final DateTime Function() _clock;

  NhkWorldProvider(MediaServerHttpClient http, {String language = 'en'})
    : this.withApi(NhkWorldApi(http, language: language));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  NhkWorldProvider.withApi(NhkWorldApi api, {DateTime Function()? clock})
    : _api = api,
      _clock = clock ?? DateTime.now,
      _catalog = NhkWorldCatalog(api, clock: clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => nhkCategories(await _api.json('categories/'));

  @override
  Future<List<ReplayRail>> home() async {
    final lists = await Future.wait([
      _api.items('video_episodes', query: {'limit': _railSize}),
      _api.items('video_episodes', query: {'limit': '10', 'sort': 'trending'}),
      _api.items('video_clips', query: {'limit': '12'}),
    ]);
    final rails = [
      ReplayRail(id: 'latest', title: 'Latest episodes', titles: _titles(lists[0])),
      ReplayRail(id: 'trending', title: 'Trending', titles: _titles(lists[1])),
      ReplayRail(id: 'clips', title: 'Clips', titles: _titles(lists[2])),
    ];
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final programmes = await _catalog.programmes(categoryId: categoryId);
    final episodes = await _categoryEpisodes(categoryId);
    final rails = [
      ReplayRail(
        id: 'programmes',
        title: 'Programmes',
        titles: programmes.take(_categoryRailPrograms).toList(),
        moreBrowseId: programmes.length > _categoryRailPrograms ? categoryId : null,
      ),
      ReplayRail(id: 'latest', title: 'Latest episodes', titles: _titles(episodes)),
    ];
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final all = await _catalog.programmes(categoryId: browseId == replayAllBrowseId ? null : browseId);
    final size = _source.listingPageSize;
    return ReplayPage(titles: all.skip(page * size).take(size).toList(), totalCount: all.length);
  }

  @override
  Future<List<ReplayTitle>> search(String query) => _catalog.search(query);

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final target = parseNhkNativeId(ref.nativeId);
    if (target == null) return null;
    return switch (target.kind) {
      NhkTargetKind.show => _catalog.show(target.id),
      NhkTargetKind.season => _season(ref, target.id),
      NhkTargetKind.episode => _catalog.episode(target.id),
      NhkTargetKind.clip => _catalog.clip(target.id),
    };
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final target = parseNhkNativeId(ref.nativeId);
    return switch (target?.kind) {
      NhkTargetKind.show => _catalog.seasons(target!.id),
      NhkTargetKind.season => _catalog.episodes(ref),
      _ => const [],
    };
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final target = parseNhkNativeId(ref.nativeId);
    if (target == null || (target.kind != NhkTargetKind.episode && target.kind != NhkTargetKind.clip)) {
      return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    }
    try {
      final item = await _api.item(clip: target.kind == NhkTargetKind.clip, id: target.id);
      return nhkParsePlayback(item, _clock());
    } on NhkWorldRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => nhkWorldImageUrl(reference);

  @override
  bool ownsImage(String reference) => isNhkWorldImage(reference);

  @override
  void close() {}

  List<ReplayTitle> _titles(List<Map<String, dynamic>> items) {
    final now = _clock();
    return [for (final item in items) nhkEpisodeTitle(item, now: now)];
  }

  Future<List<Map<String, dynamic>>> _categoryEpisodes(String categoryId) async {
    try {
      return await _api.items('categories/$categoryId/video_episodes', query: {'limit': '12'});
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<ReplayTitle?> _season(ReplayRef ref, String programId) async {
    final seasons = await _catalog.seasons(programId);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }
}
