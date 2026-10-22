import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'err_api.dart';
import 'err_mapper.dart';
import 'err_page_mapper.dart';
import 'err_refs.dart';
import 'err_season_list.dart';

/// Key of the season that holds a programme's episodes when ERR gives it no season list.
const errOnlySeason = 1;

/// How many month pages are requested at once when a year of a monthly programme is opened.
const _monthsAtOnce = 4;

/// Resolves the show -> season -> episode structure of ERR programmes.
///
/// ERR answers the id of a programme with its first episode and a season list. A season ref is `showId/key`, where
/// the key is the season number, or the year for programmes ERR files by month. A programme with no season list gets
/// one synthetic season, so every show has the same two levels.
class ErrCatalog {
  final ErrApi _api;

  ErrCatalog(this._api);

  /// The programme with this id, or null when the id is a film, an episode or unknown to ERR.
  Future<ReplayTitle?> show(int showId) async {
    final page = await _programmePage(showId);
    if (page == null) return null;
    final seasons = _seasonEntries(page);
    return errShowFromPage(page, showId, seasonCount: seasons.isEmpty ? 1 : seasons.length);
  }

  Future<List<ReplayTitle>> seasons(int showId) async {
    final page = await _programmePage(showId);
    final show = page == null ? null : errShowFromPage(page, showId);
    if (page == null || show == null) return const [];
    final entries = _seasonEntries(page);
    if (entries.isEmpty) return [_season(show, errOnlySeason, show.title, null)];
    return [
      for (final entry in entries) _season(show, entry.key, _seasonName(entry, show.title), entry.contents?.length),
    ];
  }

  Future<ReplayTitle?> season(ReplayRef ref) async {
    final parts = errSeasonParts(ref);
    if (parts == null) return null;
    return (await seasons(parts.showId)).where((s) => s.ref == ref).firstOrNull;
  }

  Future<List<ReplayTitle>> episodes(ReplayRef seasonRef) async {
    final parts = errSeasonParts(seasonRef);
    if (parts == null) return const [];
    final page = await _programmePage(parts.showId);
    final show = page == null ? null : errShowFromPage(page, parts.showId);
    if (page == null || show == null) return const [];

    final context = ErrContext(show: show.ref, showTitle: show.title, season: seasonRef, seasonNumber: parts.key);
    final list = errParseSeasonList(page['seasonList']);
    if (list == null) return parts.key == errOnlySeason ? _singleEpisode(page) : const [];
    final entry = list.entry(parts.key);
    if (entry == null) return const [];

    final contents = await _contents(entry, list, [parts.key]);
    final seen = <int>{};
    return [
      for (final item in contents)
        if (errTitleFromItem(item, context: context) case final title? when seen.add(int.parse(title.ref.nativeId)))
          title,
    ];
  }

  /// The page of a programme id, or null when the id is not a programme: ERR answers a film or an episode with that
  /// item itself, a programme with its first episode.
  Future<Map<String, dynamic>?> _programmePage(int showId) async {
    final page = await _api.contentPage(showId);
    final main = page?['mainContent'];
    if (page == null || main is! Map || (main['id'] as num?)?.toInt() == showId) return null;
    return page;
  }

  List<ErrSeasonEntry> _seasonEntries(Map<String, dynamic> page) {
    final entries = [...?errParseSeasonList(page['seasonList'])?.entries];
    return entries..sort((a, b) => a.key.compareTo(b.key));
  }

  ReplayTitle _season(ReplayTitle show, int key, String title, int? count) => ReplayTitle(
    ref: errSeasonRef(int.parse(show.ref.nativeId), key),
    kind: ReplayKind.season,
    title: title,
    posterUrl: show.posterUrl,
    backdropUrl: show.backdropUrl,
    seasonNumber: key,
    childCount: count,
    showRef: show.ref,
    showTitle: show.title,
  );

  /// Numbered seasons read "Hooaeg 2"; a year keeps its name; a short series has no name and takes the show's.
  String _seasonName(ErrSeasonEntry entry, String showTitle) {
    final name = entry.name?.trim() ?? '';
    if (name.isEmpty) return showTitle;
    return !entry.isYear && int.tryParse(name) != null ? 'Hooaeg $name' : name;
  }

  List<ReplayTitle> _singleEpisode(Map<String, dynamic> page) {
    final episode = errTitleFromPage(page);
    return episode == null ? const [] : [episode];
  }

  /// The raw episodes of [entry] in reading order, fetching the pages ERR leaves out of the season list.
  Future<List<Map<String, dynamic>>> _contents(ErrSeasonEntry entry, ErrSeasonList list, List<int> path) async {
    if (!entry.isYear) return _ordered(entry.contents ?? await _fetch(entry.firstContentId, path), list);
    final months = [...entry.months]..sort((a, b) => a.key.compareTo(b.key));
    final all = <Map<String, dynamic>>[];
    for (var i = 0; i < months.length; i += _monthsAtOnce) {
      final batch = months.skip(i).take(_monthsAtOnce);
      final loaded = await Future.wait([
        for (final month in batch)
          month.contents != null ? Future.value(month.contents!) : _fetch(month.firstContentId, [entry.key, month.key]),
      ]);
      for (final contents in loaded) {
        all.addAll(_ordered(contents, list));
      }
    }
    return all;
  }

  List<Map<String, dynamic>> _ordered(List<Map<String, dynamic>> contents, ErrSeasonList list) =>
      list.descending ? contents.reversed.toList() : contents;

  /// The episodes of the season at [path] (season key, or year and month), read from the page that opens on it.
  Future<List<Map<String, dynamic>>> _fetch(int pageId, List<int> path) async {
    final list = errParseSeasonList((await _api.contentPage(pageId))?['seasonList']);
    var entry = list?.entry(path.first);
    for (final key in path.skip(1)) {
      entry = entry?.months.where((m) => m.key == key).firstOrNull;
    }
    return entry?.contents ?? const [];
  }
}
