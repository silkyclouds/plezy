import '../../model/replay_title.dart';
import 'francetv_api.dart';
import 'francetv_categories.dart';
import 'francetv_mapper.dart';

/// Titles per page of the programme listing, fixed by the broadcaster.
const franceTvListingPageSize = 20;

const _maxPagesPerCategory = 80;

/// Flat paging over the programmes of one category, or of every category one after the other.
///
/// The endpoint has no total and no cursor: pages of twenty come until one is short or empty. A page of the
/// whole catalogue is therefore found by counting from the start; the pages already read are cached by the API layer.
class FranceTvListing {
  final FranceTvApi _api;
  final FranceTvMapper _mapper;

  FranceTvListing(this._api, this._mapper);

  /// [categoryIds] are walked in order. [page] is zero-based.
  Future<ReplayPage> page(List<String> categoryIds, int page) async {
    final start = page * franceTvListingPageSize;
    final end = start + franceTvListingPageSize;
    final wanted = <Map<String, dynamic>>[];
    var position = 0;

    for (final id in categoryIds) {
      if (!isFranceTvCategory(id)) continue;
      for (var index = 0; index < _maxPagesPerCategory; index++) {
        final items = await _programmes(id, index);
        for (final item in items) {
          if (position >= start && position < end) wanted.add(item);
          position++;
        }
        if (position >= end) return _result(wanted, end + franceTvListingPageSize);
        if (items.length < franceTvListingPageSize) break;
      }
    }
    return _result(wanted, position);
  }

  ReplayPage _result(List<Map<String, dynamic>> items, int total) =>
      ReplayPage(titles: _mapper.titles(items), totalCount: total);

  Future<List<Map<String, dynamic>>> _programmes(String categoryId, int index) async {
    final body = await _api.mobile('apps/regions/$categoryId/programs', query: {'page': '$index'});
    return (body['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
  }
}
