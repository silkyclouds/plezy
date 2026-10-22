import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'ceskatelevize_api.dart';
import 'ceskatelevize_mapper.dart';
import 'ceskatelevize_queries.dart';
import 'ceskatelevize_text.dart';

/// The catalogue's own id for "every programme", used by the whole-catalogue listing.
const ceskatelevizeEveryProgramme = '0';

const _popular = 'popular_previous_seven_days';

/// Landing page, category pages and flat listings.
///
/// A browse id is `cat:<categoryId>` or `cat:<categoryId>:<orderBy>`; a bare category id is accepted too.
class CeskaTelevizeBrowse {
  static const _railSize = 20;
  static const _pageSize = 100;

  final CeskaTelevizeApi _api;
  final CeskaTelevizeMapper _mapper;

  CeskaTelevizeBrowse(this._api, this._mapper);

  Future<List<ReplayRail>> home() async {
    final data = await _api.query(ceskatelevizeHomeQuery);
    final rows = (data['homepage'] as Map?)?['rows'];
    if (rows is! List) return const [];
    final rails = <ReplayRail>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if (row['disabled'] == true) continue;
      final items = ((row['assets'] as Map?)?['items'] as List? ?? const []).whereType<Map<String, dynamic>>();
      final titles = _dedupe([
        for (final item in items) item.containsKey('idec') ? _mapper.episode(item) : _mapper.programme(item),
      ]);
      final title = ceskatelevizeLabel(row['title']);
      if (titles.isEmpty || title == null) continue;
      rails.add(ReplayRail(id: '${row['slug'] ?? row['id']}', title: title, titles: titles));
    }
    return rails;
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    final data = await _api.query(ceskatelevizeCategoryBlocksQuery(categoryId));
    final blocks = ((data['category'] as Map?)?['categoryBlocks'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final rails = await Future.wait([for (final block in blocks) _blockRail(categoryId, block)]);
    return [for (final rail in rails) ?rail];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    final target = browseId == replayAllBrowseId
        ? (id: ceskatelevizeEveryProgramme, orderBy: _popular)
        : _parse(browseId);
    if (target == null) return const ReplayPage(titles: [], totalCount: 0);
    final found = await _programmes(target.id, target.orderBy, limit: _pageSize, offset: page * _pageSize);
    return ReplayPage(titles: found.titles, totalCount: found.total);
  }

  Future<ReplayRail?> _blockRail(String parentId, Map<String, dynamic> block) async {
    final id = block['categoryId'] as String? ?? parentId;
    final orderBy = block['orderBy'] as String? ?? _popular;
    final title = ceskatelevizeLabel(block['title']);
    if (title == null) return null;
    final found = await _programmes(id, orderBy, limit: _railSize, offset: 0);
    if (found.titles.isEmpty) return null;
    final browseId = 'cat:$id:$orderBy';
    return ReplayRail(
      id: browseId,
      title: title,
      titles: found.titles,
      moreBrowseId: block['hasMoreItems'] == true ? browseId : null,
    );
  }

  Future<({List<ReplayTitle> titles, int total})> _programmes(
    String categoryId,
    String orderBy, {
    required int limit,
    required int offset,
  }) async {
    final query = ceskatelevizeProgrammesQuery(categoryId, limit: limit, offset: offset, orderBy: orderBy);
    final data = await _api.query(query);
    final find = (data['category'] as Map?)?['programmeFind'] as Map<String, dynamic>?;
    final items = (find?['items'] as List? ?? const []).whereType<Map<String, dynamic>>();
    final titles = _dedupe([for (final item in items) _mapper.programme(item)]);
    return (titles: titles, total: (find?['totalCount'] as num?)?.toInt() ?? titles.length);
  }

  ({String id, String orderBy})? _parse(String browseId) {
    final parts = browseId.startsWith('cat:') ? browseId.substring(4).split(':') : [browseId];
    if (parts.isEmpty || !RegExp(r'^\d+$').hasMatch(parts.first)) return null;
    final order = parts.length > 1 && RegExp(r'^[A-Za-z_]+$').hasMatch(parts[1]) ? parts[1] : _popular;
    return (id: parts.first, orderBy: order);
  }

  List<ReplayTitle> _dedupe(List<ReplayTitle?> titles) {
    final seen = <String>{};
    return [
      for (final title in titles)
        if (title != null && seen.add(title.ref.toString())) title,
    ];
  }
}
