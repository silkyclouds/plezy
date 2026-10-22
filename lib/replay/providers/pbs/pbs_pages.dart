import 'pbs_api.dart';
import 'pbs_flight.dart';

/// A show's own page: the show record, its seasons and its stand-alone specials.
class PbsShowPage {
  final Map<String, dynamic> show;
  final List<Map<String, dynamic>> seasons;
  final List<Map<String, dynamic>> specials;

  const PbsShowPage({required this.show, required this.seasons, required this.specials});
}

/// One titled row of shows on a genre page or the home page.
class PbsShowRow {
  final String title;
  final List<Map<String, dynamic>> shows;

  const PbsShowRow(this.title, this.shows);
}

/// A genre page: its rows in page order, and every distinct show on it.
class PbsGenrePage {
  final List<PbsShowRow> rows;
  final List<Map<String, dynamic>> shows;

  const PbsGenrePage(this.rows, this.shows);
}

/// Reads the website pages that have no JSON route (a show's seasons, the genre pages) and keeps the result.
class PbsPages {
  static const _showTtl = Duration(minutes: 5);
  static const _genreTtl = Duration(minutes: 30);

  final PbsApi _api;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Object? value})> _kept = {};

  PbsPages(this._api, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Null when PBS has no such show or the page does not hold a show record.
  Future<PbsShowPage?> show(String slug) => _remember('show/$slug', _showTtl, () async {
    final html = await _api.page('/show/$slug/');
    return html == null ? null : parsePbsShowPage(html, slug);
  });

  Future<PbsGenrePage> genre(String genreId) => _remember('explore/$genreId', _genreTtl, () async {
    final html = await _api.page('/explore/$genreId/');
    return html == null ? const PbsGenrePage([], []) : parsePbsListingPage(html);
  });

  /// The rows of the site's front page.
  Future<PbsGenrePage> front() => _remember('front', _genreTtl, () async {
    final html = await _api.page('/');
    return html == null ? const PbsGenrePage([], []) : parsePbsListingPage(html);
  });

  Future<T> _remember<T>(String key, Duration ttl, Future<T> Function() load) async {
    final hit = _kept[key];
    if (hit != null && _now().difference(hit.at) < ttl) return hit.value as T;
    final value = await load();
    _kept[key] = (at: _now(), value: value);
    return value;
  }
}

/// Reads a show page. The record of the requested show is the fullest one with its slug: pages also carry
/// stripped copies and other shows.
PbsShowPage? parsePbsShowPage(String html, String slug) {
  final values = pbsFlightValues(html);
  final records = [
    for (final show in pbsItems(values, 'show'))
      if (show['slug'] == slug) show,
  ]..sort((a, b) => b.length.compareTo(a.length));
  if (records.isEmpty) return null;

  final seasons = <String, Map<String, dynamic>>{};
  for (final season in pbsItems(values, 'season')) {
    if (season['ordinal'] is num) seasons.putIfAbsent(season['cid'] as String, () => season);
  }
  final ordered = seasons.values.toList()..sort((a, b) => (a['ordinal'] as num).compareTo(b['ordinal'] as num));
  return PbsShowPage(show: records.first, seasons: ordered, specials: _specials(values));
}

List<Map<String, dynamic>> _specials(List<Object?> values) {
  final found = <String, Map<String, dynamic>>{};
  for (final value in values) {
    pbsWalk(value, (object, _) {
      final list = object['specials'];
      if (list is! List) return;
      for (final item in list.whereType<Map<String, dynamic>>()) {
        if (item['item_type'] == 'video' && item['cid'] is String) found.putIfAbsent(item['cid'] as String, () => item);
      }
    });
  }
  return found.values.toList();
}

/// Reads a page made of rows of shows. Rows follow the order the page lays them out in.
PbsGenrePage parsePbsListingPage(String html) {
  final values = pbsFlightValues(html);
  final rows = <({int order, int index, PbsShowRow row})>[];
  final seenTitles = <String>{};
  for (final value in values) {
    pbsWalk(value, (object, key) {
      final title = object['title'];
      final shows = object['shows'];
      if (title is! String || shows is! List || !seenTitles.add(title)) return;
      final complete = [
        for (final show in shows.whereType<Map<String, dynamic>>())
          if (show['cid'] is String && show['slug'] is String) show,
      ];
      if (complete.isEmpty) return;
      rows.add((order: int.tryParse(key ?? '') ?? 1 << 20, index: rows.length, row: PbsShowRow(title, complete)));
    });
  }
  rows.sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.index.compareTo(b.index));

  final distinct = <String, Map<String, dynamic>>{};
  for (final show in pbsItems(values, 'show')) {
    final slug = show['slug'];
    if (slug is String) distinct.putIfAbsent(slug, () => show);
  }
  return PbsGenrePage([for (final r in rows) r.row], distinct.values.toList());
}
