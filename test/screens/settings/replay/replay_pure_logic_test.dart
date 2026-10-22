import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/provider/replay_source_groups.dart';
import 'package:plezy/replay/provider/replay_source_info.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_settings.dart';
import 'package:plezy/screens/settings/replay/replay_channel_filter.dart';
import 'package:plezy/screens/settings/replay/replay_country_drawer.dart';
import 'package:plezy/screens/settings/replay/replay_country_phrases.dart';
import 'package:plezy/screens/settings/replay/replay_default_sources.dart';
import 'package:plezy/screens/settings/replay/replay_suggestion_rows.dart';
import 'package:plezy/screens/settings/replay/replay_suggestion_view.dart';

ReplaySourceInfo _info(String id, String country, List<String> languages, {Set<String> availableIn = const {}}) =>
    ReplaySourceInfo(
      id: id,
      name: id,
      support: ReplayPlaybackSupport.clear,
      country: country,
      languages: languages,
      availableIn: availableIn,
    );

void main() {
  group('country phrases', () {
    test('French writes the article of the country', () {
      expect(replayCountryFrom('BE', 'fr'), 'la Belgique');
      expect(replayCountryFrom('DE', 'fr'), "l'Allemagne");
      expect(replayCountryOf('CA', 'fr'), 'du Canada');
      expect(replayCountryOf('DE', 'fr'), "d'Allemagne");
      expect(replayCountryOf('US', 'fr'), 'des États-Unis');
      expect(replayCountryOf('FR', 'fr'), 'de France');
    });

    test('English keeps the plain name', () {
      expect(replayCountryFrom('BE', 'en'), 'Belgium');
      expect(replayCountryOf('BE', 'en'), 'Belgium');
    });

    test('French elides "de" before a vowel in a channel name', () {
      expect(replayChannelOf('Auvio', 'fr'), "d'Auvio");
      expect(replayChannelOf('ARTE', 'fr'), "d'ARTE");
      expect(replayChannelOf('France.tv', 'fr'), 'de France.tv');
    });
  });

  group('default sources', () {
    final infos = [
      _info('auvio', 'BE', ['fr']),
      _info('francetv', 'FR', ['fr'], availableIn: {'FR'}),
      _info('arte', 'FR', ['fr'], availableIn: {'FR', 'BE'}),
      _info('cbc', 'CA', ['en'], availableIn: {'CA'}),
    ];

    test('the own country is on, and so is a foreign channel that plays from there', () {
      expect(defaultReplaySources(infos, 'BE'), {'auvio', 'arte'});
    });

    test('without a country every channel is on', () {
      expect(defaultReplaySources(infos, null), {'auvio', 'francetv', 'arte', 'cbc'});
    });
  });

  group('search filter', () {
    final groups = groupReplaySources([
      _info('rtl', 'BE', ['fr']),
      _info('rtbf', 'BE', ['fr']),
      _info('ard', 'DE', ['de']),
    ]);

    test('keeps only the channels whose name contains the text', () {
      final found = filterReplayGroups(groups, 'RT');
      expect(found.map((g) => g.country), ['BE']);
      expect(found.single.sources.map((s) => s.id), ['rtbf', 'rtl']);
    });

    test('ignores accents and drops countries without a match', () {
      final accented = filterReplayGroups(
        groupReplaySources([
          ReplaySourceInfo(
            id: 'ruv',
            name: 'RÚV',
            support: ReplayPlaybackSupport.clear,
            country: 'IS',
            languages: ['is'],
          ),
        ]),
        'ruv',
      );
      expect(accented.single.country, 'IS');
      expect(filterReplayGroups(groups, 'zz'), isEmpty);
    });

    test('one character does not count as a search', () {
      expect(isReplaySearch('r'), isFalse);
      expect(isReplaySearch(' rt '), isTrue);
    });
  });

  test('the language of the interface leads inside a country', () {
    final group = groupReplaySources([
      _info('a', 'BE', ['nl']),
      _info('b', 'BE', ['nl']),
      _info('c', 'BE', ['fr']),
    ]).single;
    expect(orderedLanguageGroups(group, 'fr').map((l) => l.language), ['fr', 'nl']);
    expect(orderedLanguageGroups(group, 'en').map((l) => l.language), ['nl', 'fr']);
  });

  group('channel stance', () {
    final french = _info('arte', 'FR', ['fr']);
    final lithuanian = _info('lrt', 'LT', ['lt']);

    test('the language rule decides without a choice', () {
      const settings = ReplaySuggestionSettings();
      final on = channelStance(settings, french, {'fr'});
      final off = channelStance(settings, lithuanian, {'fr'});
      expect([on.offered, on.reason], [true, ReplayChannelReason.ruleOn]);
      expect([off.offered, off.reason], [false, ReplayChannelReason.ruleOff]);
    });

    test('an explicit choice beats the rule both ways', () {
      const settings = ReplaySuggestionSettings(channels: {'arte': false, 'lrt': true});
      expect(channelStance(settings, french, {'fr'}).reason, ReplayChannelReason.userOff);
      expect(channelStance(settings, lithuanian, {'fr'}).offered, isTrue);
    });

    test('a manual language list replaces the automatic one', () {
      const settings = ReplaySuggestionSettings(languages: {'lt'});
      expect(channelStance(settings, lithuanian, {'fr'}).offered, isTrue);
      expect(channelStance(settings, french, {'fr'}).offered, isFalse);
    });

    test('the last followed language cannot be unticked', () {
      expect(toggledLanguages(const ReplaySuggestionSettings(), {'fr'}, 'fr'), isNull);
      expect(toggledLanguages(const ReplaySuggestionSettings(), {'fr'}, 'nl'), {'fr', 'nl'});
    });
  });

  group('rows of a channel', () {
    const ids = ['docs', 'series', 'info'];

    test('by default every row is ticked and new rows are included', () {
      final selection = currentRowSelection(const ReplaySuggestionSettings(), 'auvio', ids);
      expect(selection.includeNew, isTrue);
      expect(selection.ticked, ids.toSet());
    });

    test('unticking rows with new rows included mutes them', () {
      final saved = withRowSelection(
        const ReplaySuggestionSettings(),
        'auvio',
        ids,
        const ReplayRowSelection(includeNew: true, ticked: {'docs', 'series'}),
      );
      expect(saved.mutedRows, {'auvio:info'});
      expect(saved.chosenRows, isEmpty);
    });

    test('switching new rows off keeps only the ticked ones and drops mutes', () {
      final saved = withRowSelection(
        const ReplaySuggestionSettings(mutedRows: {'auvio:info', 'arte:x'}),
        'auvio',
        ids,
        const ReplayRowSelection(includeNew: false, ticked: {'docs'}),
      );
      expect(saved.chosenRows['auvio'], {'docs'});
      expect(saved.mutedRows, {'arte:x'});
      expect(currentRowSelection(saved, 'auvio', ids).includeNew, isFalse);
    });
  });
}
