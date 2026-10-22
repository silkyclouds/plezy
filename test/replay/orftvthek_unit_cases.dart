import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_credentials.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_ids.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_images.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_numbering.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_seasons.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_shows.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_text.dart';

import 'orftvthek_test_support.dart';

Map<String, dynamic> _episode(int id, String title, String date, {String? subHeadline}) => {
  'id': id,
  'title': title,
  'date': date,
  'sub_headline': ?subHeadline,
};

/// Pure functions: API settings, title markers, season grouping, numbering, artwork variants and refs.
void orfUnitCases() {
  group('ORF API settings', () {
    test('are read from the inline configuration of the page', () {
      final settings = parseOrfApiSettings(orfFixture('web_page.html'))!;
      expect(settings.baseUri.toString(), 'https://api-tvthek.orf.at/api/v4.3/');
      expect(settings.authorization, orfBasic(orfTestUser, orfTestPassword));
    });

    test('are read from a JSON-style configuration too', () {
      const page = '{"api":{"baseUrl":"https://api-tvthek.orf.at/api/v4.4","user":"u","password":"p"}}';
      final settings = parseOrfApiSettings(page)!;
      expect(settings.baseUri.toString(), 'https://api-tvthek.orf.at/api/v4.4/');
      expect(settings.authorization, 'Basic ${base64Encode(utf8.encode('u:p'))}');
    });

    test('never send credentials to a host outside orf.at', () {
      const page = 'config={public:{api:{baseUrl:"https://evil.example/api/",user:"u",password:"p"}}}';
      expect(parseOrfApiSettings(page)!.baseUri.host, 'api-tvthek.orf.at');
    });

    test('are null when the page carries no password', () {
      expect(parseOrfApiSettings('<html>nothing here</html>'), isNull);
      expect(parseOrfApiSettings('api:{baseUrl:"https://api-tvthek.orf.at/",user:"u"}'), isNull);
    });
  });

  group('ORF title markers', () {
    test('season and episode are read from the usual spellings', () {
      expect(orfTitleMarkers('Serie (S4/E3)'), (season: 4, episode: 3));
      expect(orfTitleMarkers('Serie S04E12'), (season: 4, episode: 12));
      expect(orfTitleMarkers('Serie Staffel 2, Folge 5'), (season: 2, episode: 5));
    });

    test('a counter in brackets is the episode number', () {
      expect(orfTitleMarkers('Soko Linz (7/10): Verstummt'), (season: null, episode: 7));
      expect(orfTitleMarkers('Yoga Magazin: Folge 284'), (season: null, episode: 284));
    });

    test('dates, scores and parts are not episode numbers', () {
      expect(orfTitleMarkers('ZIB 1 vom 19.10.2026'), (season: null, episode: null));
      expect(orfTitleMarkers('Spiel (3/2)'), (season: null, episode: null));
      expect(orfTitleMarkers('Schlumpf in die Zukunft Teil 2'), (season: null, episode: null));
    });

    test('a season is read from a sub-headline', () {
      expect(orfSeasonFromText('Staffel 3'), 3);
      expect(orfSeasonFromText('Kiwi Staffel 2'), 2);
      expect(orfSeasonFromText('ORF ON Extra'), isNull);
    });
  });

  group('ORF show identity', () {
    test('a numbered profile is a season of its show', () {
      expect(splitOrfSeasonTitle('Kiwi Staffel 2'), (show: 'Kiwi', season: 2));
      expect(splitOrfSeasonTitle('(T)Raumschiff Surprise - Periode 1'), (show: '(T)Raumschiff Surprise', season: 1));
      expect(splitOrfSeasonTitle('Die Croods: Der Familienbaum Staffel 1')?.show, 'Die Croods: Der Familienbaum');
    });

    test('other profiles are not split', () {
      expect(splitOrfSeasonTitle('Dok 1'), isNull);
      expect(splitOrfSeasonTitle('Staffel 1'), isNull);
      expect(splitOrfSeasonTitle('Kiwi'), isNull);
    });

    test('series keys ignore case, accents and punctuation', () {
      expect(orfSeriesKey('Das Wunder DU'), orfSeriesKey('Das Wunder Du'));
      expect(orfSeriesKey('Österreich - Die ganze Geschichte'), 'oesterreich-die-ganze-geschichte');
      expect(orfSeriesKey('(T)Raumschiff Surprise'), 't-raumschiff-surprise');
    });

    test('a numbered profile maps to a series ref, others to a profile ref', () {
      final kiwi = OrfShowIdentity.of(13898827, 'Kiwi Staffel 2');
      expect((kiwi.ref, kiwi.title, kiwi.season), (orfSeriesRef('kiwi'), 'Kiwi', 2));
      final zib = OrfShowIdentity.of(1203, 'ZIB 1');
      expect((zib.ref, zib.title, zib.season), (orfProfileRef(1203), 'ZIB 1', null));
    });
  });

  group('ORF episode numbering', () {
    test('without stated numbers the oldest broadcast is episode 1', () {
      final numbered = orfNumberEpisodes([
        _episode(3, 'C', '2026-05-15T20:00:00+02:00'),
        _episode(1, 'A', '2026-05-12T20:00:00+02:00'),
        _episode(2, 'B', '2026-05-13T20:00:00+02:00'),
      ]);
      expect([for (final n in numbered) (n.episode['id'], n.number)], [(1, 1), (2, 2), (3, 3)]);
    });

    test('episodes broadcast together keep the order of their ids', () {
      final numbered = orfNumberEpisodes([
        _episode(8, 'B', '2026-05-12T20:00:00+02:00'),
        _episode(7, 'A', '2026-05-12T20:00:00+02:00'),
      ]);
      expect([for (final n in numbered) n.episode['id']], [7, 8]);
    });

    test('stated numbers win and extras without one come last', () {
      final numbered = orfNumberEpisodes([
        _episode(9, 'Trailer', '2026-09-07T20:15:00+02:00'),
        _episode(12, 'Show (2/3): B', '2026-09-15T20:15:00+02:00'),
        _episode(11, 'Show (1/3): A', '2026-09-08T20:15:00+02:00'),
        _episode(13, 'Show (3/3): C', '2026-09-22T20:15:00+02:00'),
      ]);
      expect([for (final n in numbered) (n.episode['id'], n.number)], [(11, 1), (12, 2), (13, 3), (9, null)]);
    });

    test('repeated or rare stated numbers fall back to the broadcast order', () {
      final repeated = orfNumberEpisodes([
        _episode(1, 'Show (1/9): A', '2026-01-02T20:00:00+01:00'),
        _episode(2, 'Show (1/9): B', '2026-01-01T20:00:00+01:00'),
      ]);
      expect([for (final n in repeated) (n.episode['id'], n.number)], [(2, 1), (1, 2)]);

      final rare = orfNumberEpisodes([
        _episode(1, 'Show (5/9): A', '2026-01-03T20:00:00+01:00'),
        _episode(2, 'B', '2026-01-02T20:00:00+01:00'),
        _episode(3, 'C', '2026-01-01T20:00:00+01:00'),
      ]);
      expect([for (final n in rare) (n.episode['id'], n.number)], [(3, 1), (2, 2), (1, 3)]);
    });
  });

  group('ORF season planning', () {
    test('a numbered profile is exactly one season', () {
      final plans = orfPlanSeasons([_episode(1, 'A', '2026-01-01T00:00:00+01:00')], profileSeason: 5);
      expect([for (final p in plans) (p.key, p.number, p.title)], [('s5', 5, 'Staffel 5')]);
    });

    test('season markers in titles make one season each', () {
      final plans = orfPlanSeasons([
        _episode(1, 'Serie (S1/E1)', '2020-01-01T00:00:00+01:00'),
        _episode(2, 'Serie (S2/E1)', '2021-01-01T00:00:00+01:00'),
        _episode(3, 'Serie (S2/E2)', '2021-01-08T00:00:00+01:00'),
      ]);
      expect([for (final p in plans) (p.key, p.episodes.length)], [('s1', 1), ('s2', 2)]);
    });

    test('a sub-headline season sorts the rest into extras', () {
      final plans = orfPlanSeasons([
        _episode(1, 'A', '2026-01-01T00:00:00+01:00', subHeadline: 'Staffel 3'),
        _episode(2, 'B', '2026-01-02T00:00:00+01:00', subHeadline: 'Staffel 3'),
        _episode(3, 'Trailer', '2026-01-03T00:00:00+01:00', subHeadline: 'ORF ON Extra'),
      ]);
      expect([for (final p in plans) (p.key, p.number, p.episodes.length)], [('s3', 3, 2), ('extras', 0, 1)]);
    });

    test('a show spanning years is split by broadcast year', () {
      final plans = orfPlanSeasons([
        _episode(1, 'A', '2025-12-31T23:30:00+01:00'),
        _episode(2, 'B', '2026-10-14T20:15:00+02:00'),
        _episode(3, 'C', '2024-01-10T20:15:00+01:00'),
      ]);
      expect([for (final p in plans) (p.key, p.number)], [('y2024', 2024), ('y2025', 2025), ('y2026', 2026)]);
    });

    test('a show within one year is a single season holding everything', () {
      final plans = orfPlanSeasons([
        _episode(1, 'A', '2025-12-20T00:00:00+01:00'),
        _episode(2, 'B', '2026-01-10T00:00:00+01:00'),
      ]);
      expect([for (final p in plans) (p.key, p.title, p.episodes.length)], [('all', 'Alle Folgen', 2)]);
    });

    test('no episodes means no seasons', () {
      expect(orfPlanSeasons(const []), isEmpty);
    });
  });

  group('ORF text', () {
    test('the show name and counter are dropped inside the show', () {
      expect(orfTrimEpisodeTitle('Kiwi: Twini im Weltraum', 'Kiwi'), 'Twini im Weltraum');
      expect(
        orfTrimEpisodeTitle('Die Rosenheim-Cops (24/27): Ein tödliches Geschenk', 'Die Rosenheim-Cops'),
        'Ein tödliches Geschenk',
      );
    });

    test('titles that continue the show name are kept whole', () {
      expect(orfTrimEpisodeTitle('ZIB 1 vom 21.10.2026', 'ZIB 1'), 'ZIB 1 vom 21.10.2026');
      expect(orfTrimEpisodeTitle('Weinviertel - Weites Land', 'Universum'), 'Weinviertel - Weites Land');
    });

    test('a news synopsis becomes one headline per line', () {
      expect(orfSummary({'description': 'Erste Meldung | Zweite Meldung'}), 'Erste Meldung\nZweite Meldung');
      expect(orfSummary({'teaser_text': 'Kurztext'}), 'Kurztext');
    });
  });

  group('ORF artwork', () {
    const reference = 'https://api-tvthek.orf.at/assets/segments/0239/97/thumb_23896384_segments_player.jpg';

    test('the variant follows the width asked for', () {
      expect(orfImageUrl(reference, width: 100), endsWith('_small.jpg'));
      expect(orfImageUrl(reference, width: 300), endsWith('_list.jpg'));
      expect(orfImageUrl(reference, width: 600), endsWith('_player.jpg'));
      expect(orfImageUrl(reference, width: 1280), endsWith('_highlight_teaser.jpg'));
      expect(orfImageUrl(reference), endsWith('_player.jpg'));
    });

    test('an address without a variant name is returned unchanged', () {
      const plain = 'https://api-tvthek.orf.at/assets/segments/0239/97/6e287dbee051e5dac4.jpg';
      expect(orfImageUrl(plain, width: 100), plain);
      expect(isOrfImage(plain), isTrue);
      expect(isOrfImage('https://example.com/a.jpg'), isFalse);
    });

    test('the generic portrait is not a poster but the landscape image is', () {
      Map<String, dynamic> image(String name, {required bool fallback}) => <String, dynamic>{
        'is_fallback': fallback,
        'public_urls': <String, dynamic>{
          'player': <String, dynamic>{
            'url': 'https://api-tvthek.orf.at/assets/$name/0001/01/thumb_1_${name}_player.jpg',
          },
        },
      };
      final art = orfArtwork({
        '_embedded': <String, dynamic>{
          'image': image('seg', fallback: false),
          'image2x3': image('gen', fallback: true),
        },
      });
      expect(art.poster, isNull);
      expect(art.backdrop, contains('/seg/'));
      final portrait = orfArtwork({
        '_embedded': <String, dynamic>{
          'image': image('seg', fallback: false),
          'image2x3': image('por', fallback: false),
        },
      });
      expect(portrait.poster, contains('/por/'));
    });
  });

  group('ORF refs', () {
    test('every kind of native id survives a round trip', () {
      expect(parseOrfRef(orfEpisodeRef(14343509)), isA<OrfEpisodeTarget>());
      expect(parseOrfRef(orfSegmentRef(16174066)), isA<OrfSegmentTarget>());
      expect(parseOrfRef(orfProfileRef(1203)), isA<OrfProfileTarget>());
      expect((parseOrfRef(orfSeriesRef('kiwi')) as OrfSeriesTarget).key, 'kiwi');
      final season = parseOrfRef(orfSeasonRef(13899392, 's3')) as OrfSeasonTarget;
      expect((season.profileId, season.key), (13899392, 's3'));
    });

    test('ids that are not ours parse to null', () {
      expect(parseOrfRef(orfTestRef('episode/abc')), isNull);
      expect(parseOrfRef(orfTestRef('nothing')), isNull);
      expect(parseOrfRef(orfTestRef('season/1')), isNull);
    });
  });
}
