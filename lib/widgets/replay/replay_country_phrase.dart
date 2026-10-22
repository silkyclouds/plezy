import '../../replay/provider/replay_regions.dart';

/// "Only in France" without a preposition rule in English, "Réservé à la France" with one in French.
///
/// French needs the article to agree with the country, so each listed country carries its own.
String replayCountryPhrase(String code, String languageCode) {
  if (languageCode != 'fr') return replayCountryName(code, languageCode);
  return '${_frenchPreposition(code)}${replayCountryName(code, 'fr')}';
}

String _frenchPreposition(String code) => switch (code) {
  'BE' || 'BG' || 'CH' || 'CZ' || 'FR' || 'PL' || 'RO' || 'SE' || 'SI' || 'SK' || 'TR' || 'KR' || 'NZ' => 'à la ',
  'AT' ||
  'AU' ||
  'DE' ||
  'EE' ||
  'ES' ||
  'FI' ||
  'GR' ||
  'HR' ||
  'HU' ||
  'IE' ||
  'IS' ||
  'IT' ||
  'LT' ||
  'LV' ||
  'NO' ||
  'UA' => "à l'",
  'CA' || 'DK' || 'JP' || 'LU' || 'PT' || 'QA' || 'GB' => 'au ',
  'NL' || 'US' => 'aux ',
  _ => 'à ',
};
