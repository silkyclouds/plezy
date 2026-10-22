import 'dart:collection';

import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_api.dart';
import 'nrktv_plugs.dart';

/// Page id of the landing page.
const nrkFrontPage = 'frontpage';

/// The category pages and their rows.
///
/// Category pages weigh up to 1.4 MB, so what is kept is the rows made from them, for a few minutes.
class NrkBrowse {
  static const _keep = Duration(minutes: 10);
  static const _maxPages = 12;

  final NrkApi _api;
  final DateTime Function() _now;
  final LinkedHashMap<String, ({DateTime at, Future<List<ReplayRail>> rails})> _pages = LinkedHashMap();

  NrkBrowse(this._api, this._now);

  Future<List<ReplayCategory>> categories() async {
    final list = await _api.pageList();
    return [
      for (final item in (list['pageListItems'] as List? ?? const []).whereType<Map>())
        if (item['pageType'] == 'category' && item['id'] is String && item['title'] is String)
          ReplayCategory(id: item['id'] as String, title: item['title'] as String),
    ];
  }

  Future<List<ReplayRail>> rails(String pageId) {
    final cached = _pages[pageId];
    if (cached != null && _now().difference(cached.at) < _keep) return cached.rails;
    final rails = _load(pageId);
    _pages.remove(pageId);
    _pages[pageId] = (at: _now(), rails: rails);
    if (_pages.length > _maxPages) _pages.remove(_pages.keys.first);
    return rails;
  }

  /// Every distinct title of a page, in the order of its rows, as one flat list.
  Future<ReplayPage> flat(String pageId, int page, int size) async {
    final seen = <ReplayRef>{};
    final titles = [
      for (final rail in await rails(pageId))
        for (final title in rail.titles)
          if (seen.add(title.ref)) title,
    ];
    final start = page * size;
    final slice = start >= titles.length ? const <ReplayTitle>[] : titles.skip(start).take(size).toList();
    return ReplayPage(titles: slice, totalCount: titles.length);
  }

  Future<List<ReplayRail>> _load(String pageId) async {
    try {
      return nrkRailsFromPage(await _api.page(pageId));
    } on Object {
      _pages.remove(pageId);
      rethrow;
    }
  }
}
