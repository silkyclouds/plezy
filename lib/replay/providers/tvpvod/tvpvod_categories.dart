import '../../model/replay_title.dart';

/// The main categories of the site's menu. Ids are the site's main category ids.
const tvpCategories = [
  ReplayCategory(id: '18', title: 'Seriale'),
  ReplayCategory(id: '136', title: 'Filmy fabularne'),
  ReplayCategory(id: '163', title: 'Filmy dokumentalne'),
  ReplayCategory(id: '88', title: 'Programy'),
  ReplayCategory(id: '205', title: 'Informacje i publicystyka'),
  ReplayCategory(id: '24', title: 'Dla dzieci'),
  ReplayCategory(id: '202', title: 'Teatr Telewizji'),
];

/// Web slug of a main category, the key of its curated rows.
const _slugs = {
  '18': 'seriale',
  '136': 'filmy-fabularne',
  '163': 'filmy-dokumentalne',
  '88': 'programy',
  '205': 'informacje-i-publicystyka',
  '24': 'dla-dzieci',
  '202': 'teatr-telewizji',
};

String? tvpCategorySlug(String categoryId) => _slugs[categoryId];

/// How a flat listing is ordered.
enum TvpSort {
  created('createdAt', 'desc', 'Najnowsze'),
  year('year', 'desc', 'Najnowsze produkcje'),
  title('title', 'asc', 'Od A do Z');

  final String field;
  final String order;
  final String label;

  const TvpSort(this.field, this.order, this.label);
}

/// A flat listing: the whole catalogue or one main category, in one order.
///
/// Browse ids are `all`, `cat:18` and `cat:18:year`.
class TvpListing {
  final String? categoryId;
  final TvpSort sort;

  const TvpListing({this.categoryId, this.sort = TvpSort.created});

  static TvpListing parse(String browseId) {
    final parts = browseId.split(':');
    if (parts.length < 2 || parts[0] != 'cat' || parts[1].isEmpty) return const TvpListing();
    final sort = TvpSort.values.where((s) => parts.length > 2 && s.name == parts[2]).firstOrNull;
    return TvpListing(categoryId: parts[1], sort: sort ?? TvpSort.created);
  }

  String get browseId => categoryId == null ? 'all' : 'cat:$categoryId:${sort.name}';
}
