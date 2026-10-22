import '../../model/replay_title.dart';
import 'aljazeera_text.dart';

const _folded = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ó': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  '’': '',
  "'": '',
};

/// Lowercases and strips accents and apostrophes so "lets focus" finds "Let’s Focus".
String aljazeeraFold(String text) => aljazeeraText(text).toLowerCase().split('').map((c) => _folded[c] ?? c).join();

/// The titles that contain every word of [query] in their title or synopsis.
///
/// The site's own search is closed to anonymous callers, so the programme list and the episodes already
/// seen are filtered here instead.
List<ReplayTitle> aljazeeraMatch(Iterable<ReplayTitle> titles, String query) {
  final words = aljazeeraFold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final title in titles)
      if (_matches(title, words)) title,
  ];
}

bool _matches(ReplayTitle title, List<String> words) {
  final haystack = aljazeeraFold('${title.title} ${title.showTitle ?? ''} ${title.summary ?? ''}');
  return words.every(haystack.contains);
}

/// The most recent episodes and clips the app has listed, kept so that search can reach beyond the programme list.
class AljazeeraSeenTitles {
  static const _limit = 600;

  final Map<Object, ReplayTitle> _seen = {};

  void remember(Iterable<ReplayTitle> titles) {
    for (final title in titles) {
      if (!title.isPlayable) continue;
      _seen.remove(title.ref);
      _seen[title.ref] = title;
    }
    while (_seen.length > _limit) {
      _seen.remove(_seen.keys.first);
    }
  }

  List<ReplayTitle> get all => _seen.values.toList(growable: false);
}
