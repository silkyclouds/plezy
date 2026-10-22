import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'dw_api.dart';
import 'dw_catalog.dart';
import 'dw_categories.dart';
import 'dw_ids.dart';
import 'dw_images.dart';
import 'dw_playback.dart';

const _railSize = 12;

/// Deutsche Welle in English: documentaries, news and magazines as clear HLS, free worldwide, no account.
class DwProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: dwSourceId,
    name: 'Deutsche Welle',
    language: 'en',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 30,
  );

  final DwApi _api;
  final DwCatalog _catalog;
  final DateTime Function() _clock;

  DwProvider(MediaServerHttpClient http) : this.withApi(DwApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  DwProvider.withApi(DwApi api, {DateTime Function()? clock})
    : _api = api,
      _clock = clock ?? DateTime.now,
      _catalog = DwCatalog(api, clock: clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => dwCategories;

  @override
  Future<List<ReplayRail>> home() async {
    final programmes = await _catalog.programmes();
    final latest = await _catalog.videos(size: _railSize);
    final rails = [
      ReplayRail(id: dwLatestBrowseId, title: 'Latest videos', titles: latest.titles, moreBrowseId: dwLatestBrowseId),
    ];
    for (final id in dwFlagshipProgrammes) {
      final show = programmes.where((s) => s.ref.nativeId == dwShowId(id)).firstOrNull;
      if (show == null) continue;
      final page = await _catalog.videos(programme: id, size: _railSize);
      rails.add(
        ReplayRail(id: show.ref.nativeId, title: show.title, titles: page.titles, moreBrowseId: show.ref.nativeId),
      );
    }
    rails.add(
      ReplayRail(id: dwProgrammesCategory, title: 'Programmes', titles: programmes, moreBrowseId: replayAllBrowseId),
    );
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId == dwProgrammesCategory) {
      return [ReplayRail(id: dwProgrammesCategory, title: 'Programmes', titles: await _catalog.programmes())];
    }
    if (categoryId == dwLatestBrowseId) {
      final page = await _catalog.videos(size: _source.listingPageSize);
      return [
        ReplayRail(id: dwLatestBrowseId, title: 'Latest videos', titles: page.titles, moreBrowseId: dwLatestBrowseId),
      ];
    }
    return const [];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final size = _source.listingPageSize;
    if (browseId == replayAllBrowseId) {
      final programmes = await _catalog.programmes();
      final from = (page * size).clamp(0, programmes.length);
      final to = (from + size).clamp(from, programmes.length);
      return ReplayPage(titles: programmes.sublist(from, to), totalCount: programmes.length);
    }
    final isLatest = browseId == dwLatestBrowseId;
    final programme = DwId.tryParse(browseId)?.programme;
    if (!isLatest && programme == null) return const ReplayPage(titles: [], totalCount: 0);
    final videos = await _catalog.videos(programme: programme, page: page, size: size);
    return ReplayPage(titles: videos.titles, totalCount: videos.total);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    return trimmed.isEmpty ? const [] : _catalog.search(trimmed);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = DwId.tryParse(ref.nativeId);
    if (id == null) return null;
    if (id.isVideo) return _catalog.video(id.video!);
    if (id.isShow) return _catalog.show(id.programme!);
    final seasons = await _catalog.seasons(id.programme!);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = DwId.tryParse(ref.nativeId);
    if (id == null || id.isVideo) return const [];
    return id.isSeason ? _catalog.episodes(id.programme!, id.year!) : _catalog.seasons(id.programme!);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = DwId.tryParse(ref.nativeId);
    if (id == null || !id.isVideo) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return dwParsePlayback(await _api.graph('content/video/${id.video}'), _clock());
    } on DwRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 451) return const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked);
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => dwImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isDwImage(reference);

  @override
  void close() => _api.clearCache();
}
