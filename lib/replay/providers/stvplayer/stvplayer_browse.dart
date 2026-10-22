import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'stvplayer_api.dart';
import 'stvplayer_mapper.dart';

const _recentId = '_recent';
const _viewedId = '_viewed';
const _popularId = '_popular';
const _clipsId = '_clips';

const _railSize = 20;
const _maxSearchResults = 100;

/// Categories, landing page rows, flat listings and search.
class StvPlayerBrowse {
  final StvPlayerApi _api;
  final StvPlayerMapper _mapper;
  final int pageSize;

  StvPlayerBrowse(this._api, this._mapper, {required this.pageSize});

  Future<List<ReplayCategory>> categories() async => [
    for (final c in await _api.categories())
      if (c['guid'] is String && c['name'] is String)
        ReplayCategory(id: c['guid'] as String, title: (c['name'] as String).trim()),
  ];

  Future<List<ReplayRail>> home() async {
    const rails = [
      (_recentId, 'Recently added'),
      (_viewedId, 'Most viewed'),
      (_popularId, 'Popular programmes'),
      (_clipsId, 'News clips'),
    ];
    final pages = await Future.wait([for (final rail in rails) _listing(rail.$1, 0, _railSize)]);
    return [
      for (var i = 0; i < rails.length; i++)
        if (pages[i].titles.isNotEmpty)
          ReplayRail(id: rails[i].$1, title: rails[i].$2, titles: pages[i].titles, moreBrowseId: rails[i].$1),
    ];
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    final pages = await Future.wait([
      _listing(_popularId, 0, _railSize, category: categoryId),
      _listing(categoryId, 0, pageSize),
    ]);
    return [
      if (pages[0].titles.isNotEmpty) ReplayRail(id: 'popular', title: 'Most popular', titles: pages[0].titles),
      if (pages[1].titles.isNotEmpty)
        ReplayRail(id: 'az', title: 'A to Z', titles: pages[1].titles, moreBrowseId: categoryId),
    ];
  }

  Future<ReplayPage> listing(String browseId, int page) => _listing(browseId, page, pageSize);

  /// Searches the programme list by name and synopsis. The server's own search needs a parameter nobody documents.
  Future<List<ReplayTitle>> search(String query) async {
    final words = _words(query);
    if (words.isEmpty) return const [];
    final ranked = <({int rank, String name, Map<String, dynamic> programme})>[];
    for (final programme in await _api.allProgrammes()) {
      final name = _fold(programme['name']);
      final text = '$name ${_fold(programme['shortName'])} ${_fold(programme['shortDescription'])}';
      if (!words.every(text.contains)) continue;
      final rank = name.contains(words.join(' ')) ? 0 : (words.every(name.contains) ? 1 : 2);
      ranked.add((rank: rank, name: name, programme: programme));
    }
    ranked.sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.name.compareTo(b.name));
    return [for (final hit in ranked.take(_maxSearchResults)) _mapper.show(hit.programme)];
  }

  Future<ReplayPage> _listing(String browseId, int page, int size, {String? category}) async {
    final offset = page * size;
    switch (browseId) {
      case _recentId:
        return _episodes('-availability.from', size, offset);
      case _viewedId:
        return _episodes('-views', size, offset);
      case _clipsId:
        final clips = await _api.clips(limit: size, offset: offset);
        return ReplayPage(titles: [for (final c in clips.items) _mapper.clip(c)], totalCount: clips.total);
      case _popularId:
        return _programmes({'orderBy': '-views', 'category': ?category}, size, offset);
      case replayAllBrowseId:
        return _programmes(const {'orderBy': 'name'}, size, offset);
      default:
        return _programmes({'orderBy': 'name', 'category': browseId}, size, offset);
    }
  }

  Future<ReplayPage> _episodes(String orderBy, int size, int offset) async {
    final episodes = await _api.episodes(query: {'orderBy': orderBy}, limit: size, offset: offset);
    return ReplayPage(titles: [for (final e in episodes.items) _mapper.episode(e)], totalCount: episodes.total);
  }

  Future<ReplayPage> _programmes(Map<String, String> query, int size, int offset) async {
    final programmes = await _api.programmes(query: query, limit: size, offset: offset);
    final seen = <String>{};
    return ReplayPage(
      titles: [
        for (final p in programmes.items)
          if (seen.add(p['guid'] as String)) _mapper.show(p),
      ],
      totalCount: programmes.total,
    );
  }
}

List<String> _words(String query) => _fold(query).split(' ').where((w) => w.isNotEmpty).toList();

/// Lower case with punctuation turned into spaces, so "Chase: Celebrity" matches "chase celebrity".
String _fold(Object? text) => text is String ? text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim() : '';
