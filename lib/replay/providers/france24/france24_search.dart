import 'france24_models.dart';

const _folded = {
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
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
  '’': "'",
};

/// Lowercases and strips French accents so "Element" finds "Élément".
String france24Fold(String text) {
  final lower = text.toLowerCase();
  return lower.split('').map((c) => _folded[c] ?? c).join();
}

/// The programmes whose title contains every word of [query].
///
/// The broadcaster has no search endpoint, so the short programme list is filtered here.
List<France24Programme> france24MatchProgrammes(Iterable<France24Programme> programmes, String query) {
  final words = france24Fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final programme in programmes)
      if (words.every(france24Fold(programme.title).contains)) programme,
  ];
}
