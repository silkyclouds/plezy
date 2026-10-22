import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import '../../provider/replay_provider.dart';
import 'nfb_api.dart';
import 'nfb_catalog.dart';
import 'nfb_categories.dart';
import 'nfb_feed.dart';
import 'nfb_mapper.dart';

/// Home rows, category pages, flat listings and search over the NFB catalogue.
class NfbBrowse {
  /// Titles per listing page and per row.
  static const pageSize = 24;
  static const _searchSize = 30;

  final NfbApi _api;
  final NfbCatalog _catalog;
  final DateTime Function() _now;

  NfbBrowse(this._api, this._catalog, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Rows load independently: one that fails is left out, and the home page only fails when every row does.
  Future<List<ReplayRail>> home() async {
    final loaders = <(String, String, String?, Future<List<ReplayTitle>> Function())>[
      (nfbRecentBrowseId, 'Recently added', null, _recent),
      (nfbSeriesBrowseId, 'Series', null, _catalog.shows),
      (nfbNewestBrowseId, 'Newest films', nfbNewestBrowseId, () => _films(sort: nfbNewestSort)),
      for (final genre in nfbHomeGenres)
        (
          nfbGenreBrowseId(genre),
          nfbGenreTitle(genre),
          nfbGenreBrowseId(genre),
          () => _films(genre: genre, sort: nfbNewestSort),
        ),
    ];
    final rails = <ReplayRail>[];
    Object? failure;
    for (final (id, title, more, load) in loaders) {
      try {
        rails.add(_rail(id, title, await load(), more: more));
      } on MediaServerHttpException catch (e) {
        failure ??= e;
      } on NfbRateLimitedException catch (e) {
        failure ??= e;
      }
    }
    final shown = _withTitles(rails);
    if (shown.isEmpty && failure != null) throw failure;
    return shown;
  }

  Future<List<ReplayRail>> category(String categoryId) async {
    if (categoryId == nfbRecentBrowseId) {
      return _withTitles([_rail(categoryId, 'Recently added', await _recent(), more: null)]);
    }
    if (categoryId == nfbSeriesBrowseId) {
      return _withTitles([_rail(categoryId, 'Series', await _catalog.shows(), more: null)]);
    }
    final genre = nfbGenreOf(categoryId);
    if (genre == null) return const [];
    final heading = nfbGenreTitle(genre);
    return _withTitles([
      _rail('$categoryId:newest', 'Newest in $heading', await _films(genre: genre, sort: nfbNewestSort), more: null),
      _rail(
        categoryId,
        heading,
        await _films(genre: genre, sort: nfbAlphabeticalSort),
        more: categoryId,
      ),
    ]);
  }

  Future<ReplayPage> listing(String browseId, {int page = 0}) async {
    if (browseId == nfbSeriesBrowseId || browseId == nfbRecentBrowseId) {
      final titles = browseId == nfbSeriesBrowseId ? await _catalog.shows() : await _recent();
      return ReplayPage(titles: page == 0 ? titles : const [], totalCount: titles.length);
    }
    final genre = nfbGenreOf(browseId);
    final everything = browseId == replayAllBrowseId || browseId == nfbNewestBrowseId;
    if (genre == null && !everything) return const ReplayPage(titles: [], totalCount: 0);
    final sort = browseId == nfbNewestBrowseId ? nfbNewestSort : nfbAlphabeticalSort;
    final body = await _api.films(genre: genre, sort: sort, page: page + 1, size: pageSize);
    final titles = nfbTitlesFromFilms(body, genre: genre, now: _now());
    return ReplayPage(titles: titles, totalCount: nfbTotal(body, titles.length));
  }

  /// Series whose name matches, then films the catalogue ranks for the words. Episodes are included because their
  /// show is not named in their title.
  Future<List<ReplayTitle>> search(String query) async {
    final words = query.trim();
    if (words.isEmpty) return const [];
    final needle = words.toLowerCase();
    final shows = [
      for (final show in await _catalog.shows())
        if (show.title.toLowerCase().contains(needle)) show,
    ];
    final body = await _api.films(query: words, size: _searchSize);
    return [...shows, ...nfbTitlesFromFilms(body, includeEpisodes: true, now: _now())];
  }

  Future<List<ReplayTitle>> _films({String? genre, required String sort}) async {
    final body = await _api.films(genre: genre, sort: sort, size: pageSize);
    return nfbTitlesFromFilms(body, genre: genre, now: _now());
  }

  Future<List<ReplayTitle>> _recent() async {
    final feed = await _api.recentFeed();
    return feed == null ? const [] : nfbTitlesFromFeed(feed);
  }

  ReplayRail _rail(String id, String title, List<ReplayTitle> titles, {required String? more}) =>
      ReplayRail(id: id, title: title, titles: titles, moreBrowseId: more);

  List<ReplayRail> _withTitles(List<ReplayRail> rails) => [
    for (final rail in rails)
      if (rail.titles.isNotEmpty) rail,
  ];
}
