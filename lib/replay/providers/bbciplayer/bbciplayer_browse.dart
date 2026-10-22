import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'bbciplayer_api.dart';
import 'bbciplayer_mapper.dart';

/// Browse ids of the listings: `cat:{categoryId}`, `ch:{channelId}` and `group:{groupId}`; [replayAllBrowseId] is A-Z.
const _categoryPrefix = 'cat:';
const _channelPrefix = 'ch:';
const _groupPrefix = 'group:';

const _homeChannel = 'bbc_one_london';
const _maxGroupRows = 6;
const _letters = [
  '0-9',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
  'x',
  'y',
  'z',
];
const _letterPage = 100;
const _letterBatch = 4;

/// Sections, home rows, listings and search over the iBL catalogue.
class BbcIplayerBrowse {
  final BbcIplayerApi _api;
  final DateTime Function() _now;
  final int pageSize;
  ({DateTime at, List<int> counts})? _letterCounts;

  BbcIplayerBrowse(this._api, this._now, {required this.pageSize});

  Future<List<ReplayCategory>> categories() async {
    final channels = await _channels();
    final channelBrands = {for (final c in channels) c['master_brand_id']};
    final body = await _api.ibl('categories');
    final categories = body['categories'];
    return [
      for (final c in channels) ReplayCategory(id: '$_channelPrefix${c['id']}', title: c['title'] as String),
      if (categories is List)
        for (final c in categories.whereType<Map<String, dynamic>>())
          if (!channelBrands.contains(c['id']))
            ReplayCategory(id: '$_categoryPrefix${c['id']}', title: c['title'] as String),
    ];
  }

