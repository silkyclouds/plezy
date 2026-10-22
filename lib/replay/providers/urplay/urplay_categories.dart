import '../../model/replay_title.dart';

/// Page size of every UR listing; the API ignores any other value.
const urPageSize = 24;

/// UR has no endpoint that lists its genres, and the filter only accepts the exact Swedish label (anything else is
/// an HTTP 400), so the menu is fixed. These are the labels the catalogue carries.
const urGenres = [
  'Dokumentärserie',
  'Dokumentärfilm',
  'Fiktiva berättelser',
  'Drama',
  'Lär-mer-program',
  'Faktaprogram',
  'Explainer',
  'Experiment',
  'Föreläsning',
  'Intervju/samtal',
  'Panelsamtal/Intervju',
  'Nyheter',
  'Reportage',
  'Reseprogram',
  'Reality',
  'Kortfilm',
  'Sånger',
  'Uppläsningar',
];

/// Genres shown as rows on the landing page.
const urHomeGenres = [
  'Dokumentärserie',
  'Fiktiva berättelser',
  'Lär-mer-program',
  'Faktaprogram',
  'Nyheter',
  'Reseprogram',
];

final urCategories = [for (final genre in urGenres) ReplayCategory(id: genre, title: genre)];

/// What a listing shows: UR's two product types, optionally narrowed to one genre.
class UrBrowseTarget {
  final String productType;
  final String? genre;

  const UrBrowseTarget(this.productType, [this.genre]);

  /// Browse id of the target: `series`, `program`, `series:Genre` or `program:Genre`.
  String get id => genre == null ? productType : '$productType:$genre';

  /// Parses a browse id, where the shared "all" id means every series.
  static UrBrowseTarget parse(String browseId, String allId) {
    if (browseId == allId) return const UrBrowseTarget('series');
    final cut = browseId.indexOf(':');
    final type = cut < 0 ? browseId : browseId.substring(0, cut);
    final genre = cut < 0 ? null : browseId.substring(cut + 1);
    return UrBrowseTarget(type == 'program' ? 'program' : 'series', genre == null || genre.isEmpty ? null : genre);
  }

  Map<String, String> query({int start = 0, bool newest = false}) => {
    'product_type': productType,
    'main_genre': ?genre,
    if (newest) 'sort': 'newest',
    if (start > 0) 'start': '$start',
  };
}
