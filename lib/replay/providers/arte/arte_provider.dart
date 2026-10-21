import '../../../exceptions/media_server_exceptions.dart';
import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'arte_api.dart';
import 'arte_catalog.dart';
import 'arte_categories.dart';
import 'arte_images.dart';
import 'arte_mapper.dart';
import 'arte_playback.dart';

/// ARTE: clear HLS for most of the catalogue, with French, German and original-language versions.
class ArteProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: arteSourceId,
    name: 'ARTE',
    language: 'fr',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 12,
  );

  final ArteApi _api;
  final ArteCatalog _catalog;

  ArteProvider(MediaServerHttpClient http, {String language = 'fr'}) : this._(ArteApi(http, language: language));

  ArteProvider._(this._api) : _catalog = ArteCatalog(_api);

  /// Test seam: a provider over an API whose responses the caller controls.
  ArteProvider.withApi(ArteApi api) : this._(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => arteCategories;

  @override
  Future<List<ReplayRail>> home() async => arteRailsFromPage(await _api.emac('pages/HOME/'));

  @override
  Future<List<ReplayRail>> category(String categoryId) async => arteRailsFromPage(await _api.emac('pages/$categoryId'));

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final code = browseId == replayAllBrowseId ? arteSeriesListing : browseId;
    final first = await _api.emac('pages/$code');
    final zone = _listingZone(first, code);
    if (zone == null) return const ReplayPage(titles: [], totalCount: 0);

    final content = zone['content'] as Map<String, dynamic>;
    final pagination = content['pagination'] as Map<String, dynamic>?;
    final total = (pagination?['totalCount'] as num?)?.toInt() ?? (content['data'] as List).length;
    if (page == 0) return ReplayPage(titles: arteTitlesFromZone(zone), totalCount: total);

    final pages = (pagination?['pages'] as num?)?.toInt() ?? 1;
    final firstLink = (pagination?['links'] as Map?)?['first'] as String?;
    if (firstLink == null || page >= pages) return ReplayPage(titles: const [], totalCount: total);
    final body = await _api.link(firstLink.replaceFirst(RegExp(r'page=\d+'), 'page=${page + 1}'));
    return ReplayPage(titles: arteTitlesFromZone({'content': body}), totalCount: total);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final page = await _api.emac('pages/SEARCH', query: {'query': trimmed});
    final zones = page['zones'];
    if (zones is! List) return const [];
    final zone = zones.whereType<Map<String, dynamic>>().where((z) => z['code'] == 'listing_SEARCH').firstOrNull;
    return zone == null ? const [] : arteTitlesFromZone(zone);
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = ref.nativeId;
    if (id.contains('/')) return _seasonTitle(ref);
    if (id.startsWith('RC-')) return _catalog.show(id);
    final page = await _api.emac('programs/$id');
    return _programTitle(page, ref);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) {
    final id = ref.nativeId;
    if (id.contains('/')) return _catalog.episodes(ref);
    if (id.startsWith('RC-')) return _catalog.seasons(id);
    return Future.value(const []);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    if (ref.nativeId.startsWith('RC-')) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return arteParsePlayback(await _api.playerConfig(ref.nativeId));
    } on ReplayRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => arteImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isArteImage(reference);

  @override
  void close() {}

  Map<String, dynamic>? _listingZone(Map<String, dynamic> page, String code) {
    final zones = page['zones'];
    if (zones is! List) return null;
    final maps = zones.whereType<Map<String, dynamic>>().toList();
    for (final prefix in ['videos_subcategory_$code', 'videos_']) {
      final hit = maps.where((z) => (z['code'] as String? ?? '').startsWith(prefix)).firstOrNull;
      if (hit != null) return hit;
    }
    return maps.where((z) => ((z['content'] as Map?)?['data'] as List? ?? const []).isNotEmpty).firstOrNull;
  }

  Future<ReplayTitle?> _seasonTitle(ReplayRef ref) async {
    final seasons = await _catalog.seasons(ref.nativeId.split('/').first);
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }

  Future<ReplayTitle?> _programTitle(Map<String, dynamic> page, ReplayRef ref) async {
    final zones = page['zones'];
    if (zones is! List) return null;
    final zone = zones
        .whereType<Map<String, dynamic>>()
        .where((z) => (z['code'] as String? ?? '').startsWith('program_content_'))
        .firstOrNull;
    final data = (zone?['content'] as Map?)?['data'];
    if (data is! List || data.isEmpty) return null;
    final item = data.first as Map<String, dynamic>;
    return arteTitleFromItem(item, context: _parents(item));
  }

  ArteContext _parents(Map<String, dynamic> item) {
    final parents = item['parentCollections'];
    if (parents is! List) return ArteContext.none;
    String? seriesId;
    String? seasonId;
    for (final p in parents.whereType<Map<String, dynamic>>()) {
      if (p['catalogType'] == 'SERIES') seriesId = p['programId'] as String?;
      if (p['catalogType'] == 'SEASON') seasonId = p['programId'] as String?;
    }
    if (seriesId == null) return ArteContext.none;
    return ArteContext(show: arteRef(seriesId), season: seasonId == null ? null : arteRef('$seriesId/$seasonId'));
  }
}
