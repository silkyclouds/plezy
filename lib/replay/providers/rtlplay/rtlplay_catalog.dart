import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'rtlplay_api.dart';
import 'rtlplay_categories.dart';
import 'rtlplay_episodes.dart';
import 'rtlplay_ids.dart';
import 'rtlplay_labels.dart';
import 'rtlplay_mapper.dart';

const _rowPrefix = 'row/';
const _fullListingTtl = Duration(minutes: 10);

/// Browse id of the whole content of one row.
String rtlPlayRowBrowseId(String storefront, String rowId) => '$_rowPrefix$storefront/$rowId';

/// Storefront rows, programme pages and search, mapped to the neutral show -> season -> episode model.
///
/// The catalogue has no listing of every programme, so the full listing is the union of every row of
/// every storefront, built once and kept for a few minutes.
class RtlPlayCatalog {
  final RtlPlayApi _api;
  final Map<String, String> _posters = {};
  Future<List<ReplayTitle>>? _everything;
  DateTime _everythingAt = DateTime.fromMillisecondsSinceEpoch(0);

  RtlPlayCatalog(this._api);

  Future<List<ReplayRail>> rails(String storefront) async {
    final rows = await _rows(storefront);
    final rails = <ReplayRail>[];
    for (final row in rows) {
      final titles = _remember(rtlPlayTitlesFromTeasers(row['teasers'], shape: rtlPlayRowShape(row)));
      if (titles.isEmpty) continue;
      final id = row['id'] as String;
      rails.add(
        ReplayRail(
          id: id,
          title: (row['title'] as String?)?.trim() ?? '',
          titles: titles,
          moreBrowseId: row['hasDetail'] == true ? rtlPlayRowBrowseId(storefront, id) : null,
        ),
      );
    }
    return rails;
  }

  Future<ReplayPage> listing(String browseId, {required int page, required int pageSize}) async {
    final titles = await _listingTitles(browseId);
    final start = page * pageSize;
    final slice = start >= titles.length ? const <ReplayTitle>[] : titles.skip(start).take(pageSize).toList();
    return ReplayPage(titles: slice, totalCount: titles.length);
  }

  Future<List<ReplayTitle>> search(String query) async {
    final body = await _api.search(query);
    final results = body?['results'];
    if (body == null || body['userMessage'] != null || results is! List) return const [];
    final seen = <String>{};
    final titles = <ReplayTitle>[];
    for (final group in results.whereType<Map<String, dynamic>>()) {
      final type = group['type'];
      if (type != 'exact' && type != 'collaborator') continue;
      for (final title in rtlPlayTitlesFromTeasers(group['teasers'])) {
        if (seen.add(title.ref.nativeId)) titles.add(title);
      }
    }
    return _remember(titles);
  }

  Future<ReplayTitle?> title(RtlPlayId id) async {
    final detail = await _api.detail(id.programme, season: id.season);
    if (detail == null) return null;
    final poster = _posters[id.programme];
    if (id.isProgramme) return rtlPlayTitleFromDetail(detail, id.programme, poster: poster);
    if (id.isSeason) return _seasonOf(detail, id, poster);
    return _episodeOf(detail, id, poster);
  }

  Future<List<ReplayTitle>> children(RtlPlayId id) async {
    if (id.isEpisode) return const [];
    final detail = await _api.detail(id.programme, season: id.season);
    if (detail == null) return const [];
    final poster = _posters[id.programme];
    if (id.isProgramme) return rtlPlaySeasons(detail, id.programme, poster: poster);
    return rtlPlayEpisodes(detail, id.programme, id.season!, poster: poster);
  }

  ReplayTitle? _seasonOf(Map<String, dynamic> detail, RtlPlayId id, String? poster) =>
      rtlPlaySeasons(detail, id.programme, poster: poster).where((s) => s.ref == id.seasonRef).firstOrNull;

  ReplayTitle? _episodeOf(Map<String, dynamic> detail, RtlPlayId id, String? poster) {
    final ref = rtlPlayEpisodeRef(id.programme, id.season!, id.episode!);
    return rtlPlayEpisodes(detail, id.programme, id.season!, poster: poster).where((e) => e.ref == ref).firstOrNull;
  }

  Future<List<Map<String, dynamic>>> _rows(String storefront) async {
    final rows = (await _api.storefront(storefront))?['rows'];
    if (rows is! List) return const [];
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (isRtlPlayCardRow(row) && row['id'] is String) row,
    ];
  }

  Future<List<ReplayTitle>> _listingTitles(String browseId) {
    if (browseId == replayAllBrowseId) return _allTitles();
    if (browseId.startsWith(_rowPrefix)) {
      final parts = browseId.substring(_rowPrefix.length).split('/');
      return parts.length == 2 ? _rowTitles(parts[0], parts[1]) : Future.value(const []);
    }
    if (rtlPlayCategories.any((c) => c.id == browseId)) return _storefrontTitles(browseId);
    return Future.value(const []);
  }

  Future<List<ReplayTitle>> _rowTitles(String storefront, String rowId) async {
    final row = (await _api.rowDetail(storefront, rowId))?['row'];
    if (row is! Map<String, dynamic>) return const [];
    return _remember(rtlPlayTitlesFromTeasers(row['teasers'], shape: rtlPlayRowShape(row)));
  }

  /// Every programme of a storefront, with rows that have a detail page expanded to their full content.
  Future<List<ReplayTitle>> _storefrontTitles(String storefront) async {
    final titles = <ReplayTitle>[];
    for (final row in await _rows(storefront)) {
      if (row['hasDetail'] == true) {
        titles.addAll(await _rowTitles(storefront, row['id'] as String));
      } else {
        titles.addAll(_remember(rtlPlayTitlesFromTeasers(row['teasers'], shape: rtlPlayRowShape(row))));
      }
    }
    return titles;
  }

  Future<List<ReplayTitle>> _allTitles() async {
    var pending = _everything;
    if (pending == null || DateTime.now().difference(_everythingAt) >= _fullListingTtl) {
      pending = _buildEverything();
      _everything = pending;
      _everythingAt = DateTime.now();
    }
    try {
      return await pending;
    } on Object {
      if (identical(_everything, pending)) _everything = null;
      rethrow;
    }
  }

  Future<List<ReplayTitle>> _buildEverything() async {
    final storefronts = [for (final c in rtlPlayCategories) c.id, rtlPlayHomeStorefront];
    final perStorefront = await Future.wait([for (final id in storefronts) _storefrontTitles(id)]);
    final seen = <String>{};
    final unique = [
      for (final titles in perStorefront)
        for (final title in titles)
          if (seen.add(title.ref.nativeId)) title,
    ];
    return unique..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title)));
  }

  /// Keeps the portrait art of listed titles: programme pages only carry landscape images.
  List<ReplayTitle> _remember(List<ReplayTitle> titles) {
    for (final title in titles) {
      final poster = title.posterUrl;
      if (poster != null) _posters[title.ref.nativeId] = poster;
    }
    return titles;
  }
}
