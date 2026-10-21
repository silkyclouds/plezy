import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_api.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_assets.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_availability.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_genres.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_geo.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_images.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_numbering.dart';
import 'package:plezy/replay/providers/m6plus/m6plus_search.dart';
import 'package:plezy/utils/media_server_http_client.dart';

import 'm6plus_fixture_server.dart';

Map<String, dynamic> _video(String name) => readFixture(name) as Map<String, dynamic>;

void main() {
  group('M6+ numbering', () {
    test('a code prefix gives season, episode and a clean title', () {
      final info = m6plusEpisodeInfo(title: 'S3 E4 - La plume est dans le sac');
      expect((info.season, info.episode, info.title), (3, 4, 'La plume est dans le sac'));
    });

    test('a title that is only a code becomes Épisode N', () {
      final info = m6plusEpisodeInfo(title: 'S13 E16');
      expect((info.season, info.episode, info.title), (13, 16, 'Épisode 16'));
    });

    test('a worded episode gives the number and keeps the title', () {
      final info = m6plusEpisodeInfo(title: 'Épisode 7 - Partie 1');
      expect((info.season, info.episode, info.title), (null, 7, 'Épisode 7 - Partie 1'));
      expect(m6plusEpisodeInfo(title: 'Émission 31 - Partie 2').episode, 31);
    });

    test('a part marker after the code stays in the title', () {
      final info = m6plusEpisodeInfo(title: 'S8 E1 (1/2) - La dernière chance');
      expect((info.season, info.episode, info.title), (8, 1, '(1/2) - La dernière chance'));
    });

    test('metadata wins over the title, the season title fills gaps', () {
      final info = m6plusEpisodeInfo(title: 'S1 E1 - Pilote', season: 2, episode: 5);
      expect((info.season, info.episode), (2, 5));
      expect(m6plusEpisodeInfo(title: 'Pilote', seasonTitle: 'Saison 6').season, 6);
    });

    test('a plain title has no numbers', () {
      final info = m6plusEpisodeInfo(title: 'Mon voisin nu');
      expect((info.season, info.episode, info.title), (null, null, 'Mon voisin nu'));
    });
  });

  group('M6+ streams', () {
    test('clear HLS streams are chosen, HD before SD', () {
      final assets = m6plusAssetsOf(_video('video_clear_clip'));
      final clear = m6plusPlayableAssets(assets);
      expect(clear.map((a) => a.quality), ['hd', 'sd']);
      expect(clear.every((a) => a.isHls && a.isClear), isTrue);
    });

    test('protected streams are never chosen', () {
      for (final name in ['video_drm_geoblocked', 'video_drm_be_allowed']) {
        final assets = m6plusAssetsOf(_video(name));
        expect(assets, isNotEmpty);
        expect(assets.any((a) => a.isClear), isFalse, reason: name);
        expect(m6plusPlayableAssets(assets), isEmpty, reason: name);
      }
    });

    test('a podcast file is clear audio', () {
      final clear = m6plusPlayableAssets(m6plusAssetsOf(_video('video_podcast')));
      expect(clear.single.isAudio, isTrue);
      expect(clear.single.countries, isEmpty);
    });

    test('the allowed countries are read from the stream address', () {
      final locked = m6plusAssetsOf(_video('video_drm_geoblocked')).first;
      expect(locked.countries, containsAll(['FR', 'MC']));
      expect(locked.allows('BE'), isFalse);
      final open = m6plusAssetsOf(_video('video_clear_clip')).first;
      expect(open.allows('BE'), isTrue);
      expect(open.allows('XX'), isFalse);
    });

    test('a video with no stream list has no assets', () {
      expect(m6plusAssetsOf(_video('video_premium')), isEmpty);
      expect(m6plusAssetsOf(const {}), isEmpty);
    });
  });

  group('M6+ availability', () {
    test('long-form is protected, clear clips playable, premium gated', () {
      expect(m6plusVideoAvailability(_video('video_drm_geoblocked')), ReplayAvailability.drmProtected);
      expect(m6plusVideoAvailability(_video('video_clear_clip')), ReplayAvailability.playable);
      expect(m6plusVideoAvailability(_video('video_premium')), ReplayAvailability.loginRequired);
    });

    test('a known country outside the rights zone blocks a clear clip', () {
      final clip = _video('video_clear_clip');
      expect(m6plusVideoAvailability(clip, country: 'BE'), ReplayAvailability.playable);
      expect(m6plusVideoAvailability(clip, country: 'XX'), ReplayAvailability.geoBlocked);
    });

    test('a programme is judged from its content counts', () {
      Map<String, dynamic> program(int vi, int vc, int podcast, [String service = 'm6replay']) => {
        'count': {'vi': vi, 'vc': vc, 'podcast': podcast},
        'service_display': {'code': service},
      };
      expect(m6plusProgramAvailability(program(10, 0, 0)), ReplayAvailability.drmProtected);
      expect(m6plusProgramAvailability(program(10, 3, 0)), ReplayAvailability.drmProtected);
      expect(m6plusProgramAvailability(program(0, 3, 0)), ReplayAvailability.playable);
      expect(m6plusProgramAvailability(program(0, 0, 4)), ReplayAvailability.playable);
      expect(m6plusProgramAvailability(program(0, 0, 0)), ReplayAvailability.expired);
      expect(m6plusProgramAvailability(program(5, 0, 0, 'parispremierereplay')), ReplayAvailability.loginRequired);
    });
  });

  group('M6+ geo block', () {
    test('the refusal names the country and the allowed ones, not the address', () {
      const body =
          'Your country : BE is not allowed to access this resource. Allowed countries : AD, FR, GP ip detected: 192.0.2.7';
      final block = m6plusParseGeoBlock(body)!;
      expect(block.country, 'BE');
      expect(block.allowed, ['AD', 'FR', 'GP']);
      expect(block.message, contains('BE'));
      expect(block.message, isNot(contains('192.0.2.7')));
    });

    test('any other body is not a geo block', () {
      expect(m6plusParseGeoBlock('Forbidden'), isNull);
      expect(m6plusParseGeoBlock(''), isNull);
    });

    test('the country is unknown until a refusal reveals it', () {
      final geo = M6plusGeo();
      expect(geo.country, isNull);
      geo.learn('BE');
      expect(geo.country, 'BE');
    });
  });

  group('M6+ search folding', () {
    test('accents, case and punctuation are folded', () {
      expect(m6plusFold("L'amour est dans le pré"), 'l amour est dans le pre');
      expect(m6plusFold('Ça peut vous arriver'), 'ca peut vous arriver');
      expect(m6plusFold('  '), '');
    });

    test('every word must match and prefixes rank first', () {
      final programs = [
        {'title': 'Zig et Sharko'},
        {'title': 'Le grand Zig'},
        {'title': 'Zig'},
      ];
      final hits = m6plusSearchPrograms(programs, 'zig').map((p) => p['title']);
      expect(hits, ['Zig et Sharko', 'Zig', 'Le grand Zig']);
      expect(m6plusSearchPrograms(programs, 'zig sharko').single['title'], 'Zig et Sharko');
      expect(m6plusSearchPrograms(programs, 'nothing'), isEmpty);
    });
  });

  group('M6+ artwork', () {
    final images = [
      {'role': 'vignette', 'external_key': '111', 'id': 1},
      {'role': 'cover', 'external_key': '222', 'id': 2},
      {'role': 'portrait', 'external_key': '333', 'id': 3},
      {'role': 'logo', 'external_key': '444', 'id': 4},
    ];

    test('references point at the original file on the image host', () {
      expect(m6plusPoster(images), 'https://images-fio.6play.fr/v2/images/333/raw');
      expect(m6plusBackdrop(images), 'https://images-fio.6play.fr/v2/images/111/raw');
      expect(m6plusLogo(images), 'https://images-fio.6play.fr/v2/images/444/raw');
    });

    test('a missing preferred role falls back to the next one', () {
      expect(m6plusPoster([images[1]]), endsWith('/222/raw'));
      expect(m6plusBackdrop([images[2]]), isNull);
      expect(m6plusPoster(null), isNull);
    });

    test('sizes are ignored because resizing needs a signature', () {
      final reference = m6plusPoster(images)!;
      expect(m6plusImageUrl(reference), reference);
      expect(isM6plusImage(reference), isTrue);
      expect(isM6plusImage('https://example.com/a.jpg'), isFalse);
    });
  });

  group('M6+ genres', () {
    test('known slugs get accented labels, others are spaced out', () {
      expect(m6plusGenres('serie-policiere'), ['Série policière']);
      expect(m6plusGenres('mode-et-beaute'), ['Mode et beauté']);
      expect(m6plusGenres('new-kind_of'), ['New kind of']);
      expect(m6plusGenres(null), isEmpty);
    });
  });

  group('M6+ api', () {
    test('requests are spaced by the configured interval', () async {
      final server = M6plusFixtureServer();
      final api = server.api(minInterval: const Duration(milliseconds: 60));
      final clock = Stopwatch()..start();
      await api.program('28545');
      await api.program('28336');
      await api.program('28127');
      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });

    test('a repeated request is served from the cache', () async {
      final server = M6plusFixtureServer();
      final api = server.api();
      await api.program('28545');
      await api.program('28545');
      expect(server.requests.where((u) => u.path.endsWith('/programs/28545')), hasLength(1));
    });

    test('a 429 carries the retry delay', () async {
      final server = M6plusFixtureServer();
      await expectLater(
        server.api().video('clip_429'),
        throwsA(
          isA<M6plusRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30)),
        ),
      );
    });

    test('a missing programme is null, not an error', () async {
      expect(await M6plusFixtureServer().api().program('1'), isNull);
    });

    test('every request names the app in its user agent', () async {
      String? agent;
      final client = MediaServerHttpClient(
        client: MockClient((request) async {
          agent = request.headers['User-Agent'];
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        }),
      );
      await M6plusApi(client, minInterval: Duration.zero).program('1');
      expect(agent, startsWith('Plezy-Replay'));
    });
  });

  group('M6+ messages', () {
    test('gated outcomes have a sentence, playable has none', () {
      expect(m6plusUnavailableMessage(ReplayAvailability.drmProtected), contains('DRM'));
      expect(m6plusUnavailableMessage(ReplayAvailability.loginRequired), isNotEmpty);
      expect(m6plusUnavailableMessage(ReplayAvailability.expired), isNotEmpty);
      expect(m6plusUnavailableMessage(ReplayAvailability.upcoming), isNotEmpty);
      expect(m6plusUnavailableMessage(ReplayAvailability.playable), isNull);
    });
  });
}
