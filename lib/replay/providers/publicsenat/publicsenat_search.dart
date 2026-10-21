const _folded = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'œ': 'oe',
  'æ': 'ae',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  '’': "'",
};

/// Lower case without accents, so "senat" finds "Sénat".
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_folded[char] ?? char);
  }
  return out.toString();
}

/// Whether every word of [query] appears in at least one of [fields].
bool matchesQuery(String query, Iterable<String?> fields) {
  final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final haystack = fields.whereType<String>().map(foldForSearch).join(' ');
  return words.isNotEmpty && words.every(haystack.contains);
}
