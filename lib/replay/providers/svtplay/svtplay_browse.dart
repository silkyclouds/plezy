import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'svtplay_api.dart';
import 'svtplay_mapper.dart';
import 'svtplay_queries.dart';

/// Landing page, categories, listings and search of the SVT Play catalogue.
class SvtPlayBrowse {
  final SvtPlayApi _api;
  final SvtPlayMapper _mapper;
  final int pageSize;

  SvtPlayBrowse(this._api, this._mapper, {required this.pageSize});

  Future<List<ReplayCategory>> categories() async {
    final data = await _api.query(svtCategoriesQuery, ttl: SvtPlayApi.wholeCatalogueTtl);
    final categories = (data['mainCategories'] as Map?)?['categories'];
    if (categories is! List) return const [];
    return [
      for (final category in categories.whereType<Map<String, dynamic>>())
        if (category['isMainCategory'] == true)
          ReplayCategory(id: category['id'] as String, title: (category['heading'] as String).trim()),
    ];
  }

  Future<List<ReplayRail>> home() async {
    final data = await _api.query(svtHomeQuery);
    return _mapper.rails((data['startForSvtPlay'] as Map?)?['selections']);
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    final data = await _api.query(svtCategoryQuery, variables: {'id': categoryId});
    final tabs = (data['categoryPage'] as Map?)?['tabs'];
    if (tabs is! List) return const [];
    final recommended = tabs.whereType<Map<String, dynamic>>().where((t) => t['slug'] == 'recommended');
    return recommended.isEmpty ? const [] : _mapper.rails(recommended.first['selections']);
  }

  /// The whole alphabetical catalogue for [replayAllBrowseId], or the "all programmes" tab of one category.
  Future<ReplayPage> listing(String browseId, {int page = 0}) =>
      browseId == replayAllBrowseId ? _wholeCatalogue(page) : _categoryTab(browseId, page);

  Future<List<ReplayTitle>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final data = await _api.query(svtSearchQuery, variables: {'query': text}, ttl: SvtPlayApi.detailsTtl);
    final hits = ((data['searchPage'] as Map?)?['flat'] as Map?)?['hits'];
    return hits is List ? _mapper.titlesOfEntries(hits) : const [];
  }

  /// One call returns every title, so pages are cut here.
  Future<ReplayPage> _wholeCatalogue(int page) async {
    final data = await _api.query(svtAllTitlesQuery, ttl: SvtPlayApi.wholeCatalogueTtl);
    final flat = (data['programAtillO'] as Map?)?['flat'];
    final titles = flat is List ? _mapper.titles(flat) : const <ReplayTitle>[];
    return ReplayPage(titles: titles.skip(page * pageSize).take(pageSize).toList(), totalCount: titles.length);
  }

  Future<ReplayPage> _categoryTab(String categoryId, int page) async {
    final data = await _api.query(
      svtCategoryListingQuery,
      variables: {'id': categoryId, 'limit': pageSize, 'offset': page * pageSize},
    );
    final tabs = (data['categoryPage'] as Map?)?['lazyLoadedTabs'];
    if (tabs is! List) return const ReplayPage(titles: [], totalCount: 0);
    for (final tab in tabs.whereType<Map<String, dynamic>>().where((t) => t['slug'] == 'all')) {
      final selections = tab['selections'];
      final paginated = selections is List && selections.isNotEmpty
          ? (selections.first as Map)['itemsPaginated']
          : null;
      if (paginated is! Map) continue;
      final titles = _mapper.titlesOfEntries(paginated['items'] as List? ?? const []);
      return ReplayPage(titles: titles, totalCount: (paginated['totalSize'] as num?)?.toInt() ?? titles.length);
    }
    return const ReplayPage(titles: [], totalCount: 0);
  }
}
