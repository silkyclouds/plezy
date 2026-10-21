/// Lowercases and strips accents and punctuation so "L'amour est dans le pré" matches "amour pre".
String m6plusFold(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at >= 0 ? to[at] : char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Programmes whose title contains every word of [query], titles that start with it first.
/// The catalogue API has no search route, so the full programme list is filtered here.
List<Map<String, dynamic>> m6plusSearchPrograms(List<Map<String, dynamic>> programs, String query, {int limit = 40}) {
  final folded = m6plusFold(query);
  if (folded.isEmpty) return const [];
  final words = folded.split(' ');
  final scored = <(int, int, Map<String, dynamic>)>[];
  for (var i = 0; i < programs.length; i++) {
    final title = m6plusFold(programs[i]['title'] as String? ?? '');
    if (!words.every(title.contains)) continue;
    final rank = title.startsWith(folded)
        ? 0
        : (words.every((w) => title.startsWith(w) || title.contains(' $w')) ? 1 : 2);
    scored.add((rank, i, programs[i]));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final entry in scored.take(limit)) entry.$3];
}
