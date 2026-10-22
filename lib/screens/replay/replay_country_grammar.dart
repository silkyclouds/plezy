import '../../replay/provider/replay_regions.dart';

/// How a French country name takes its prepositions: en France, d'Allemagne, au Canada, aux Pays-Bas, à Chypre.
enum _Article { feminine, vowel, masculine, plural, none }

const _vowelCountries = {'AT', 'AU', 'DE', 'EE', 'ES', 'FI', 'IE', 'IS', 'IT', 'UA'};
const _masculineCountries = {'CA', 'DK', 'GB', 'JP', 'LU', 'PT', 'QA'};
const _pluralCountries = {'NL', 'US'};
const _bareCountries = {'CY', 'SG'};

_Article _articleOf(String code) {
  if (_vowelCountries.contains(code)) return _Article.vowel;
  if (_masculineCountries.contains(code)) return _Article.masculine;
  if (_pluralCountries.contains(code)) return _Article.plural;
  if (_bareCountries.contains(code)) return _Article.none;
  return _Article.feminine;
}

/// Where the viewer is, as a place: "en Belgique" in French, "Belgium" elsewhere.
String replayInCountry(String code, String language) {
  final name = replayCountryName(code, language);
  if (language != 'fr') return name;
  return switch (_articleOf(code)) {
    _Article.feminine || _Article.vowel => 'en $name',
    _Article.masculine => 'au $name',
    _Article.plural => 'aux $name',
    _Article.none => 'à $name',
  };
}

/// A country after "outside": "de France", "d'Allemagne", "du Canada" in French, the plain name elsewhere.
String replayOutsideCountry(String code, String language) {
  final name = replayCountryName(code, language);
  if (language != 'fr') return name;
  return switch (_articleOf(code)) {
    _Article.feminine || _Article.none => 'de $name',
    _Article.vowel => "d'$name",
    _Article.masculine => 'du $name',
    _Article.plural => 'des $name',
  };
}
