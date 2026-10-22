import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'tvpvod_api.dart';
import 'tvpvod_categories.dart';
import 'tvpvod_mapper.dart';
import 'tvpvod_rails.dart';

/// Titles per page of a flat listing; the site allows up to 100.
const tvpPageSize = 24;

const _railItems = '12';

/// The landing page, category pages, flat listings and search.
class TvpBrowse {
  final TvpVodApi _api;

  TvpBrowse(this._api);

  Future<List<ReplayRail>> home() async =>
      tvpRailsFromSections(await _api.products('sections/main', query: {'elementsLimit': _railItems}));

  /// The curated rows of a category, then its newest titles. Categories the site gives no rows for get the newest
  /// titles by arrival and by production year instead.
  Future<List<ReplayRail>> category(String categoryId) async {
    final rails = <ReplayRail>[...await _curatedRows(categoryId)];
    rails.add(await _listingRail(TvpListing(categoryId: categoryId)));
    if (rails.length == 1) rails.add(await _listingRail(TvpListing(categoryId: categoryId, sort: TvpSort.year)));
    return [
      for (final rail in rails)
        if (rail.titles.isNotEmpty) rail,
    ];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final target = TvpListing.parse(browseId);
    final response = await _api.products(
      'vods',
      query: {
        'firstResult': '${page * tvpPageSize}',
        'maxResults': '$tvpPageSize',
        'sort': target.sort.field,
        'order': target.sort.order,
        if (target.categoryId != null) 'mainCategoryId[]': [target.categoryId!],
      },
    );
    if (response is! Map<String, dynamic>) return const ReplayPage(titles: [], totalCount: 0);
    final items = response['items'] as List? ?? const [];
    final total = ((response['meta'] as Map?)?['totalCount'] as num?)?.toInt() ?? items.length;
    return ReplayPage(titles: tvpTitlesFromItems(items), totalCount: total);
  }

  Future<List<ReplayTitle>> search(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    final response = await _api.products('vods/search/VOD_SERIAL', query: {'keyword': keyword, 'maxResults': '50'});
    return response is Map<String, dynamic> ? tvpTitlesFromItems(response['items'] as List? ?? const []) : const [];
  }

  Future<List<ReplayRail>> _curatedRows(String categoryId) async {
    final slug = tvpCategorySlug(categoryId);
    if (slug == null) return const [];
    try {
      return tvpRailsFromSections(await _api.products('sections/$slug', query: {'elementsLimit': _railItems}));
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<ReplayRail> _listingRail(TvpListing listing) async {
    final page = await this.listing(listing.browseId);
    return ReplayRail(
      id: listing.browseId,
      title: listing.sort.label,
      titles: page.titles,
      moreBrowseId: listing.browseId,
    );
  }
}
