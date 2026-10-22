import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'threecat_api.dart';
import 'threecat_envelope.dart';
import 'threecat_ids.dart';
import 'threecat_mapper.dart';
import 'threecat_numbering.dart';

/// Resolves the show -> season -> episode structure of 3Cat programmes.
///
/// A programme lists all its full episodes in one flat result. Seasons are read from the episodes: the broadcaster's
/// own season id when there is one, else the `T2xC5` numbering in the title. Episodes outside any season form the
/// season `_all`, which is the only one of a programme with no seasons.
class ThreeCatCatalog {
  static const _pageSize = 100;

  /// Pages read to group a programme locally: 500 episodes. Larger programmes lean on the server's season filter.
  static const _localPages = 5;
  static const _filteredPages = 3;
  static const _probeLimit = 60;

  final ThreeCatApi _api;
  final ThreeCatMapper _mapper;

  ThreeCatCatalog(this._api, this._mapper);

  Future<ReplayTitle?> show(String programmeId) async {
    try {
      final item = threeCatItem(await _api.catalogue('programestv/$programmeId/'));
      return item == null ? null : threeCatShow(item);
    } on MediaServerHttpException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ReplayTitle>> seasons(String programmeId) async {
    final show = await this.show(programmeId);
    if (show == null) return const [];
    final found = await _discover(programmeId);
    final numbered = found.seasons.where((s) => s.key != threeCatLooseSeason).toList();
    if (numbered.isEmpty) return [_syntheticSeason(programmeId, show, found.total)];
    final loose = found.seasons.where((s) => s.key == threeCatLooseSeason);
    return [
      for (final s in numbered) _season(programmeId, show, s),
      for (final s in loose) _otherEpisodes(programmeId, show, s),
    ];
  }

  Future<List<ReplayTitle>> episodes(String programmeId, String seasonKey) async {
    final season = threeCatSeasonRef(programmeId, seasonKey);
    final first = await _page(programmeId, 1);
    final paging = threeCatPaging(first);
    final items = seasonKey.startsWith('PUTEMP_') && paging.totalPages > _localPages
        ? await _filteredItems(programmeId, seasonKey)
        : _inSeason(await _allItems(programmeId, first, paging), seasonKey);
    return _inOrder(_mapper.titles(items, season: season));
  }

  Future<Map<String, dynamic>> _page(String programmeId, int page, {String? season, int size = _pageSize}) =>
      _api.catalogue('videos', {
        'tipus_contingut': 'PPD',
        'programatv_id': programmeId,
        'items_pagina': '$size',
        'pagina': '$page',
        'temporada': ?season,
      });

  Future<List<Map<String, dynamic>>> _allItems(
    String programmeId,
    Map<String, dynamic> first,
    ({int totalItems, int totalPages}) paging,
  ) async {
    final last = paging.totalPages < _localPages ? paging.totalPages : _localPages;
    final rest = await Future.wait([for (var page = 2; page <= last; page++) _page(programmeId, page)]);
    return _distinct([...threeCatItems(first), for (final page in rest) ...threeCatItems(page)]);
  }

  Future<List<Map<String, dynamic>>> _filteredItems(String programmeId, String seasonKey) async {
    final first = await _page(programmeId, 1, season: seasonKey);
    final pages = threeCatPaging(first).totalPages;
    final last = pages < _filteredPages ? pages : _filteredPages;
    final rest = await Future.wait([
      for (var page = 2; page <= last; page++) _page(programmeId, page, season: seasonKey),
    ]);
    return _distinct([...threeCatItems(first), for (final page in rest) ...threeCatItems(page)]);
  }

  List<Map<String, dynamic>> _distinct(List<Map<String, dynamic>> items) {
    final seen = <Object?>{};
    return [
      for (final item in items)
        if (seen.add(item['id'])) item,
    ];
  }

  Future<_Found> _discover(String programmeId) async {
    final first = await _page(programmeId, 1);
    final paging = threeCatPaging(first);
    if (paging.totalPages <= _localPages) {
      final items = await _allItems(programmeId, first, paging);
      return _Found(_group(items, exact: true), items.length);
    }
    final last = await _page(programmeId, paging.totalPages);
    final sampled = _group(_distinct([...threeCatItems(first), ...threeCatItems(last)]), exact: false);
    return _Found(await _counted(programmeId, sampled), paging.totalItems);
  }

  /// Fills the gaps between the first and last season met in a large programme, and counts each one.
  Future<List<_Season>> _counted(String programmeId, List<_Season> sampled) async {
    final numbers = [
      for (final s in sampled)
        if (s.key.startsWith('PUTEMP_')) ?threeCatSeasonNumber(s.key),
    ];
    if (numbers.isEmpty) return sampled;
    numbers.sort();
    final span = numbers.last - numbers.first + 1;
    if (span > _probeLimit) return sampled;
    final known = {for (final s in sampled) s.key: s};
    final probed = await Future.wait([
      for (var n = numbers.first; n <= numbers.last; n++) _probe(programmeId, 'PUTEMP_$n', known['PUTEMP_$n']?.label),
    ]);
    final others = sampled.where((s) => !s.key.startsWith('PUTEMP_'));
    return [...probed.nonNulls, ...others];
  }

  Future<_Season?> _probe(String programmeId, String key, String? label) async {
    final answer = await _page(programmeId, 1, season: key, size: 1);
    final total = threeCatPaging(answer).totalItems;
    if (total == 0) return null;
    final sample = threeCatItems(answer).firstOrNull;
    return _Season(key, label ?? (sample == null ? null : threeCatSeasonLabel(sample)), total);
  }

  List<_Season> _group(List<Map<String, dynamic>> items, {required bool exact}) {
    final keys = _keys(items);
    final groups = <String, _Season>{};
    for (var i = 0; i < items.length; i++) {
      final key = keys[i] ?? threeCatLooseSeason;
      final label = threeCatSeasonLabel(items[i]);
      final seen = groups[key];
      groups[key] = _Season(key, seen?.label ?? label, exact ? (seen?.count ?? 0) + 1 : null);
    }
    final list = groups.values.toList();
    list.sort((a, b) => (threeCatSeasonNumber(a.key) ?? -1).compareTo(threeCatSeasonNumber(b.key) ?? -1));
    return list;
  }

  List<Map<String, dynamic>> _inSeason(List<Map<String, dynamic>> items, String seasonKey) {
    final keys = _keys(items);
    return [
      for (var i = 0; i < items.length; i++)
        if ((keys[i] ?? threeCatLooseSeason) == seasonKey) items[i],
    ];
  }

  /// Season key per item. A title-derived `T2` joins the broadcaster's `PUTEMP_2` when the programme has both.
  List<String?> _keys(List<Map<String, dynamic>> items) {
    final keys = [for (final item in items) threeCatSeasonKey(item)];
    final own = keys.whereType<String>().where((k) => k.startsWith('PUTEMP_')).toSet();
    return [
      for (final key in keys)
        if (key != null && key.startsWith('T') && own.contains('PUTEMP_${key.substring(1)}'))
          'PUTEMP_${key.substring(1)}'
        else
          key,
    ];
  }

  List<ReplayTitle> _inOrder(List<ReplayTitle> titles) {
    final indexed = [for (var i = 0; i < titles.length; i++) (i, titles[i])];
    indexed.sort((a, b) {
      final left = a.$2.episodeNumber;
      final right = b.$2.episodeNumber;
      if (left != null && right != null && left != right) return left.compareTo(right);
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  ReplayTitle _season(String programmeId, ReplayTitle show, _Season season) {
    final number = threeCatSeasonNumber(season.key);
    return ReplayTitle(
      ref: threeCatSeasonRef(programmeId, season.key),
      kind: ReplayKind.season,
      title: season.label ?? 'Temporada ${number ?? season.key}',
      posterUrl: show.posterUrl,
      backdropUrl: show.backdropUrl,
      seasonNumber: number,
      childCount: season.count,
      showRef: show.ref,
      showTitle: show.title,
    );
  }

  ReplayTitle _otherEpisodes(String programmeId, ReplayTitle show, _Season season) => ReplayTitle(
    ref: threeCatSeasonRef(programmeId, threeCatLooseSeason),
    kind: ReplayKind.season,
    title: 'Altres capítols',
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 0,
    childCount: season.count,
    showRef: show.ref,
    showTitle: show.title,
  );

  ReplayTitle _syntheticSeason(String programmeId, ReplayTitle show, int total) => ReplayTitle(
    ref: threeCatSeasonRef(programmeId, threeCatLooseSeason),
    kind: ReplayKind.season,
    title: show.title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: 1,
    childCount: total > 0 ? total : null,
    showRef: show.ref,
    showTitle: show.title,
  );
}

class _Season {
  final String key;
  final String? label;

  /// Episodes in the season, when every one of them has been seen or counted.
  final int? count;

  const _Season(this.key, this.label, this.count);
}

class _Found {
  final List<_Season> seasons;
  final int total;

  const _Found(this.seasons, this.total);
}
