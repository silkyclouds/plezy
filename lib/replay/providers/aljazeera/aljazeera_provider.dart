import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'aljazeera_api.dart';
import 'aljazeera_catalog.dart';
import 'aljazeera_categories.dart';
import 'aljazeera_ids.dart';
import 'aljazeera_images.dart';
import 'aljazeera_mapper.dart';
import 'aljazeera_playback.dart';
import 'aljazeera_search.dart';

/// Al Jazeera English: talk shows, current affairs and documentaries as clear HLS with English captions.
///
/// Programmes have no seasons, so a season is a calendar year. Posts that only exist on YouTube are never listed.
class AljazeeraProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: aljazeeraSourceId,
    name: 'Al Jazeera English',
    language: 'en',
    support: ReplayPlaybackSupport.clear,
    listingPageSize: 24,
  );

  static const _railSize = 10;

  final AljazeeraApi _api;
  final AljazeeraCatalog _catalog;
  final AljazeeraSeenTitles _seen = AljazeeraSeenTitles();

  AljazeeraProvider(MediaServerHttpClient http) : this.withApi(AljazeeraApi(http));

  /// Test seam: a provider over an API whose responses and clock the caller controls.
  AljazeeraProvider.withApi(AljazeeraApi api, {DateTime Function()? clock})
    : _api = api,
      _catalog = AljazeeraCatalog(api, clock: clock);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => aljazeeraCategories;

  @override
  Future<List<ReplayRail>> home() async {
    final latest = [for (final (slug, name) in aljazeeraHomeProgrammes) _programmeRail(slug, name)];
    final rails = await Future.wait([
      ...latest,
      _clipsRail(),
      _showsRail(aljazeeraShowsCategory, 'TV shows'),
      _showsRail(aljazeeraDocumentariesCategory, 'Documentaries'),
    ]);
    return [
      for (final rail in rails)
        if (rail != null && rail.titles.isNotEmpty) rail,
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final rail = switch (categoryId) {
      aljazeeraShowsCategory => await _showsRail(aljazeeraShowsCategory, 'TV shows', limit: null),
      aljazeeraDocumentariesCategory => await _showsRail(aljazeeraDocumentariesCategory, 'Documentaries', limit: null),
      aljazeeraClipsBrowseId => await _clipsRail(),
      _ => null,
    };
    return rail == null || rail.titles.isEmpty ? const [] : [rail];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final size = _source.listingPageSize;
    if (page < 0) return const ReplayPage(titles: [], totalCount: 0);
    if (browseId == replayAllBrowseId) return _slice(await _catalog.allProgrammes(), page, size);
    if (browseId == aljazeeraShowsCategory || browseId == aljazeeraDocumentariesCategory) {
      return _slice(await _catalog.programmes(browseId), page, size);
    }
    if (browseId == aljazeeraClipsBrowseId) {
      return _feedPage(await _catalog.clips(offset: page * size, quantity: size), page * size);
    }
    if (browseId.startsWith(aljazeeraProgrammeBrowsePrefix)) {
      final slug = browseId.substring(aljazeeraProgrammeBrowsePrefix.length);
      return _feedPage(await _catalog.latest(slug, offset: page * size, quantity: size), page * size);
    }
    return const ReplayPage(titles: [], totalCount: 0);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    if (query.trim().isEmpty) return const [];
    final programmes = aljazeeraMatch(await _catalog.allProgrammes(), query);
    return [...programmes, ...aljazeeraMatch(_seen.all, query)];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async {
    final id = AljazeeraId.tryParse(ref.nativeId);
    if (id == null) return null;
    if (id.isClip || id.isEpisode) return _video(id);
    if (id.isSeason) {
      final seasons = await _catalog.seasons(id.programme!);
      return seasons.where((s) => s.ref == id.ref).firstOrNull;
    }
    return _catalog.show(id.programme!);
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async {
    final id = AljazeeraId.tryParse(ref.nativeId);
    if (id == null || id.isClip || id.isEpisode) return const [];
    if (!id.isSeason) return _catalog.seasons(id.programme!);
    final episodes = await _catalog.episodes(id.programme!, id.year!);
    _seen.remember(episodes);
    return episodes;
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final id = AljazeeraId.tryParse(ref.nativeId);
    if (id == null || id.video == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return aljazeeraParsePlayback(await _api.video(id.video!));
    } on AljazeeraRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    } on AljazeeraPolicyKeyRejectedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) =>
      aljazeeraImageUrl(reference, width: width, height: height);

  @override
  bool ownsImage(String reference) => isAljazeeraImage(reference);

  @override
  void close() => _api.clearCache();

  Future<ReplayRail?> _programmeRail(String slug, String name) async {
    final page = await _catalog.latest(slug, quantity: _railSize);
    _seen.remember(page.titles);
    return ReplayRail(id: slug, title: name, titles: page.titles, moreBrowseId: '$aljazeeraProgrammeBrowsePrefix$slug');
  }

  Future<ReplayRail?> _clipsRail() async {
    final page = await _catalog.clips(quantity: _railSize);
    _seen.remember(page.titles);
    return ReplayRail(
      id: aljazeeraClipsBrowseId,
      title: 'Newsfeed',
      titles: page.titles,
      moreBrowseId: aljazeeraClipsBrowseId,
    );
  }

  Future<ReplayRail?> _showsRail(String category, String name, {int? limit = 20}) async {
    final shows = await _catalog.programmes(category);
    return ReplayRail(
      id: category,
      title: name,
      titles: limit == null || shows.length <= limit ? shows : shows.sublist(0, limit),
      moreBrowseId: limit == null ? null : category,
    );
  }

  /// A title opened by id alone has only Brightcove's record to go on. A removed video is no title.
  Future<ReplayTitle?> _video(AljazeeraId id) async {
    final reply = await _api.video(id.video!);
    final body = reply.body;
    if (reply.statusCode != 200 || body is! Map<String, dynamic>) return null;
    final show = id.isEpisode ? await _catalog.show(id.programme!) : null;
    return aljazeeraTitleFromVideo(body, id, showTitle: show?.title);
  }

  ReplayPage _slice(List<ReplayTitle> titles, int page, int size) {
    final from = page * size;
    if (from >= titles.length) return ReplayPage(titles: const [], totalCount: titles.length);
    final to = from + size < titles.length ? from + size : titles.length;
    return ReplayPage(titles: titles.sublist(from, to), totalCount: titles.length);
  }

  /// The site gives no total for a feed, so a full page claims one more title than is shown to keep paging going.
  ReplayPage _feedPage(({List<ReplayTitle> titles, bool more}) page, int start) {
    _seen.remember(page.titles);
    return ReplayPage(titles: page.titles, totalCount: start + page.titles.length + (page.more ? 1 : 0));
  }
}
