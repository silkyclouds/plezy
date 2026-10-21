import '../../model/replay_title.dart';
import 'francetv_mapper.dart';

/// Programmes and playable videos of a search answer, best title match first.
///
/// The broadcaster's own ranking is loose (an exact programme name can come fourth), so titles
/// that equal the query are moved up, then the ones that start with it, then the ones that contain it.
/// Collections, events and clips are left out because the app cannot open them.
List<ReplayTitle> franceTvSearchResults(Map<String, dynamic> page, String query, FranceTvMapper mapper) {
  final rows = page['collections'];
  if (rows is! List) return const [];
  final found = <ReplayTitle>[];
  final seen = <String>{};
  for (final row in rows.whereType<Map<String, dynamic>>()) {
    final type = row['type'];
    if (type != 'playlist_program' && type != 'playlist_video') continue;
    for (final title in mapper.titles(row['items'] as List? ?? const [])) {
      if (seen.add(title.ref.toString())) found.add(title);
    }
  }

  final wanted = _normalise(query);
  final scored = [for (var i = 0; i < found.length; i++) (title: found[i], score: _score(found[i], wanted), order: i)];
  scored.sort((a, b) => a.score != b.score ? a.score.compareTo(b.score) : a.order.compareTo(b.order));
  return [for (final entry in scored) entry.title];
}

int _score(ReplayTitle title, String wanted) {
  final name = _normalise(title.title);
  if (name == wanted) return 0;
  if (name.startsWith(wanted)) return 1;
  return name.contains(wanted) ? 2 : 3;
}

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'œ': 'oe',
};

String _normalise(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
