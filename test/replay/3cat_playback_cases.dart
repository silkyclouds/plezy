import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/3cat/threecat_geo.dart';
import 'package:plezy/replay/providers/3cat/threecat_playback.dart';

import '3cat_fake_site.dart';

ReplayRef _ref(String id) => ReplayRef('3cat', id);

ReplayTitle _episode(String id) => ReplayTitle(ref: _ref('v$id'), kind: ReplayKind.episode, title: 'Episode $id');

void threeCatPlaybackCases() {
  group('ThreeCatProvider playback', () {
    test('a worldwide video gives DASH first, then MP4, and subtitles', () async {
      final site = ThreeCatFakeSite();
      final playback = await site.provider().playback(_ref('v6431752'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['DASH', '720p']);
      expect(playback.streams.first.url.host, 'ott-vod.3catvideos.cat');
      expect(playback.streams.last.url.host, 'mp4-down-high-int.3catvideos.cat');
      expect(playback.subtitles.single.languageCode, 'ca');
      expect(playback.subtitles.single.label, 'Català (SPS)');
      expect(playback.subtitles.single.url.host, 'statics.3cat.cat');
      expect(site.requestsTo('mp4-down-high-int.3catvideos.cat'), isEmpty);
    });

    test('a Spain-only video outside Spain is geoblocked with the notice', () async {
      final site = ThreeCatFakeSite();
      final playback = await site.provider().playback(_ref('v6431644'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, "Emissió no disponible fora de l'Estat Espanyol");
      expect(site.requestsTo('mp4-down-high-es.3catvideos.cat').single.host, contains('-es.'));
    });

    test('a Spain-only video plays for a viewer the host accepts', () async {
      final site = ThreeCatFakeSite(spainReachable: true);
      final playback = await site.provider().playback(_ref('v6431644'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.url.host, 'adaptive-es.3catvideos.cat');
    });

    test('an unexpected refusal is unknown, not a geoblock', () async {
      final site = ThreeCatFakeSite(
        custom: (r) => r.url.host.endsWith('3catvideos.cat') ? http.Response('', 503) : null,
      );
      final playback = await site.provider().playback(_ref('v6431644'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, 'HTTP 503');
    });

    test('a retired video is expired', () async {
      final retired = threeCatFixture('media_tots');
      (retired['informacio'] as Map)['estat'] = {'actiu': false, 'id': 3};
      final site = ThreeCatFakeSite(custom: (r) => r.url.host == 'api-media.3cat.cat' ? json(retired) : null);
      expect((await site.provider().playback(_ref('v6431752'))).availability, ReplayAvailability.expired);
    });

    test('an unknown video is expired', () async {
      expect((await ThreeCatFakeSite().provider().playback(_ref('v1'))).availability, ReplayAvailability.expired);
    });

    test('an answer without a file is unknown', () async {
      final empty = threeCatFixture('media_tots');
      (empty['media'] as Map)['url'] = <Object>[];
      final site = ThreeCatFakeSite(custom: (r) => r.url.host == 'api-media.3cat.cat' ? json(empty) : null);
      expect((await site.provider().playback(_ref('v6431752'))).availability, ReplayAvailability.unknown);
    });

    test('rate limiting is reported without throwing and pauses requests', () async {
      final site = ThreeCatFakeSite(
        custom: (r) =>
            r.url.host == 'api-media.3cat.cat' ? http.Response('', 429, headers: {'retry-after': '30'}) : null,
      );
      final provider = site.provider();
      final playback = await provider.playback(_ref('v6431752'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('30'));
      final before = site.requests.length;
      await provider.playback(_ref('v6431752'));
      expect(site.requests.length, before);
    });

    test('a show or a season is never played', () async {
      final provider = ThreeCatFakeSite().provider();
      expect((await provider.playback(_ref('p76976'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('p76976/PUTEMP_1'))).isPlayable, isFalse);
    });

    test('a bare address and a single subtitle object are understood', () {
      final media = threeCatParseMedia({
        'informacio': {
          'estat': {'actiu': true},
        },
        'media': {'geo': 'TOTS', 'url': 'https://mp4-down-high-int.3catvideos.cat/a.mp4'},
        'subtitols': {'text': 'Español', 'iso': 'es', 'url': 'https://statics.3cat.cat/multimedia/vtt/a.vtt'},
      });
      expect(media.streams.single.label, 'MP4');
      expect(media.subtitles.single.languageCode, 'es');
      expect(media.spainOnly, isFalse);
    });
  });

  group('ThreeCatProvider availability forecast', () {
    test('Spain-only videos of a list are blocked outside Spain', () async {
      final provider = ThreeCatFakeSite().provider();
      final episodes = await provider.children(_ref('p76976/PUTEMP_1'));
      final verdicts = await provider.predictAvailability(episodes, 'BE');
      expect(verdicts.keys.toSet(), episodes.map((e) => e.ref).toSet());
      expect(verdicts.values.every((v) => v == ReplayAvailability.geoBlocked), isTrue);
    });

    test('nothing is blocked for a viewer in Spain', () async {
      final provider = ThreeCatFakeSite().provider();
      final episodes = await provider.children(_ref('p76976/PUTEMP_1'));
      expect(await provider.predictAvailability(episodes, 'ES'), isEmpty);
      expect(await provider.predictAvailability(episodes, 'es'), isEmpty);
    });

    test('worldwide videos are not named', () async {
      final site = ThreeCatFakeSite(
        programmes: {
          '99010': [
            threeCatVideoItem(
              id: 1,
              title: 'T1xC1 - Obert',
              programmeId: '99010',
              season: 'PUTEMP_1',
              number: 1,
              geo: 'TOTS',
            ),
            threeCatVideoItem(
              id: 2,
              title: 'T1xC2 - Tancat',
              programmeId: '99010',
              season: 'PUTEMP_1',
              number: 2,
              geo: 'ESPANYA',
            ),
          ],
        },
      );
      final provider = site.provider();
      final episodes = await provider.children(_ref('p99010/PUTEMP_1'));
      final verdicts = await provider.predictAvailability(episodes, 'FR');
      expect(verdicts, {_ref('v2'): ReplayAvailability.geoBlocked});
    });

    test('videos without a flag are looked up in the media answer', () async {
      final site = ThreeCatFakeSite();
      final verdicts = await site.provider().predictAvailability([_episode('6431644'), _episode('6431752')], 'BE');
      expect(verdicts, {_ref('v6431644'): ReplayAvailability.geoBlocked});
      expect(site.requestsTo('api-media.3cat.cat'), hasLength(2));
    });

    test('a failed lookup leaves the video out', () async {
      final verdicts = await ThreeCatFakeSite().provider().predictAvailability([_episode('1')], 'BE');
      expect(verdicts, isEmpty);
    });

    test('lookups are capped', () async {
      final site = ThreeCatFakeSite();
      await site.provider().predictAvailability([for (var i = 1; i <= 30; i++) _episode('$i')], 'BE');
      expect(site.requestsTo('api-media.3cat.cat'), hasLength(ThreeCatAvailabilityForecast.maxLookups));
    });

    test('shows are not judged', () async {
      final show = ReplayTitle(ref: _ref('p76976'), kind: ReplayKind.show, title: 'Wonderblocks');
      final site = ThreeCatFakeSite();
      expect(await site.provider().predictAvailability([show], 'BE'), isEmpty);
      expect(site.requests, isEmpty);
    });
  });
}