  Future<List<ReplayRail>> home() => _highlights(_homeChannel);

  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId.startsWith(_channelPrefix)) return _highlights(categoryId.substring(_channelPrefix.length));
    final id = categoryId.startsWith(_categoryPrefix) ? categoryId.substring(_categoryPrefix.length) : categoryId;
    final page = await listing('$_categoryPrefix$id');
    if (page.titles.isEmpty) return const [];
    final title = await _categoryTitle(id);
    return [ReplayRail(id: id, title: title, titles: page.titles, moreBrowseId: '$_categoryPrefix$id')];
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) {
    if (browseId == replayAllBrowseId) return _atoz(page);
    if (browseId.startsWith(_channelPrefix)) {
      return _paged('channels/${browseId.substring(_channelPrefix.length)}/programmes', 'channel_programmes', page);
    }
    if (browseId.startsWith(_groupPrefix)) {
      return _paged('groups/${browseId.substring(_groupPrefix.length)}/episodes', 'group_episodes', page);
    }
    final id = browseId.startsWith(_categoryPrefix) ? browseId.substring(_categoryPrefix.length) : browseId;
    return _paged('categories/$id/programmes', 'category_programmes', page);
  }

  /// Results come back as one page of 24, brands and episodes mixed. Shows with nothing to watch yet are dropped.
  Future<List<ReplayTitle>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final body = await _api.ibl('new-search', query: {'q': trimmed});
    final results = (body['new_search'] as Map?)?['results'];
    final titles = bbcTitlesFromElements(results, _now());
    return [
      for (final t in titles)
        if (t.availability != ReplayAvailability.upcoming || t.kind != ReplayKind.show) t,
    ];
  }

  Future<List<Map<String, dynamic>>> _channels() async {
    final channels = (await _api.ibl('channels'))['channels'];
    if (channels is! List) return const [];
    return [
      for (final c in channels.whereType<Map<String, dynamic>>())
        if (!(c['id'] as String).startsWith('bbc_radio')) c,
    ];
  }

  Future<String> _categoryTitle(String id) async {
    final categories = (await _api.ibl('categories'))['categories'];
    if (categories is List) {
      for (final c in categories.whereType<Map<String, dynamic>>()) {
        if (c['id'] == id) return c['title'] as String;
      }
    }
    return id;
  }

  /// The landing rows of a channel: a "Featured" row of episodes, then each curated group filled by its own call.
  Future<List<ReplayRail>> _highlights(String channelId) async {
    final body = await _api.ibl('channels/$channelId/highlights');
    final elements = (body['channel_highlights'] as Map?)?['elements'];
    if (elements is! List) return const [];
    final items = elements.whereType<Map<String, dynamic>>().toList();

    final featured = bbcTitlesFromElements(items.where((e) => e['type'] == 'episode').toList(), _now());
    final groups = items.where((e) => e['type'] == 'group_large').take(_maxGroupRows).toList();
    final filled = await Future.wait([
      for (final g in groups) _api.ibl('groups/${g['id']}/episodes', query: {'per_page': '20'}),
    ]);
    return [
      if (featured.isNotEmpty) ReplayRail(id: 'featured', title: 'Featured', titles: featured),
      for (final (i, g) in groups.indexed)
        if (_rows(filled[i], 'group_episodes') case final titles when titles.isNotEmpty)
          ReplayRail(
            id: 'group:${g['id']}',
            title: g['title'] as String? ?? '',
            titles: titles,
            moreBrowseId: '$_groupPrefix${g['id']}',
          ),
    ];
  }

  Future<ReplayPage> _paged(String path, String block, int page) async {
    final body = await _api.ibl(path, query: {'page': '${page + 1}', 'per_page': '$pageSize'});
    return ReplayPage(titles: _rows(body, block), totalCount: _count(body, block));
  }

  List<ReplayTitle> _rows(Map<String, dynamic> body, String block) =>
      bbcTitlesFromElements((body[block] as Map?)?['elements'], _now());

  int _count(Map<String, dynamic> body, String block) => ((body[block] as Map?)?['count'] as num?)?.toInt() ?? 0;

  /// The whole catalogue is the 27 alphabetical lists back to back. A page is a window of [pageSize] titles over
  /// that sequence, so it may straddle two letters.
  Future<ReplayPage> _atoz(int page) async {
    final counts = await _counts();
    final total = counts.fold<int>(0, (sum, c) => sum + c);
    final from = page * pageSize;
    final to = from + pageSize;
    final titles = <ReplayTitle>[];
    var letterStart = 0;
    for (final (i, count) in counts.indexed) {
      final letterEnd = letterStart + count;
      if (letterEnd > from && letterStart < to) {
        final inLetterFrom = (from > letterStart ? from : letterStart) - letterStart;
        final inLetterTo = (to < letterEnd ? to : letterEnd) - letterStart;
        titles.addAll(await _letterSlice(_letters[i], inLetterFrom, inLetterTo));
      }
      letterStart = letterEnd;
    }
    return ReplayPage(titles: titles, totalCount: total);
  }

  Future<List<ReplayTitle>> _letterSlice(String letter, int from, int to) async {
    final titles = <ReplayTitle>[];
    for (var chunk = from ~/ _letterPage; chunk * _letterPage < to; chunk++) {
      final body = await _atozPage(letter, chunk + 1);
      final rows = _rows(body, 'atoz_programmes');
      final offset = chunk * _letterPage;
      final start = from > offset ? from - offset : 0;
      final end = to - offset < rows.length ? to - offset : rows.length;
      if (start < end) titles.addAll(rows.sublist(start, end));
    }
    return titles;
  }

  Future<Map<String, dynamic>> _atozPage(String letter, int page) =>
      _api.ibl('atoz/$letter/programmes', query: {'page': '$page', 'per_page': '$_letterPage'});

  Future<List<int>> _counts() async {
    final known = _letterCounts;
    if (known != null && _now().difference(known.at) < const Duration(minutes: 30)) return known.counts;
    final counts = <int>[];
    for (var i = 0; i < _letters.length; i += _letterBatch) {
      final batch = _letters.skip(i).take(_letterBatch);
      final bodies = await Future.wait([for (final l in batch) _atozPage(l, 1)]);
      counts.addAll([for (final b in bodies) _count(b, 'atoz_programmes')]);
    }
    _letterCounts = (at: _now(), counts: counts);
    return counts;
  }
}
