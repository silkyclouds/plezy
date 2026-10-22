import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/provider/replay_source_groups.dart';
import 'package:plezy/replay/provider/replay_source_info.dart';

ReplaySourceInfo _info(String id, String country, List<String> languages) => ReplaySourceInfo(
  id: id,
  name: id.toUpperCase(),
  support: ReplayPlaybackSupport.clear,
  country: country,
  languages: languages,
);

void main() {
  final infos = [
    _info('rts', 'CH', ['fr']),
    _info('bbc', 'GB', ['en']),
    _info('s4c', 'GB', ['cy']),
    _info('itv', 'GB', ['en']),
    _info('dw', replayInternational, ['en']),
    _info('auvio', 'BE', ['fr']),
  ];

  test('the viewer\'s country leads, countries follow by name, international channels close the list', () {
    final groups = groupReplaySources(infos, viewerCountry: 'GB');
    expect([for (final g in groups) g.country], ['GB', 'BE', 'CH', replayInternational]);
  });

  test('without a known country the countries are simply alphabetical', () {
    final groups = groupReplaySources(infos);
    expect([for (final g in groups) g.country], ['BE', 'CH', 'GB', replayInternational]);
  });

  test('a country is split by main language, the most common language first, channels by name', () {
    final gb = groupReplaySources(infos, viewerCountry: 'GB').first;
    expect([for (final l in gb.languages) l.language], ['en', 'cy']);
    expect([for (final s in gb.languages.first.sources) s.id], ['bbc', 'itv']);
  });

  test('names are ordered in the language of the display', () {
    // Royaume-Uni sorts before Suisse, where the English names put Switzerland before the United Kingdom.
    final groups = groupReplaySources(infos, locale: 'fr');
    expect([for (final g in groups) g.country], ['BE', 'GB', 'CH', replayInternational]);
  });
}
