import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_settings.dart';

const _lithuanian = ['lt'];
const _multilingual = ['fr', 'de', 'en'];

void main() {
  test('A stored record survives a round trip', () {
    const settings = ReplaySuggestionSettings(
      enabled: false,
      languages: {'fr', 'en'},
      channels: {'rtlplay': false},
      onlyChosenChannels: true,
      chosenRows: {
        'arte': {'docs', 'magazines'},
      },
      mutedRows: {'arte:news'},
      rowsPerChannel: 3,
    );

    final again = ReplaySuggestionSettings.fromJson(settings.toJson());

    expect(again.toJson(), settings.toJson());
  });

  test('A malformed record falls back to the defaults', () {
    final settings = ReplaySuggestionSettings.fromJson({
      'enabled': 'yes',
      'languages': 'fr',
      'channels': {'a': 1, 'b': true},
      'rowsPerChannel': 99,
    });

    expect(settings.enabled, isTrue);
    expect(settings.languages, isEmpty);
    expect(settings.channels, {'b': true});
    expect(settings.rowsPerChannel, ReplaySuggestionSettings.maxRowsPerChannel);
  });

  test('Automatic languages decide until the viewer picks some', () {
    const automatic = {'fr'};

    expect(const ReplaySuggestionSettings().offers('arte', _multilingual, {'en'}), isTrue);
    expect(const ReplaySuggestionSettings().offers('arte', _multilingual, automatic), isTrue);
    expect(const ReplaySuggestionSettings().offers('lrt', _lithuanian, automatic), isFalse);
    expect(const ReplaySuggestionSettings(languages: {'lt'}).offers('lrt', _lithuanian, automatic), isTrue);
    expect(const ReplaySuggestionSettings(languages: {'lt'}).offers('arte', _multilingual, automatic), isFalse);
  });

  test('Only chosen channels: a channel never chosen stays off in any language', () {
    const settings = ReplaySuggestionSettings(onlyChosenChannels: true, channels: {'arte': true});

    expect(settings.offers('arte', _multilingual, {'fr'}), isTrue);
    expect(settings.offers('auvio', const ['fr'], {'fr'}), isFalse);
    expect(settings.offers('newchannel', const ['en'], {'en'}), isFalse);
  });
}
