import 'dart:async';

import '../../../utils/media_server_http_client.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'stvr_api.dart';
import 'stvr_cards.dart';
import 'stvr_catalog.dart';
import 'stvr_categories.dart';
import 'stvr_images.dart';
import 'stvr_mapper.dart';
import 'stvr_playback.dart';
import 'stvr_record.dart';
import 'stvr_refs.dart';
import 'stvr_search.dart';

const _searchMinimumForShows = 3;
const _searchRecordings = 20;
const _homeRecordings = 30;

/// STVR, the Slovak public broadcaster: clear HLS for most of its archive, with the rest replaced by a slate outside
/// Slovakia.
class StvrProvider implements ReplayProvider {
  static const _source = ReplaySource(
    id: stvrSourceId,
    name: 'STVR',
    language: 'sk',
    support: ReplayPlaybackSupport.partial,
    listingPageSize: 20,
  );

  final StvrApi _api;
  final StvrCatalog _catalog;
  final StvrPlaybackResolver _playback;

  StvrProvider(MediaServerHttpClient http) : this.withApi(StvrApi(http));

  /// Test seam: a provider over an API whose responses the caller controls.
  StvrProvider.withApi(StvrApi api, {DateTime Function()? now})
    : _api = api,
      _catalog = StvrCatalog(api, now: now),
      _playback = StvrPlaybackResolver(api);

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => stvrCategories;

  @override
  Future<List<ReplayRail>> home() async {
    final sections = [for (final id in stvrHomeCategoryIds) _api.sectionPage(id, 1)];
    final (latest, pages) = await (_api.archive(size: _homeRecordings), Future.wait(sections)).wait;
    final recordings = StvrRecord.fromPage(latest);
    return [
      ReplayRail(
        id: 'latest',
        title: 'Najnovšie',
        titles: [for (final r in recordings) stvrEpisodeFromRecord(r)],
        moreBrowseId: replayAllBrowseId,
      ),
      for (var i = 0; i < pages.length; i++)
        if (stvrParseCards(pages[i]).shows case final shows when shows.isNotEmpty)
          ReplayRail(
            id: stvrHomeCategoryIds[i],
            title: stvrCategoryById(stvrHomeCategoryIds[i])!.title,
            titles: shows,
            moreBrowseId: stvrHomeCategoryIds[i],
          ),
    ];
  }

  @override
  Future<List<ReplayRail>> category(String categoryId) async {
    final category = stvrCategoryById(categoryId);
    if (category == null) return const [];
    final shows = stvrParseCards(await _api.sectionPage(categoryId, 1)).shows;
    if (shows.isEmpty) return const [];
    return [ReplayRail(id: categoryId, title: category.title, titles: shows, moreBrowseId: categoryId)];
  }

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == replayAllBrowseId) {
      final data = await _api.archive(page: page + 1, size: _source.listingPageSize);
      final titles = [for (final r in StvrRecord.fromPage(data)) stvrEpisodeFromRecord(r)];
      return ReplayPage(titles: titles, totalCount: StvrRecord.totalOf(data));
    }
    if (stvrCategoryById(browseId) == null) return const ReplayPage(titles: [], totalCount: 0);
    final cards = stvrParseCards(await _api.sectionPage(browseId, page + 1));
    return ReplayPage(titles: cards.shows, totalCount: cards.total);
  }

  @override
  Future<List<ReplayTitle>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final withShows = text.length >= _searchMinimumForShows;
    final answers = await Future.wait([
      _api.archive(size: _searchRecordings, query: text),
      if (withShows) _api.siteSearch(text),
    ]);
    final found = StvrRecord.fromPage(answers.first);
    final listed = withShows ? stvrShowsFromSiteSearch(answers.last) : const <ReplayTitle>[];
    final episodes = [for (final r in found) stvrEpisodeFromRecord(r)];
    return [
      ...stvrDistinctShows([...listed, ..._showsOf(found)]),
      ...episodes,
    ];
  }

  @override
  Future<ReplayTitle?> title(ReplayRef ref) {
    final id = ref.nativeId;
    if (stvrParseEpisodeId(id) != null) return _catalog.episode(ref);
    if (stvrParseSeasonId(id) != null) return _seasonTitle(ref);
    if (stvrIsShowId(id)) return _catalog.show(ref);
    return Future.value();
  }

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) {
    final id = ref.nativeId;
    if (stvrParseSeasonId(id) != null) return _catalog.episodes(ref);
    if (stvrIsShowId(id)) return _catalog.seasons(ref);
    return Future.value(const []);
  }

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async {
    final episode = stvrParseEpisodeId(ref.nativeId);
    if (episode == null) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
    try {
      return await _playback.resolve('${episode.programId}');
    } on StvrRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  @override
  String imageUrl(String reference, {int? width, int? height}) => stvrAbsoluteImage(reference) ?? reference;

  @override
  bool ownsImage(String reference) => isStvrImage(reference);

  @override
  void close() {}

  /// One show card per series among [records], in the order the series first appear.
  List<ReplayTitle> _showsOf(List<StvrRecord> records) {
    final seen = <int>{};
    return [
      for (final record in records)
        if (seen.add(record.series)) stvrShowFromRecord(record),
    ];
  }

  Future<ReplayTitle?> _seasonTitle(ReplayRef ref) async {
    final ids = stvrParseSeasonId(ref.nativeId)!;
    final seasons = await _catalog.seasons(stvrShowRef(ids.show));
    return seasons.where((s) => s.ref == ref).firstOrNull;
  }
}
