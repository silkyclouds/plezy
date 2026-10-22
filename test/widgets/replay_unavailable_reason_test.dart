import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/widgets/replay/replay_unavailable_overlay.dart';
import 'package:plezy/widgets/replay/replay_unavailable_reason.dart';

import '../test_helpers/media_items.dart';

MediaItem _item(String id, ReplayAvailability availability, {Map<String, Object?> stamps = const {}}) {
  return testMediaItem(
    id: id,
    backend: MediaBackend.replay,
    title: 'Titre',
    raw: {replayAvailabilityKey: availability.name, ...stamps},
  );
}

String? _reason(MediaItem item) => replayUnavailableReasonOf(item)?.shortReason;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fr');
  });

  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  group('in French', () {
    setUp(() => LocaleSettings.setLocale(AppLocale.fr));

    test('a geo-blocked France.tv title is reserved to France', () {
      expect(_reason(_item('francetv:a', ReplayAvailability.geoBlocked)), 'Réservé à la France');
    });

    test('the preposition follows the country of the broadcaster', () {
      expect(_reason(_item('rtlplay:a', ReplayAvailability.geoBlocked)), 'Réservé à la Belgique');
      expect(_reason(_item('pbs:a', ReplayAvailability.geoBlocked)), 'Réservé aux États-Unis');
      expect(_reason(_item('dw:a', ReplayAvailability.geoBlocked)), "Réservé à l'Allemagne");
    });

    test('an expired title gives the day it was withdrawn', () {
      final item = _item(
        'arte:a',
        ReplayAvailability.expired,
        stamps: {replayAvailableUntilKey: DateTime(2026, 10, 12, 3).toIso8601String()},
      );
      expect(_reason(item), 'Expiré le 12 oct.');
    });

    test('an upcoming title gives the day and the time it goes online', () {
      final item = _item(
        'francetv:a',
        ReplayAvailability.upcoming,
        stamps: {replayAirsAtKey: DateTime(2026, 10, 30, 20, 55).toIso8601String()},
      );
      expect(_reason(item), 'Le 30 oct. à 20 h 55');
    });

    test('a full hour is written without minutes', () {
      final item = _item(
        'francetv:a',
        ReplayAvailability.upcoming,
        stamps: {replayAirsAtKey: DateTime(2026, 10, 30, 22).toIso8601String()},
      );
      expect(_reason(item), 'Le 30 oct. à 22 h');
    });

    test('the other cases use their plain wording', () {
      expect(_reason(_item('arte:a', ReplayAvailability.drmProtected)), 'Protégé par DRM');
      expect(_reason(_item('arte:a', ReplayAvailability.loginRequired)), 'Compte requis');
      expect(_reason(_item('arte:a', ReplayAvailability.timeSlotRestricted)), 'Plage horaire');
    });
  });

  group('in English', () {
    test('a geo-blocked title names the country it is reserved to', () {
      expect(_reason(_item('francetv:a', ReplayAvailability.geoBlocked)), 'Only in France');
    });

    test('a worldwide broadcaster falls back to the generic wording', () {
      expect(_reason(_item('ted:a', ReplayAvailability.geoBlocked)), 'Not available in your country');
    });

    test('dates missing from the title leave the short wording', () {
      expect(_reason(_item('arte:a', ReplayAvailability.expired)), 'Expired');
      expect(_reason(_item('arte:a', ReplayAvailability.upcoming)), 'Not available yet');
    });
  });

  group('which items get a reason', () {
    test('a playable title has none', () {
      expect(replayUnavailableReasonOf(_item('arte:a', ReplayAvailability.playable)), isNull);
      expect(replayUnavailableReasonOf(_item('arte:a', ReplayAvailability.unknown)), isNull);
    });

    test('an item from a media server has none', () {
      final plex = testMediaItem(id: 'x', raw: {replayAvailabilityKey: ReplayAvailability.geoBlocked.name});
      expect(replayUnavailableReasonOf(plex), isNull);
    });

    test('each case has its own pictogram', () {
      final icons = {
        for (final a in ReplayAvailability.values)
          if (replayUnavailableReasonOf(_item('arte:a', a)) case final reason?) reason.icon,
      };
      expect(icons.length, 6);
    });
  });

  group('the dates stamped by the mapper', () {
    const source = ReplaySource(id: 'fake', name: 'Fake TV', language: 'fr', support: ReplayPlaybackSupport.clear);

    test('an item carries when it expires and when it airs', () {
      final until = DateTime(2026, 10, 12, 3);
      final airs = DateTime(2026, 10, 1, 20, 55);
      final item = const ReplayMapper(serverId: 'replay', source: source).item(
        ReplayTitle(
          ref: const ReplayRef('fake', 'a'),
          kind: ReplayKind.movie,
          title: 'A',
          availableUntil: until,
          airDate: airs,
        ),
      );

      final dates = replayDatesOf(item);
      expect(dates.availableUntil, until);
      expect(dates.airsAt, airs);
    });

    test('an item without dates reads back none', () {
      final item = const ReplayMapper(
        serverId: 'replay',
        source: source,
      ).item(const ReplayTitle(ref: ReplayRef('fake', 'a'), kind: ReplayKind.movie, title: 'A'));

      expect(replayDatesOf(item), (availableUntil: null, airsAt: null));
    });
  });

  group('the grey of the artwork', () {
    test('every channel gets the same luminance scaled by the brightness', () {
      final m = replayGreyMatrix(0.45);

      expect(m.sublist(0, 5), m.sublist(5, 10));
      expect(m.sublist(5, 10), m.sublist(10, 15));
      expect(m[0] + m[1] + m[2], closeTo(0.45, 1e-9));
      expect(m.sublist(15), [0, 0, 0, 1, 0]);
    });

    test('the focused card is lighter than the resting one', () {
      expect(ReplayUnavailableShade.focusBrightness, greaterThan(ReplayUnavailableShade.restBrightness));
      expect(ReplayUnavailableShade.restBrightness, 0.45);
      expect(ReplayUnavailableShade.focusBrightness, 0.70);
    });
  });
}
