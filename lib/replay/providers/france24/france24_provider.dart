import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'france24_api.dart';
import 'france24_catalog.dart';
import 'france24_categories.dart';
import 'france24_ids.dart';
import 'france24_images.dart';
import 'france24_mapper.dart';
import 'france24_playback.dart';
import 'france24_search.dart';

/// France 24 (French edition): news, debates and magazines as progressive MP4 files, no account, no DRM.
class France24Provider implements ReplayProvider {
  static const _source = ReplaySource(
    id: france24SourceId,
    name: 'France 24',
    language: 'fr',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 24,
  );

  final France24Api _api;
  final France24Catalog _catalog;
  final DateTime Function() _clock;

  France24Provider(MediaServerHttpClient http) : this.withApi(France24Api(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  France24Provider.withApi(France24Api api, {DateTime Function()? clock})
    : _api = api,
      _clock = clock ?? DateTime.now,
      _catalog = France24Catalog(api, clock: clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => france24Categories;

  @override
  Future<List<ReplayRail>> home() async {
    final videos = await _api.videos();
    final latest = await _api.latestEditions();
    final programmes = await _api.programmes();
    final rails = [
      ReplayRail(
        id: 'videos',
        title: 'Dernières vidéos',
        titles: france24Clips(videos.items, _clock()),
        moreBrowseId: france24VideosBrowseId,
      ),
      ReplayRail(id: 'latest', title: 'Dernières éditions', titles: france24Episodes(latest.items, _clock())),
      ReplayRail(
        id: 'programmes',
        title: 'Toutes les émissions',
        titles: [for (final p in programmes.items) france24Show(p)],
        moreBrowseId: replayAllBrowseId,
      ),
    ];
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId == france24ProgrammesCategory) {
      final programmes = await _catalog.allProgrammes();
      return [
        ReplayRail(
          id: 'programmes',
          title: 'Toutes les émissions',
          titles: [for (final p in programmes) france24Show(p)],
        ),
      ];
    }
    if (categoryId == france24VideosBrowseId) {
      final page = await _api.videos();
      return [
        ReplayRail(
          id: 'videos',
          title: 'Dernières vidéos',
          titles: france24Clips(page.items, _clock()),
          moreBrowseId: france24VideosBrowseId,
        ),
      ];
    }
    return const [];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == replayAllBrowseId) {
      final programmes = await _api.programmes(page: page + 1);
      return ReplayPage(titles: [for (final p in programmes.items) france24Show(p)], totalCount: programmes.total);
    }
    if (browseId == france24VideosBrowseId) {
      final videos = await _api.videos(page: page + 1);
      return ReplayPage(titles: france24Clips(videos.items, _clock()), totalCount: videos.total);
    }
    return const ReplayPage(titles: [], totalCount: 0);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final programmes = france24MatchProgrammes(await _catalog.allProgrammes(), query);
    return [for (final p in programmes) france24Show(p)];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = France24Id.tryParse(ref.nativeId);
    if (id == null) return null;
    if (id.isClip) return _catalog.clip(id.clip!);
    if (id.isShow) return _catalog.show(id.programme!);
    if (id.isSeason) return _season(id);
    final edition = await _catalog.edition(id.programme!, id.edition!);
    return edition == null ? null : france24Episode(edition, _clock());
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = France24Id.tryParse(ref.nativeId);
    if (id == null || id.isEpisode || id.isClip) return const [];
    return id.isSeason ? _catalog.episodes(id.programme!, id.year!) : _catalog.seasons(id.programme!);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = France24Id.tryParse(ref.nativeId);
    if (id == null || !(id.isClip || id.isEpisode)) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      final video = id.isClip
          ? await _catalog.clipVideo(id.clip!)
          : (await _catalog.edition(id.programme!, id.edition!))?.video;
      return france24Playback(video, _clock());
    } on France24RateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on France24TokenRejectedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      france24ImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isFrance24Image(reference);

  @override
  void close() => _api.clearCache();

  Future<ReplayTitle?> _season(France24Id id) async {
    final seasons = await _catalog.seasons(id.programme!);
    return seasons.where((s) => s.ref == id.ref).firstOrNull;
  }
}
