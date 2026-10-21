import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_api.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_images.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_mapper.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_numbering.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_playback.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'tf1plus_fixture_server.dart';

Map<String, dynamic> _video({Map<String, dynamic> extra = const {}}) => {
  'id': 'a6236d76-4dc3-4f6d-aaad-4c65481fcd08',
  'type': 'REPLAY',
  'decoration': {'label': 'HPI - S01 E01 - Vents d\'Ouest', 'programLabel': 'HPI', 'description': 'Un résumé'},
  'program': {'slug': 'hpi', 'name': 'HPI'},
  ...extra,
};

void main() {
  group('numbering', () {
    test('season labels state a number, a year, or nothing', () {
      expect(tf1SeasonNumberFromLabel('Saison 2'), 2);
      expect(tf1SeasonNumberFromLabel('Saison 34 - All Stars'), 34);
      expect(tf1SeasonNumberFromLabel('2026'), 2026);
      expect(tf1SeasonNumberFromLabel('Miami'), isNull);
      expect(tf1IsYearLabel('2025'), isTrue);
      expect(tf1IsYearLabel('Saison 2025'), isFalse);
    });

    test('themed seasons take free positions around the stated numbers', () {
      expect(tf1SeasonNumbers(['Saison 1', 'Miami', 'Saison 2', 'Hors-saison']), [1, 3, 2, 4]);
      expect(tf1SeasonNumbers(['Miami', 'Asian dream']), [1, 2]);
      expect(tf1SeasonNumbers(['2026', '2025']), [2026, 2025]);
    });

    test('episode labels spell their season and episode in several ways', () {
      expect(tf1NumbersFromLabel('HPI - S02 E01 - 2300 calories'), (season: 2, episode: 1));
      expect(tf1NumbersFromLabel('S18 E236'), (season: 18, episode: 236));
      expect(tf1NumbersFromLabel('Koh Lanta All Stars - Emission 9 (Partie 2)'), (season: null, episode: 9));
      expect(tf1NumbersFromLabel('Les Anges - Saison 13 Episode 40 du 29 mai 2026'), (season: 13, episode: 40));
      expect(tf1NumbersFromLabel('Série - Épisode 12'), (season: null, episode: 12));
      expect(tf1NumbersFromLabel('Le JT du mardi'), (season: null, episode: null));
    });

    test('an episode title drops the show name and the counter', () {
      expect(tf1EpisodeTitle('HPI - S02 E01 - 2300 calories', programName: 'HPI'), '2300 calories');
      expect(tf1EpisodeTitle('S02 E01 - 2300 calories'), '2300 calories');
      expect(
        tf1EpisodeTitle('Plus belle la vie - S18 E236', programName: 'Plus belle la vie', episode: 236),
        'Épisode 236',
      );
      expect(
        tf1EpisodeTitle('Koh Lanta All Stars - Emission 9', programName: 'Koh-Lanta'),
        'Koh Lanta All Stars - Emission 9',
      );
      expect(tf1EpisodeTitle('S01 E01'), 'S01 E01');
    });
  });

  group('images', () {
    const sources = {
      'sourcesWithScales': [
        {'url': 'https://photos.tf1.fr/330/186/a-1-0@1x.jpg', 'type': 'jpg', 'scale': 1, 'width': '330'},
        {'url': 'https://photos.tf1.fr/330/186/a-2-0@2x.jpg', 'type': 'jpg', 'scale': 2, 'width': '330'},
        {'url': 'https://photos.tf1.fr/330/186/a-3-0@3x.avif', 'type': 'avif', 'scale': 3, 'width': '330'},
        {'url': 'https://photos.tf1.fr/330/186/a-4-0@1x.webp', 'type': 'webp', 'scale': 1, 'width': '330'},
      ],
    };

    test('the smallest variant that is wide enough wins, and AVIF is skipped', () {
      expect(tf1PickImage(sources, targetWidth: 300), endsWith('a-1-0@1x.jpg'));
      expect(tf1PickImage(sources, targetWidth: 640), endsWith('a-2-0@2x.jpg'));
      expect(tf1PickImage(sources, targetWidth: 5000), endsWith('a-2-0@2x.jpg'));
    });

    test('portrait, background and logo shapes all yield a URL', () {
      final program = tf1Fixture('programs_series')['data']['programs']['items'][0]['decoration'] as Map;
      expect(tf1PickImage(program['image'], targetWidth: Tf1ImageWidth.poster), contains('/700/933/'));
      expect(tf1PickImage(program['background'], targetWidth: Tf1ImageWidth.backdrop), contains('/1920/1080/'));
      final smartTv = tf1Fixture('detail_hpi')['data']['programById']['decoration'] as Map;
      expect(tf1PickImage(smartTv['logo'], targetWidth: Tf1ImageWidth.logo), endsWith('.png'));
    });

    test('a video still prefers the large thumbnail and ignores the teaser', () {
      final images = [
        {
          'type': 'PREVIEW',
          'sources': [
            {'url': 'https://vidpreviews.tf1.fr/video/x.mp4', 'type': 'mp4'},
          ],
        },
        {
          'type': 'THUMBNAIL',
          'sources': [
            {'url': 'https://photos.tf1.fr/396/222/s-0@1x.jpg', 'type': 'jpg'},
          ],
        },
        {
          'type': 'THUMBNAIL_LARGE',
          'sources': [
            {'url': 'https://photos.tf1.fr/1200/720/l-0@1x.jpg', 'type': 'jpg'},
          ],
        },
      ];
      expect(tf1PickVideoImage(images), endsWith('l-0@1x.jpg'));
      expect(tf1PickVideoImage([images.first]), isNull);
      expect(tf1PickImage(null, targetWidth: 100), isNull);
    });
  });

  group('titles', () {
    test('a placeholder first-of-January date gives way to the publication date', () {
      final title = tf1VideoTitle(
        _video(extra: {'date': '2021-01-01T00:00:00Z', 'published': '2024-12-16T08:00:00Z'}),
      )!;
      expect(title.airDate, DateTime.utc(2024, 12, 16, 8));
      final real = tf1VideoTitle(_video(extra: {'date': '2024-01-01T09:00:00Z', 'published': '2024-01-01T09:30:00Z'}))!;
      expect(real.airDate, DateTime.utc(2024, 1, 1, 9));
    });

    test('availability ends the given number of days from now', () {
      final now = DateTime.utc(2026, 10, 21, 12);
      final title = tf1VideoTitle(
        _video(
          extra: {
            'playingInfos': {'duration': 90, 'remainingDays': 7},
          },
        ),
        now: now,
      )!;
      expect(title.availableUntil, DateTime.utc(2026, 10, 28, 12));
      expect(title.durationSeconds, 90);
      expect(tf1VideoTitle(_video())!.availableUntil, isNull);
    });

    test('counters come from the integer fields before the label', () {
      final fromFields = tf1VideoTitle(_video(extra: {'season': 3, 'episode': 4}))!;
      expect([fromFields.seasonNumber, fromFields.episodeNumber], [3, 4]);
      final fromLabel = tf1VideoTitle(_video(extra: {'season': 0, 'episode': 0}))!;
      expect([fromLabel.seasonNumber, fromLabel.episodeNumber], [1, 1]);
    });

    test('text loses its non-breaking spaces, extracts become clips', () {
      final title = tf1VideoTitle(_video(extra: {'type': 'EXTRACT'}))!;
      expect(title.summary, 'Un résumé');
      expect(title.kind, ReplayKind.clip);
      expect(title.title, 'Vents d\'Ouest');
    });

    test('a record without an id or slug is dropped', () {
      expect(tf1VideoTitle({'decoration': {}}), isNull);
      expect(tf1ProgramTitle({'name': 'No slug'}), isNull);
    });

    test('content rating classes become short labels', () {
      expect(
        [
          for (final c in ['CSA_ALL', 'CSA_10', 'CSA_12', 'CSA_16', 'CSA_18', null]) tf1ContentRating(c),
        ],
        ['TP', '10+', '12+', '16+', '18+', null],
      );
    });
  });

  group('media info', () {
    test('only a delivery that declares no DRM yields a stream', () {
      final clear = tf1ParsePlayback({
        'delivery': {'code': 200, 'url': 'https://example.invalid/a.mpd', 'format': 'dash'},
      });
      expect(clear.isPlayable, isTrue);
      final encrypted = tf1ParsePlayback({
        'delivery': {
          'code': 200,
          'url': 'https://example.invalid/a.mpd',
          'drms': [
            {'name': 'widevine'},
          ],
        },
      });
      expect(encrypted.availability, ReplayAvailability.drmProtected);
      expect(encrypted.streams, isEmpty);
    });

    test('an answer without a manifest or delivery is unknown', () {
      expect(
        tf1ParsePlayback({
          'delivery': {'code': 200},
        }).availability,
        ReplayAvailability.unknown,
      );
      expect(tf1ParsePlayback({}).availability, ReplayAvailability.unknown);
    });

    test('a refusal outside the geo list is geoblocked, inside it needs a login', () {
      Map<String, dynamic> denied(List<String> geoList) => {
        'media': {'error_code': 'PERMISSION_DENIED', 'geolock': true, 'geoList': geoList},
        'delivery': {'code': 403, 'country': 'BE'},
      };
      expect(tf1AvailabilityOfMediaInfo(denied(['FR'])), ReplayAvailability.geoBlocked);
      expect(tf1AvailabilityOfMediaInfo(denied(['BE', 'FR'])), ReplayAvailability.loginRequired);
      expect(
        tf1AvailabilityOfMediaInfo({
          'media': {'error_code': 'PERMISSION_DENIED'},
        }),
        ReplayAvailability.loginRequired,
      );
    });

    test('an unknown delivery error is expired only for a missing media', () {
      expect(tf1AvailabilityOfMediaInfo(tf1Fixture('mediainfo_unknown')), ReplayAvailability.expired);
      expect(
        tf1AvailabilityOfMediaInfo({
          'media': {'error_code': 'DELIVERY_ERROR'},
          'delivery': {'code': 500},
        }),
        ReplayAvailability.unknown,
      );
    });
  });

  group('requests', () {
    http.Response ok() =>
        http.Response('{"data":{"programs":{"total":1}}}', 200, headers: {'content-type': 'application/json'});

    test('every request names the app and asks for JSON', () async {
      final seen = <Map<String, String>>[];
      final api = Tf1Api(
        MediaServerHttpClient(
          client: MockClient((r) async {
            seen.add(r.headers);
            return ok();
          }),
        ),
        pacing: Tf1Pacing.none,
      );
      await api.programs({'categorySlug': 'series'});
      await api.mediaInfo('00000000-0000-4000-8000-000000000000');
      expect(seen, hasLength(2));
      for (final headers in seen) {
        expect(headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
        expect(headers['Accept'], 'application/json');
        expect(headers.containsKey('Authorization'), isFalse);
      }
    });

    test('a repeated catalogue query is served from the cache', () async {
      final server = Tf1FixtureServer();
      final api = server.api();
      await api.programs({'categorySlug': 'series'});
      await api.programs({'categorySlug': 'series'});
      await api.mediaInfo(Tf1TestVideo.widevine);
      await api.mediaInfo(Tf1TestVideo.widevine);
      expect(server.requests.where((u) => u.host == 'www.tf1.fr'), hasLength(1));
      expect(server.requests.where((u) => u.host == 'mediainfo.tf1.fr'), hasLength(2));
    });

    test('requests are spaced by the configured interval', () async {
      final pauses = <Duration>[];
      final api = Tf1FixtureServer().api(
        pacing: const Tf1Pacing(minInterval: Duration(milliseconds: 400)),
        delay: (d) async => pauses.add(d),
      );
      await api.mediaInfo(Tf1TestVideo.widevine);
      await api.mediaInfo(Tf1TestVideo.loginRequired);
      expect(pauses, isNotEmpty);
      expect(pauses.every((d) => d <= const Duration(milliseconds: 400)), isTrue);
    });

    test('a short Retry-After is waited out once, a long one is reported', () async {
      var calls = 0;
      final pauses = <Duration>[];
      Tf1Api build(String retryAfter) => Tf1Api(
        MediaServerHttpClient(
          client: MockClient((r) async {
            calls++;
            if (calls == 1) return http.Response('', 429, headers: {'retry-after': retryAfter});
            return ok();
          }),
        ),
        pacing: const Tf1Pacing(minInterval: Duration.zero, maxRetryWait: Duration(seconds: 10)),
        delay: (d) async => pauses.add(d),
      );

      await build('3').programs({'categorySlug': 'series'});
      expect(calls, 2);
      expect(pauses, contains(const Duration(seconds: 3)));

      calls = 0;
      await expectLater(
        build('120').programs({'categorySlug': 'series'}),
        throwsA(isA<Tf1RateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 120))),
      );
      expect(calls, 1);
    });

    test('a query the gateway cannot run at all is an error, not an empty list', () async {
      final api = Tf1Api(
        MediaServerHttpClient(
          client: MockClient(
            (r) async => http.Response(
              '{"data":null,"errors":[{"message":"category x not found"}]}',
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
        pacing: Tf1Pacing.none,
      );
      await expectLater(api.programs({'category': 'x'}), throwsA(isA<Tf1GraphqlException>()));
    });
  });
}
