import 'dart:async';

import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ruv_api.dart';
import 'ruv_films.dart';
import 'ruv_mapper.dart';
import 'ruv_queries.dart';
import 'ruv_scope.dart';

const _station = 'tv';

/// Landing rows, categories, flat listings and search.
class RuvBrowse {
  /// Panels fetched for the landing page. The site has about 35; the first dozen are the editorial front.
  static const _homePanels = 12;
  static const _railLength = 30;
  static const _maxSearchHits = 24;

  final RuvApi _api;
  final RuvScopes _scopes;
  final RuvFilmCheck _films;
  final DateTime Function() _now;
  final int pageSize;

  Future<List<ReplayTitle>>? _everything;
  DateTime? _everythingAt;

  RuvBrowse(this._api, this._scopes, this._films, this._now, {required this.pageSize});

  Future<List<ReplayCategory>> categories() async {
    final data = await _api.query(ruvCategoriesQuery, variables: {'s': _station}, ttl: RuvApi.wholeCatalogueTtl);
    return [
      for (final c in _categoryRows(data))
        if (c['slug'] is String && c['title'] is String)
          ReplayCategory(id: c['slug'] as String, title: c['title'] as String),
    ];
  }

  Future<List<ReplayRail>> home() async {
    final data = await _api.query(ruvPanelsQuery, variables: {'t': _station, 'l': _homePanels});
    final panels = (data['Featured'] as Map?)?['panels'];
    if (panels is! List) return const [];
    final rails = <ReplayRail>[];
    for (final panel in panels.whereType<Map<String, dynamic>>()) {
      final titles = await _titles(_programs(panel));
      if (titles.isEmpty) continue;
      rails.add(ReplayRail(id: panel['slug'] as String, title: (panel['title'] as String?) ?? '', titles: titles));
    }
    return rails;
  }

  /// One row with the start of the category and a way to open the rest.
  Future<List<ReplayRail>> category(String slug) async {
    final titles = await _category(slug);
    if (titles.isEmpty) return const [];
    final name = (await categories()).where((c) => c.id == slug).firstOrNull?.title ?? slug;
    return [
      ReplayRail(
        id: slug,
        title: name,
        titles: titles.take(_railLength).toList(),
        moreBrowseId: titles.length > _railLength ? slug : null,
      ),
    ];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final titles = browseId == replayAllBrowseId ? await _wholeCatalogue() : await _category(browseId);
    final start = page * pageSize;
    if (start >= titles.length) return ReplayPage(titles: const [], totalCount: titles.length);
    final end = start + pageSize > titles.length ? titles.length : start + pageSize;
    return ReplayPage(titles: titles.sublist(start, end), totalCount: titles.length);
  }

  /// Programmes with a hit in their episodes, in the order of the hits. The search returns episodes, so each
  /// programme is looked up once for its card.
  Future<List<ReplayTitle>> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final data = await _api.query(ruvSearchQuery, variables: {'t': _station, 'x': text}, ttl: RuvApi.detailsTtl);
    final hits = data['Search'];
    if (hits is! List) return const [];
    final ids = <int>{
      for (final hit in hits.whereType<Map<String, dynamic>>()) ?int.tryParse('${hit['id']}'),
    }.take(_maxSearchHits).toList();
    if (ids.isEmpty) return const [];
    final cards = await _api.query(ruvCardsBatchQuery(ids), ttl: RuvApi.detailsTtl);
    final programs = ruvBatchResults(cards, ids.length).whereType<Map<String, dynamic>>().toList();
    _scopes.noteAll(programs);
    return ruvTitlesFromPrograms(programs, now: _now());
  }

  Future<List<ReplayTitle>> _category(String slug) async {
    final data = await _api.query(ruvCategoryQuery, variables: {'s': _station, 'c': slug});
    final row = _categoryRows(data).where((c) => c['slug'] == slug).firstOrNull;
    return _titles(row == null ? const [] : _programs(row));
  }

  Future<List<ReplayTitle>> _titles(List<Map<String, dynamic>> listed) async {
    _scopes.noteAll(listed);
    return ruvTitlesFromPrograms(await _films.settle(listed), now: _now());
  }

  /// Every programme of every category once, by title. RÚV has no single "all programmes" query.
  Future<List<ReplayTitle>> _wholeCatalogue() {
    final held = _everything;
    final at = _everythingAt;
    if (held != null && at != null && _now().difference(at) < RuvApi.wholeCatalogueTtl) return held;
    final load = _loadEverything();
    _everything = load;
    _everythingAt = _now();
    // A failed load must not be kept for hours; the caller still gets the error from [load].
    unawaited(
      load.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_everything, load)) _everything = null;
        },
      ),
    );
    return load;
  }

  Future<List<ReplayTitle>> _loadEverything() async {
    final lists = await Future.wait([for (final c in await categories()) _category(c.id)]);
    final seen = <ReplayRef>{};
    final titles = [
      for (final list in lists)
        for (final title in list)
          if (seen.add(title.ref)) title,
    ];
    titles.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return titles;
  }

  List<Map<String, dynamic>> _categoryRows(Map<String, dynamic> data) {
    final rows = (data['Category'] as Map?)?['categories'];
    return rows is List ? rows.whereType<Map<String, dynamic>>().toList() : const [];
  }

  List<Map<String, dynamic>> _programs(Map<String, dynamic> holder) {
    final programs = holder['programs'];
    return programs is List ? programs.whereType<Map<String, dynamic>>().toList() : const [];
  }
}
