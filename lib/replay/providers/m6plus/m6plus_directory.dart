import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'm6plus_api.dart';
import 'm6plus_categories.dart';
import 'm6plus_dates.dart';
import 'm6plus_mapper.dart';
import 'm6plus_search.dart';

/// Browsing, home rows and search over the programme list.
///
/// The full list is about fourteen requests, so it is loaded once and reused by home rows, search
/// and the "free" section. Plain A-Z and category paging go straight to the API instead.
class M6plusDirectory {
  static const _catalogueTtl = Duration(hours: 1);
  static const _railSize = 30;
  static const _maxPages = 30;
  static const _minChannelRow = 5;

  final M6plusApi _api;
  List<Map<String, dynamic>>? _programs;
  DateTime _loadedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<List<Map<String, dynamic>>>? _loading;

  M6plusDirectory(this._api);

  Future<ReplayPage> listing(String browseId, int page) async {
    if (browseId == m6plusFreeBrowseId) return _freeListing(page);
    final offset = page * M6plusApi.pageSize;
    final raw = browseId == replayAllBrowseId
        ? await _api.programs(offset)
        : await _api.folderPrograms(browseId, offset);
    final known = _programs;
    final total = known != null && browseId == replayAllBrowseId
        ? known.length
        : (raw.length < M6plusApi.pageSize ? offset + raw.length : offset + raw.length + 1);
    return ReplayPage(titles: _titles(raw), totalCount: total);
  }

  Future<List<ReplayRail>> home() async {
    final programs = _withContent(await _catalogue());
    final recent = _newestFirst(programs);
    final rails = <ReplayRail>[ReplayRail(id: 'recent', title: 'Nouveautés', titles: _titles(recent.take(_railSize)))];

    final free = recent.where(_hasClearContent).toList();
    if (free.isNotEmpty) {
      rails.add(
        ReplayRail(
          id: m6plusFreeBrowseId,
          title: 'Extraits et podcasts',
          titles: _titles(free.take(_railSize)),
          moreBrowseId: free.length > _railSize ? m6plusFreeBrowseId : null,
        ),
      );
    }
    for (final channel in m6plusChannels.entries) {
      final onChannel = recent.where((p) => _service(p) == channel.key).toList();
      if (onChannel.length < _minChannelRow) continue;
      rails.add(
        ReplayRail(id: 'channel-${channel.key}', title: channel.value, titles: _titles(onChannel.take(_railSize))),
      );
    }
    return rails;
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    final title = m6plusCategories.where((c) => c.id == categoryId).firstOrNull?.title ?? categoryId;
    final page = await listing(categoryId, 0);
    if (page.titles.isEmpty) return const [];
    final more = page.totalCount > page.titles.length;
    return [
      ReplayRail(id: 'category-$categoryId', title: title, titles: page.titles, moreBrowseId: more ? categoryId : null),
    ];
  }

  Future<List<ReplayTitle>> search(String query) async {
    final hits = m6plusSearchPrograms(_withContent(await _catalogue()), query);
    return _titles(hits);
  }

  Future<ReplayPage> _freeListing(int page) async {
    final free = _newestFirst(_withContent(await _catalogue())).where(_hasClearContent).toList();
    final from = (page * M6plusApi.pageSize).clamp(0, free.length);
    final to = (from + M6plusApi.pageSize).clamp(from, free.length);
    return ReplayPage(titles: _titles(free.sublist(from, to)), totalCount: free.length);
  }

  /// Every programme, in the server's order. Concurrent callers share one load.
  Future<List<Map<String, dynamic>>> _catalogue() {
    final cached = _programs;
    if (cached != null && DateTime.now().difference(_loadedAt) < _catalogueTtl) return Future.value(cached);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final all = <Map<String, dynamic>>[];
    for (var page = 0; page < _maxPages; page++) {
      final batch = await _api.programs(page * M6plusApi.pageSize);
      all.addAll(batch);
      if (batch.length < M6plusApi.pageSize) break;
    }
    _programs = all;
    _loadedAt = DateTime.now();
    return all;
  }

  List<ReplayTitle> _titles(Iterable<Map<String, dynamic>> programs) => [
    for (final program in _withContent(programs)) m6plusTitleFromProgram(program),
  ];

  /// Programmes with nothing to watch or hear are noise in a list.
  List<Map<String, dynamic>> _withContent(Iterable<Map<String, dynamic>> programs) => [
    for (final p in programs)
      if (_itemCount(p) != 0) p,
  ];

  List<Map<String, dynamic>> _newestFirst(List<Map<String, dynamic>> programs) {
    final indexed = [for (var i = 0; i < programs.length; i++) (i, programs[i])];
    DateTime stamp(Map<String, dynamic> p) =>
        m6plusDate(p['last_clip_publication']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    indexed.sort((a, b) {
      final byDate = stamp(b.$2).compareTo(stamp(a.$2));
      return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  bool _hasClearContent(Map<String, dynamic> program) {
    final count = program['count'];
    return count is Map && ((m6plusInt(count['vc']) ?? 0) + (m6plusInt(count['podcast']) ?? 0)) > 0;
  }

  /// Total items of every kind, or null when the programme does not say.
  int? _itemCount(Map<String, dynamic> program) {
    final count = program['count'];
    if (count is! Map) return null;
    return count.values.whereType<num>().fold<int>(0, (sum, n) => sum + n.toInt());
  }

  String? _service(Map<String, dynamic> program) => (program['service_display'] as Map?)?['code'] as String?;
}
