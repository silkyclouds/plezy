import '../../model/replay_title.dart';

const nfbSeriesBrowseId = 'series';
const nfbRecentBrowseId = 'recent';
const nfbNewestBrowseId = 'newest';
const _genrePrefix = 'genre:';

/// Newest production year first; the catalogue breaks ties by title.
const nfbNewestSort = 'year:desc,title';
const nfbAlphabeticalSort = 'title';

/// Genres the catalogue can filter on: the name it expects and the heading shown to the viewer.
const nfbGenres = [
  (name: 'Documentary', title: 'Documentaries'),
  (name: 'Animation', title: 'Animation'),
  (name: 'Fiction', title: 'Fiction'),
  (name: "Children's film", title: "Children's films"),
  (name: 'Experimental', title: 'Experimental films'),
  (name: 'News Magazine (1940-1965)', title: 'News magazines, 1940 to 1965'),
];

/// Genres shown on the home page.
const nfbHomeGenres = ['Animation', 'Documentary', "Children's film"];

String nfbGenreBrowseId(String name) => '$_genrePrefix$name';

/// The genre name in a browse id, or null when the id is not a known genre.
String? nfbGenreOf(String browseId) {
  if (!browseId.startsWith(_genrePrefix)) return null;
  final name = browseId.substring(_genrePrefix.length);
  return nfbGenres.any((g) => g.name == name) ? name : null;
}

String nfbGenreTitle(String name) => nfbGenres.firstWhere((g) => g.name == name).title;

/// The site has no endpoint that lists its sections, so the menu is fixed.
final nfbCategories = [
  const ReplayCategory(id: nfbRecentBrowseId, title: 'Recently added'),
  const ReplayCategory(id: nfbSeriesBrowseId, title: 'Series'),
  for (final g in nfbGenres) ReplayCategory(id: nfbGenreBrowseId(g.name), title: g.title),
];
