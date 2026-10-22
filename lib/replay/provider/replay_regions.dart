import 'replay_source_info.dart';

/// Display names for the countries and languages the setup screen groups channels by. English is the fallback.
const _countryNames = <String, ({String en, String fr})>{
  replayInternational: (en: 'International', fr: 'International'),
  'AT': (en: 'Austria', fr: 'Autriche'),
  'AU': (en: 'Australia', fr: 'Australie'),
  'BE': (en: 'Belgium', fr: 'Belgique'),
  'BG': (en: 'Bulgaria', fr: 'Bulgarie'),
  'CA': (en: 'Canada', fr: 'Canada'),
  'CH': (en: 'Switzerland', fr: 'Suisse'),
  'CY': (en: 'Cyprus', fr: 'Chypre'),
  'CZ': (en: 'Czechia', fr: 'Tchéquie'),
  'DE': (en: 'Germany', fr: 'Allemagne'),
  'DK': (en: 'Denmark', fr: 'Danemark'),
  'EE': (en: 'Estonia', fr: 'Estonie'),
  'ES': (en: 'Spain', fr: 'Espagne'),
  'FI': (en: 'Finland', fr: 'Finlande'),
  'FR': (en: 'France', fr: 'France'),
  'GB': (en: 'United Kingdom', fr: 'Royaume-Uni'),
  'GR': (en: 'Greece', fr: 'Grèce'),
  'HR': (en: 'Croatia', fr: 'Croatie'),
  'HU': (en: 'Hungary', fr: 'Hongrie'),
  'IE': (en: 'Ireland', fr: 'Irlande'),
  'IS': (en: 'Iceland', fr: 'Islande'),
  'IT': (en: 'Italy', fr: 'Italie'),
  'JP': (en: 'Japan', fr: 'Japon'),
  'KR': (en: 'South Korea', fr: 'Corée du Sud'),
  'LT': (en: 'Lithuania', fr: 'Lituanie'),
  'LU': (en: 'Luxembourg', fr: 'Luxembourg'),
  'LV': (en: 'Latvia', fr: 'Lettonie'),
  'NL': (en: 'Netherlands', fr: 'Pays-Bas'),
  'NO': (en: 'Norway', fr: 'Norvège'),
  'NZ': (en: 'New Zealand', fr: 'Nouvelle-Zélande'),
  'PL': (en: 'Poland', fr: 'Pologne'),
  'PT': (en: 'Portugal', fr: 'Portugal'),
  'QA': (en: 'Qatar', fr: 'Qatar'),
  'RO': (en: 'Romania', fr: 'Roumanie'),
  'SE': (en: 'Sweden', fr: 'Suède'),
  'SG': (en: 'Singapore', fr: 'Singapour'),
  'SI': (en: 'Slovenia', fr: 'Slovénie'),
  'SK': (en: 'Slovakia', fr: 'Slovaquie'),
  'TR': (en: 'Türkiye', fr: 'Turquie'),
  'UA': (en: 'Ukraine', fr: 'Ukraine'),
  'US': (en: 'United States', fr: 'États-Unis'),
};

const _languageNames = <String, ({String en, String fr})>{
  'ar': (en: 'Arabic', fr: 'Arabe'),
  'bg': (en: 'Bulgarian', fr: 'Bulgare'),
  'ca': (en: 'Catalan', fr: 'Catalan'),
  'cs': (en: 'Czech', fr: 'Tchèque'),
  'cy': (en: 'Welsh', fr: 'Gallois'),
  'da': (en: 'Danish', fr: 'Danois'),
  'de': (en: 'German', fr: 'Allemand'),
  'el': (en: 'Greek', fr: 'Grec'),
  'en': (en: 'English', fr: 'Anglais'),
  'es': (en: 'Spanish', fr: 'Espagnol'),
  'et': (en: 'Estonian', fr: 'Estonien'),
  'fi': (en: 'Finnish', fr: 'Finnois'),
  'fr': (en: 'French', fr: 'Français'),
  'ga': (en: 'Irish', fr: 'Irlandais'),
  'hr': (en: 'Croatian', fr: 'Croate'),
  'hu': (en: 'Hungarian', fr: 'Hongrois'),
  'is': (en: 'Icelandic', fr: 'Islandais'),
  'it': (en: 'Italian', fr: 'Italien'),
  'ja': (en: 'Japanese', fr: 'Japonais'),
  'ko': (en: 'Korean', fr: 'Coréen'),
  'lt': (en: 'Lithuanian', fr: 'Lituanien'),
  'lv': (en: 'Latvian', fr: 'Letton'),
  'mi': (en: 'Māori', fr: 'Maori'),
  'nb': (en: 'Norwegian', fr: 'Norvégien'),
  'nl': (en: 'Dutch', fr: 'Néerlandais'),
  'no': (en: 'Norwegian', fr: 'Norvégien'),
  'pl': (en: 'Polish', fr: 'Polonais'),
  'pt': (en: 'Portuguese', fr: 'Portugais'),
  'ro': (en: 'Romanian', fr: 'Roumain'),
  'sk': (en: 'Slovak', fr: 'Slovaque'),
  'sl': (en: 'Slovenian', fr: 'Slovène'),
  'sv': (en: 'Swedish', fr: 'Suédois'),
  'tr': (en: 'Turkish', fr: 'Turc'),
  'uk': (en: 'Ukrainian', fr: 'Ukrainien'),
  'zh': (en: 'Chinese', fr: 'Chinois'),
};

/// The name of a country in [locale] ('fr' or anything else for English); the code itself when it is not listed.
String replayCountryName(String code, String locale) {
  final names = _countryNames[code];
  if (names == null) return code;
  return locale == 'fr' ? names.fr : names.en;
}

String replayLanguageName(String code, String locale) {
  final names = _languageNames[code];
  if (names == null) return code;
  return locale == 'fr' ? names.fr : names.en;
}

/// Countries that have at least one channel, for the location picker.
List<String> replayKnownCountries() => [
  for (final code in _countryNames.keys)
    if (code != replayInternational) code,
];
