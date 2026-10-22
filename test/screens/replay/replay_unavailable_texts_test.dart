import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/app_locale_utils.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/screens/replay/replay_country_grammar.dart';
import 'package:plezy/screens/replay/replay_unavailable_texts.dart';

import 'replay_detail_fixtures.dart';

const _belgium = ReplayViewerPlace(country: 'BE');

ReplayUnavailableTexts? _texts(MediaItem item, {ReplayViewerPlace place = _belgium}) => replayUnavailableTexts(
  item,
  place: place,
  language: LocaleSettings.currentLocale.languageCode,
  intlLocale: LocaleSettings.currentLocale.intlLocaleName,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fr');
  });

  tearDown(() => LocaleSettings.setLocale(AppLocale.en));

  group('in French', () {
    setUp(() => LocaleSettings.setLocale(AppLocale.fr));

    test('a geo-blocked episode says where the viewer is placed and why', () {
      final texts = _texts(replayItem('francetv:1', ReplayAvailability.geoBlocked, studio: 'France.tv'))!;
      expect(texts.notice, 'Réservé à la France. Plezy vous situe en Belgique.');
      expect(texts.dialogTitle, 'Réservé à la France');
      expect(
        texts.dialogBody,
        "France.tv bloque cet épisode hors de France. Plezy vous situe en Belgique, d'après votre connexion.",
      );
      expect(texts.offersLocationChange, isTrue);
    });

    test('a position chosen by hand is called a choice', () {
      final texts = _texts(
        replayItem('francetv:1', ReplayAvailability.geoBlocked, studio: 'France.tv'),
        place: const ReplayViewerPlace(country: 'BE', chosen: true),
      )!;
      expect(texts.dialogBody, endsWith("Plezy vous situe en Belgique, d'après votre choix."));
    });

    test('an unknown position leaves out the sentence about it', () {
      final texts = _texts(
        replayItem('francetv:1', ReplayAvailability.geoBlocked, studio: 'France.tv'),
        place: const ReplayViewerPlace(),
      )!;
      expect(texts.notice, 'Réservé à la France.');
      expect(texts.dialogBody, 'France.tv bloque cet épisode hors de France.');
    });

    test('a DRM title says Plezy cannot play it', () {
      final texts = _texts(
        replayItem('francetv:1', ReplayAvailability.drmProtected, kind: MediaKind.clip, studio: 'France.tv'),
      )!;
      expect(texts.notice, 'Protégé par DRM. Plezy ne sait pas lire cette vidéo.');
      expect(texts.dialogTitle, 'Vidéo protégée');
      expect(texts.dialogBody, 'France.tv protège cette vidéo par DRM et Plezy ne sait pas la lire.');
    });

    test('an expired title gives the day it was withdrawn', () {
      final item = replayItem(
        'arte:1',
        ReplayAvailability.expired,
        kind: MediaKind.clip,
        studio: 'ARTE',
        stamps: {replayAvailableUntilKey: DateTime(2026, 10, 12, 3).toIso8601String()},
      );
      final texts = _texts(item)!;
      expect(texts.notice, 'Expiré le 12 oct. 2026.');
      expect(texts.dialogTitle, 'Vidéo expirée');
      expect(texts.dialogBody, 'ARTE a retiré cette vidéo le 12 oct. 2026.');
    });

    test('an upcoming title gives the day and hour it goes online', () {
      final item = replayItem(
        'francetv:1',
        ReplayAvailability.upcoming,
        kind: MediaKind.clip,
        studio: 'France.tv',
        stamps: {replayAirsAtKey: DateTime(2026, 10, 30, 20, 55).toIso8601String()},
      );
      final texts = _texts(item)!;
      expect(texts.notice, 'Disponible le 30 oct. à 20 h 55.');
      expect(texts.dialogTitle, 'Disponible le 30 oct. à 20 h 55');
      expect(texts.dialogBody, 'France.tv met cette vidéo en ligne à cette date.');
    });

    test('an account-only title names the channel', () {
      final texts = _texts(
        replayItem('francetv:1', ReplayAvailability.loginRequired, kind: MediaKind.clip, studio: 'France.tv'),
      )!;
      expect(texts.dialogTitle, 'Compte France.tv requis');
      expect(texts.dialogBody, 'Connectez-vous pour lire cette vidéo ; la lecture démarre ensuite.');
      expect(texts.offersSignIn, isTrue);
    });
  });

  group('in English', () {
    test('a geo-blocked title says where the viewer is placed', () {
      final texts = _texts(replayItem('francetv:1', ReplayAvailability.geoBlocked, studio: 'France.tv'))!;
      expect(texts.notice, endsWith('Plezy places you in Belgium.'));
      expect(texts.dialogBody, contains('blocks this episode outside France.'));
    });

    test('a playable title has no texts', () {
      expect(_texts(replayItem('francetv:1', ReplayAvailability.playable)), isNull);
    });
  });

  group('country phrases', () {
    test('French places take the article of the country', () {
      expect(replayInCountry('BE', 'fr'), 'en Belgique');
      expect(replayInCountry('DE', 'fr'), 'en Allemagne');
      expect(replayInCountry('CA', 'fr'), 'au Canada');
      expect(replayInCountry('NL', 'fr'), 'aux Pays-Bas');
      expect(replayInCountry('CY', 'fr'), 'à Chypre');
    });

    test('French "outside" phrases take de, d\', du or des', () {
      expect(replayOutsideCountry('FR', 'fr'), 'de France');
      expect(replayOutsideCountry('DE', 'fr'), "d'Allemagne");
      expect(replayOutsideCountry('CA', 'fr'), 'du Canada');
      expect(replayOutsideCountry('US', 'fr'), 'des États-Unis');
    });

    test('other languages use the plain name', () {
      expect(replayInCountry('BE', 'en'), 'Belgium');
      expect(replayOutsideCountry('CA', 'en'), 'Canada');
    });
  });
}
