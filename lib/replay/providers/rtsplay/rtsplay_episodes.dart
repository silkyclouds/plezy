import '../../model/replay_title.dart';
import 'rtsplay_api.dart';
import 'rtsplay_ids.dart';
import 'rtsplay_numbering.dart';

const _pageSize = 100;
const _maxPages = 10;
const _byShow = 'mediaList/video/latest/byShow';

/// The episodes of one show as the broadcaster serves them, newest first.
class RtsEpisodePages {
  final List<Map<String, dynamic>> items;

  /// True when the show has episodes this load did not reach.
  final bool truncated;

  const RtsEpisodePages(this.items, {required this.truncated});
}

/// Loads a show's episode lists: whole for ordinary shows, one page at a time for long daily shows.
class RtsEpisodeSource {
  final RtsPlayApi _api;

  RtsEpisodeSource(this._api);

  /// Episodes in served order, following the server's pagination up to [_maxPages] pages.
  ///
  /// A full first page with no continuation link, on a show that claims more episodes, is read again
  /// through the search endpoint, which pages by item offset.
  Future<RtsEpisodePages> load(String showId, {required int expected}) async {
    var page = await page0(showId);
    final items = [..._list(page, 'mediaList')];
    var next = page?['next'];
    for (var pages = 1; next is String && pages < _maxPages; pages++) {
      page = await _api.link(next);
      items.addAll(_list(page, 'mediaList'));
      next = page?['next'];
    }
    if (next == null && items.length == _pageSize && expected > _pageSize) return _viaSearch(showId);
    return RtsEpisodePages(items, truncated: next != null);
  }

  Future<Map<String, dynamic>?> page0(String showId) => _api.unit('$_byShow/$showId', {'pageSize': '$_pageSize'});

  /// Page [index] (zero-based) of the newest-first list. Empty once past the end.
  Future<List<Map<String, dynamic>>> pageAt(String showId, int index) async {
    final query = {'pageSize': '$_pageSize', if (index > 0) 'next': '$index'};
    return _list(await _api.unit('$_byShow/$showId', query), 'mediaList');
  }

  Future<RtsEpisodePages> _viaSearch(String showId) async {
    final items = <Map<String, dynamic>>[];
    var offset = 0;
    var total = 1;
    for (var pages = 0; pages < _maxPages && offset < total; pages++, offset += _pageSize) {
      final page = await _api.unit('searchResultMediaList', {
        'showUrns': 'urn:rts:show:tv:$showId',
        'pageSize': '$_pageSize',
        'includeAggregations': 'false',
        if (offset > 0) 'next': '$offset',
      });
      total = (page?['total'] as num?)?.toInt() ?? 0;
      items.addAll(_list(page, 'searchResultMediaList').where((i) => i['type'] == 'EPISODE'));
    }
    return RtsEpisodePages(items, truncated: offset < total);
  }
}

List<Map<String, dynamic>> _list(Map<String, dynamic>? page, String key) {
  final list = page?[key];
  return list is List ? list.whereType<Map<String, dynamic>>().toList() : const [];
}

/// Episodes grouped by season, in the order a season list shows them.
class RtsSeasonGroups {
  final Map<RtsSeasonKey, List<Map<String, dynamic>>> groups;

  RtsSeasonGroups._(this.groups);

  factory RtsSeasonGroups.of(Iterable<Map<String, dynamic>> items) {
    final groups = <RtsSeasonKey, List<Map<String, dynamic>>>{};
    for (final item in items) {
      (groups[rtsGroupKey(item)] ??= []).add(item);
    }
    final keys = groups.keys.toList()..sort(_byPosition);
    return RtsSeasonGroups._({for (final key in keys) key: groups[key]!});
  }

  bool get hasNumberedSeasons => groups.keys.any((k) => k.number != null);

  /// Season number shown for [key]: its own number, 0 for extras next to real seasons, 1 for a lone group.
  int numberOf(RtsSeasonKey key) => key.number ?? (hasNumberedSeasons ? 0 : 1);
}

/// The season an episode of an ordinary show belongs to.
RtsSeasonKey rtsGroupKey(Map<String, dynamic> item) {
  final numbers = rtsNumbers(item);
  if (numbers.season != null) return RtsSeasonKey.numbered(numbers.season!);
  return numbers.episode != null ? const RtsSeasonKey.numbered(1) : const RtsSeasonKey.other();
}

int _byPosition(RtsSeasonKey a, RtsSeasonKey b) {
  if (a.isOther || b.isOther) return a.isOther == b.isOther ? 0 : (a.isOther ? 1 : -1);
  return (a.number ?? 0).compareTo(b.number ?? 0);
}

/// Numbered episodes first in order, then the unnumbered ones newest first.
List<ReplayTitle> rtsOrderEpisodes(List<ReplayTitle> episodes) {
  final numbered = episodes.where((e) => e.episodeNumber != null).toList()
    ..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
  final rest = episodes.where((e) => e.episodeNumber == null).toList()
    ..sort((a, b) => (b.airDate ?? DateTime(0)).compareTo(a.airDate ?? DateTime(0)));
  return [...numbered, ...rest];
}
