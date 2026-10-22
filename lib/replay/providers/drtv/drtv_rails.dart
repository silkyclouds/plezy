import '../../model/replay_title.dart';
import 'drtv_api.dart';
import 'drtv_mapper.dart';

/// Builds the rows of a DR page.
///
/// DR sends the cards of only the first few lists with the page; the others arrive empty and are fetched by id. A page
/// has dozens of lists, so only a few are filled and the rest are left out.
class DrtvRails {
  static const _filledPerPage = 4;
  static const _fallbackTitle = 'Udvalgt';
  static const _railPageSize = 24;

  final DrtvApi _api;
  final DrtvMapper _mapper;

  DrtvRails(this._api, this._mapper);

  /// Browse id of a list, as passed back to `listing`.
  static String browseIdOf(String listId) => 'list:$listId';

  static String? listIdOf(String browseId) => browseId.startsWith('list:') ? browseId.substring(5) : null;

  Future<List<ReplayRail>> fromPage(DrtvJson? page) async {
    final entries = page?['entries'];
    if (entries is! List) return const [];
    final rails = <ReplayRail>[];
    var filled = 0;
    var usedFallback = false;

    for (final entry in entries.whereType<DrtvJson>()) {
      final list = entry['list'];
      if (entry['type'] != 'ListEntry' || list is! DrtvJson) continue;
      final id = '${list['id'] ?? ''}';
      if (id.isEmpty) continue;
      final heading = (entry['title'] as String? ?? '').trim();

      var items = list['items'] as List? ?? const [];
      var paging = list['paging'];
      if (items.isEmpty && heading.isNotEmpty && filled < _filledPerPage) {
        filled++;
        final loaded = await _api.list(id, pageSize: _railPageSize);
        items = loaded?['items'] as List? ?? const [];
        paging = loaded?['paging'] ?? paging;
      }
      final titles = _mapper.titles(items);
      if (titles.isEmpty || (heading.isEmpty && usedFallback)) continue;
      if (heading.isEmpty) usedFallback = true;

      rails.add(
        ReplayRail(
          id: id,
          title: heading.isEmpty ? _fallbackTitle : heading,
          titles: titles,
          moreBrowseId: hasMore(paging) ? browseIdOf(id) : null,
        ),
      );
    }
    return rails;
  }

  /// Whether a list continues past the page just read.
  static bool hasMore(Object? paging) {
    final next = paging is Map<String, dynamic> ? paging['next'] : null;
    return next is String && next.isNotEmpty;
  }
}
