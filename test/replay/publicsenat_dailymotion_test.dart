import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/dailymotion/dailymotion_ids.dart';
import 'package:plezy/replay/providers/dailymotion/dailymotion_metadata.dart';
import 'package:plezy/replay/providers/dailymotion/dailymotion_resolver.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/replay/fixtures/publicsenat/$name').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _error(String code, int status) => {
  'error': {'code': code, 'status_code': status, 'title': 'raison'},
};

void main() {
  group('ids', () {
    test('both spellings of a video id are accepted', () {
      expect(isDailymotionVideoId('xbn437q'), isTrue);
      expect(isDailymotionVideoId('k1Q8jzk5KFFnRoLDHwy'), isTrue);
      expect(isDailymotionVideoId('a-vrai-dire'), isFalse);
      expect(isDailymotionVideoId('s2026'), isFalse);
      expect(isDailymotionVideoId(''), isFalse);
    });

    test('an id is found in thumbnail, embed and watch URLs', () {
      expect(
        dailymotionIdFromUrl('https://www.dailymotion.com/thumbnail/video/k1Q8jzk5KFFnRoLDHwy'),
        'k1Q8jzk5KFFnRoLDHwy',
      );
      expect(dailymotionIdFromUrl('https://www.dailymotion.com/embed/video/xbn437q?autoplay=1'), 'xbn437q');
      expect(dailymotionIdFromUrl('https://www.dailymotion.com/video/xbn437q'), 'xbn437q');
      expect(dailymotionIdFromUrl('https://example.com/video/xbn437q'), isNull);
    });
  });

  group('metadata', () {
    test('a recorded video gives its master playlist and nothing else', () {
      final playback = dailymotionPlaybackFromMetadata(_fixture('player_metadata.json'));
      expect(playback.availability, ReplayAvailability.playable);
      expect(playback.streams, hasLength(1));
      expect(
        playback.streams.single.url.toString(),
        startsWith('https://cdndirector.dailymotion.com/cdn/manifest/video/xbn437q.m3u8?'),
      );
      expect(playback.streams.single.headers, isEmpty);
      expect(playback.subtitles, isEmpty);
    });

    test('the stream label can be chosen by the caller', () {
      final playback = dailymotionPlaybackFromMetadata(_fixture('player_metadata.json'), label: 'FR');
      expect(playback.streams.single.label, 'FR');
    });

    test('a country block keeps the owner message', () {
      final playback = dailymotionPlaybackFromMetadata(_fixture('player_metadata_geoblocked.json'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('votre pays'));
      expect(playback.streams, isEmpty);
    });

    test('protected delivery is reported as protected, never played', () {
      final metadata = {..._fixture('player_metadata.json'), 'protected_delivery': true};
      expect(dailymotionPlaybackFromMetadata(metadata).availability, ReplayAvailability.drmProtected);
    });

    test('other error documents map by status and otherwise stay unknown', () {
      expect(dailymotionPlaybackFromMetadata(_error('DM001', 404)).availability, ReplayAvailability.expired);
      expect(dailymotionPlaybackFromMetadata(_error('DM010', 401)).availability, ReplayAvailability.loginRequired);
      final other = dailymotionPlaybackFromMetadata(_error('DM999', 500));
      expect(other.availability, ReplayAvailability.unknown);
      expect(other.message, 'raison');
    });

    test('a document without a usable playlist is unknown', () {
      expect(dailymotionPlaybackFromMetadata(const {}).availability, ReplayAvailability.unknown);
      final wrongType = {
        'qualities': {
          'auto': [
            {'type': 'video/mp4', 'url': 'https://example.com/v.mp4'},
          ],
        },
      };
      expect(dailymotionPlaybackFromMetadata(wrongType).availability, ReplayAvailability.unknown);
    });
  });

  group('resolver', () {
    test('an id is looked up and read', () async {
      final asked = <String>[];
      final resolver = DailymotionResolver((id) async {
        asked.add(id);
        return _fixture('player_metadata.json');
      });
      expect((await resolver.resolve('xbn437q')).isPlayable, isTrue);
      expect(asked, ['xbn437q']);
    });

    test('an id that is not a video id is refused without a lookup', () async {
      final resolver = DailymotionResolver((_) async => fail('must not be asked'));
      expect((await resolver.resolve('not an id')).availability, ReplayAvailability.unknown);
    });

    test('a video that is gone is expired', () async {
      final resolver = DailymotionResolver((_) async => null);
      expect((await resolver.resolve('xbn437q')).availability, ReplayAvailability.expired);
    });
  });
}
