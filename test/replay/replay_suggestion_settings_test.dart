import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/suggestions/replay_suggestion_settings.dart';

const _lithuanian = ReplaySource(id: 'lrt', name: 'LRT', language: 'lt', support: ReplayPlaybackSupport.clear);
const _french = ReplaySource(id: 'arte', name: 'ARTE', language: 'fr', support: ReplayPlaybackSupport.clear);

void main() {
  test('A stored record survives a round trip', () {
    const settings = ReplaySuggestionSettings(
      enabled: false,
      languages: {'fr', 'en'},
      channels: {'rtlplay': false},
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

    expect(const ReplaySuggestionSettings().offers(_french, automatic), isTrue);
    expect(const ReplaySuggestionSettings().offers(_lithuanian, automatic), isFalse);
    expect(const ReplaySuggestionSettings(languages: {'lt'}).offers(_lithuanian, automatic), isTrue);
    expect(const ReplaySuggestionSettings(languages: {'lt'}).offers(_french, automatic), isFalse);
  });
}
