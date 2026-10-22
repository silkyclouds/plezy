import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'err_mapper.dart';

/// Titles of a genre page shown as one row; the rest sits behind "see all".
const errGenreRowSize = 40;

/// Rows of a section page. Promotional banners, live blocks, rows made for a signed-in viewer, unnamed rows and rows
/// without a card that can be opened are dropped.
List<ReplayRail> errRailsFromCategory(Map<String, dynamic> category) {
  final rows = category['frontPage'];
  if (rows is! List) return const [];
  final rails = <ReplayRail>[];
  for (final row in rows.whereType<Map<String, dynamic>>()) {
    if (_isPromotion(row)) continue;
    final header = errText(row['header']);
    final data = row['data'];
    final titles = data is List ? errTitles(data) : const <ReplayTitle>[];
    if (header == null || titles.isEmpty) continue;
    final more = _moreBrowseId(row['headerUrl']);
    rails.add(ReplayRail(id: more ?? header, title: header, titles: titles, moreBrowseId: more));
  }
  return rails;
}

/// A genre page lists every title in `items`; it becomes one row that links to the full listing.
List<ReplayRail> errRailsFromGenre(String slug, Map<String, dynamic> category) {
  final items = category['items'];
  final titles = items is List ? errTitles(items).take(errGenreRowSize).toList() : const <ReplayTitle>[];
  if (titles.isEmpty) return const [];
  final name = errText(category['name']) ?? slug;
  return [ReplayRail(id: slug, title: name, titles: titles, moreBrowseId: slug)];
}

/// Everything a page lists, for "see all": a genre page has it in `items`, a section page only in its rows. A card
/// that sits in several rows is listed once.
List<dynamic> errCategoryItems(Map<String, dynamic> category) {
  final items = category['items'];
  if (items is List && items.isNotEmpty) return items;
  final rows = category['frontPage'];
  if (rows is! List) return const [];
  final seen = <Object?>{};
  return [
    for (final row in rows.whereType<Map<String, dynamic>>())
      if (!_isPromotion(row) && row['data'] is List)
        for (final card in row['data'] as List)
          if (card is Map && seen.add(card['id'])) card,
  ];
}

/// The titles of a list of cards or catalogue items, without repeats and without what cannot be opened.
List<ReplayTitle> errTitles(Iterable<dynamic> items) {
  final seen = <ReplayRef>{};
  return [
    for (final item in items)
      if (item is Map<String, dynamic>)
        if (errTitleFromItem(item) case final title? when seen.add(title.ref)) title,
  ];
}

bool _isPromotion(Map<String, dynamic> row) {
  final manual = row['manual'];
  return (manual is Map && manual['banner'] == true) || row['liveBlock'] == true || row['userBasedTimeline'] == true;
}

/// The slug of the "see all" page. Rows that link to another site, to a path inside a section or to a programme
/// (a bare number) have none.
String? _moreBrowseId(Object? headerUrl) {
  if (headerUrl is! String || !headerUrl.startsWith('/') || headerUrl.length < 2) return null;
  final slug = headerUrl.substring(1);
  return slug.contains('/') || int.tryParse(slug) != null ? null : slug;
}
