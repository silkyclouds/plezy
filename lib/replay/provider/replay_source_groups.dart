import 'replay_regions.dart';
import 'replay_source_info.dart';

/// The channels of one language within a country.
class ReplayLanguageGroup {
  final String language;
  final List<ReplaySourceInfo> sources;

  const ReplayLanguageGroup(this.language, this.sources);
}

/// The channels of one country, split by language, as the setup screen lists them.
class ReplayCountryGroup {
  final String country;
  final List<ReplayLanguageGroup> languages;

  const ReplayCountryGroup(this.country, this.languages);

  List<ReplaySourceInfo> get sources => [for (final group in languages) ...group.sources];
}

/// Files [infos] under country and main language. The viewer's country comes first, the others follow alphabetically
/// by their name in [locale], and international channels come last. A country's most common language leads.
List<ReplayCountryGroup> groupReplaySources(
  Iterable<ReplaySourceInfo> infos, {
  String? viewerCountry,
  String locale = 'en',
}) {
  final byCountry = <String, List<ReplaySourceInfo>>{};
  for (final info in infos) {
    byCountry.putIfAbsent(info.country, () => []).add(info);
  }
  final countries = byCountry.keys.toList()
    ..sort((a, b) => _rank(a, viewerCountry, locale).compareTo(_rank(b, viewerCountry, locale)));
  return [for (final country in countries) ReplayCountryGroup(country, _languages(byCountry[country]!))];
}

String _rank(String country, String? viewerCountry, String locale) {
  if (country == viewerCountry) return '0';
  if (country == replayInternational) return '2';
  return '1${replayCountryName(country, locale).toLowerCase()}';
}

List<ReplayLanguageGroup> _languages(List<ReplaySourceInfo> sources) {
  final byLanguage = <String, List<ReplaySourceInfo>>{};
  for (final info in sources) {
    byLanguage.putIfAbsent(info.mainLanguage, () => []).add(info);
  }
  final languages = byLanguage.keys.toList()
    ..sort((a, b) {
      final byCount = byLanguage[b]!.length.compareTo(byLanguage[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return [
    for (final language in languages)
      ReplayLanguageGroup(
        language,
        [...byLanguage[language]!]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ),
  ];
}
