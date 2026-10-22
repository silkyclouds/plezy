import '../../../replay/provider/replay_regions.dart';

/// French needs the article of a country to say "de Belgique", "d'Allemagne", "du Canada", "depuis la France".
enum _Article { none, feminine, feminineVowel, masculine, plural }

const _articles = <String, _Article>{
  'AT': _Article.feminineVowel,
  'AU': _Article.feminineVowel,
  'BE': _Article.feminine,
  'BG': _Article.feminine,
  'CA': _Article.masculine,
  'CH': _Article.feminine,
  'CY': _Article.feminine,
  'CZ': _Article.feminine,
  'DE': _Article.feminineVowel,
  'DK': _Article.masculine,
  'EE': _Article.feminineVowel,
  'ES': _Article.feminineVowel,
  'FI': _Article.feminine,
  'FR': _Article.feminine,
  'GB': _Article.masculine,
  'GR': _Article.feminine,
  'HR': _Article.feminine,
  'HU': _Article.feminine,
  'IE': _Article.feminineVowel,
  'IS': _Article.feminineVowel,
  'IT': _Article.feminineVowel,
  'JP': _Article.masculine,
  'KR': _Article.feminine,
  'LT': _Article.feminine,
  'LU': _Article.masculine,
  'LV': _Article.feminine,
  'NL': _Article.plural,
  'NO': _Article.feminine,
  'NZ': _Article.feminine,
  'PL': _Article.feminine,
  'PT': _Article.masculine,
  'QA': _Article.masculine,
  'RO': _Article.feminine,
  'SE': _Article.feminine,
  'SG': _Article.none,
  'SI': _Article.feminine,
  'SK': _Article.feminine,
  'TR': _Article.feminine,
  'UA': _Article.feminineVowel,
  'US': _Article.plural,
};

/// The country after "from" ("la Belgique", "l'Allemagne"); the plain name outside French.
String replayCountryFrom(String code, String locale) {
  final name = replayCountryName(code, locale);
  if (locale != 'fr') return name;
  return switch (_articles[code] ?? _Article.none) {
    _Article.feminine => 'la $name',
    _Article.feminineVowel => "l'$name",
    _Article.masculine => 'le $name',
    _Article.plural => 'les $name',
    _Article.none => name,
  };
}

/// The country after "of" ("de Belgique", "d'Allemagne", "du Canada"); the plain name outside French.
String replayCountryOf(String code, String locale) {
  final name = replayCountryName(code, locale);
  if (locale != 'fr') return name;
  return switch (_articles[code] ?? _Article.none) {
    _Article.feminineVowel => "d'$name",
    _Article.masculine => 'du $name',
    _Article.plural => 'des $name',
    _Article.feminine || _Article.none => 'de $name',
  };
}

/// A channel name after "of" in French ("d'Auvio", "de France.tv"); the plain name elsewhere.
String replayChannelOf(String name, String locale) {
  if (locale != 'fr') return name;
  final first = name.isEmpty ? '' : name[0].toLowerCase();
  return 'aeiouyhàâéèêëîïôöùûü'.contains(first) && first.isNotEmpty ? "d'$name" : 'de $name';
}
