import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'bbciplayer_test_support.dart';

const _geoBlockedBody = 'mediaselector_geoblocked_BE.json';

Map<String, dynamic> _episodeWith(Map<String, dynamic> changes) {
  final record = bbcFixture('episode');
  final episode = Map<String, dynamic>.from((record['episodes'] as List).first as Map)..addAll(changes);
  return {
    'episodes': [episode],
  };
}

/// The media selector chain. Success bodies and manifests are synthetic, written from the documented response
/// shape; the geolocation answer is the one recorded from Belgium.
void bbcPlaybackCases() {
  group('BbcIplayerProvider playback', () {
    test('a clear HLS master is chosen by priority, with variants and subtitles', () async {
      final site = BbcFakeSite()..selector['m0032k1w'] = (status: 403, body: '{"result":"selectionunavailable"}');
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['Standard', 'Audio described']);
      expect(playback.streams.first.url.toString(), contains('/aaaa/'));
      expect(playback.streams.first.url.host, 'vod-hls-uk-live.akamaized.net');
      expect(playback.subtitles.single.languageCode, 'en');
      expect(playback.subtitles.single.url.path, endsWith('.xml'));
    });

    test('credits start where the version says and end with the programme', () async {
      final playback = await BbcFakeSite().provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.credits?.start, const Duration(seconds: 4381));
      expect(playback.credits?.end, const Duration(seconds: 4409));
    });

    test('the selector is asked for the pc media set of each version', () async {
      final site = BbcFakeSite();
      await site.provider().playback(bbcTestRef('m0030pxt'));
      final paths = site.selectorRequests.map((r) => r.url.path).toList();
      expect(paths.first, endsWith('/mediaset/pc/vpid/m0030pxv/format/json'));
      expect(paths, hasLength(3));
      expect(site.selectorRequests.first.headers['User-Agent'], contains('Plezy-Replay'));
    });

    test('DASH is used when no HLS connection exists and it carries no licence', () async {
      final site = BbcFakeSite()
        ..dashManifest = '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"/>'
        ..selector['m0030pxv'] = (status: 200, body: bbcFixtureText('synthetic_mediaselector_dash_only.json'));
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.first.url.path, endsWith('.mpd'));
    });

    test('a viewer outside the UK is told so and nothing else is tried', () async {
      final site = BbcFakeSite();
      for (final id in ['m0030pxv', 'p0pbcllx', 'm0032k1w']) {
        site.selector[id] = (status: 403, body: bbcFixtureText(_geoBlockedBody));
      }
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('United Kingdom'));
      expect(site.selectorRequests, hasLength(1));
    });

    test('a selection the BBC cannot make reads as expired', () async {
      final site = BbcFakeSite()..selector['m0030pxv'] = (status: 404, body: '{"result":"selectionunavailable"}');
      expect((await site.provider().playback(bbcTestRef('m0030pxt'))).availability, ReplayAvailability.expired);
    });

    test('an unknown selector answer is reported in its own words', () async {
      final site = BbcFakeSite()..selector['m0030pxv'] = (status: 403, body: '{"result":"allcdnsfailed"}');
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('allcdnsfailed'));
    });

    test('a refusal asking for sign-in is a login requirement', () async {
      final site = BbcFakeSite()..selector['m0030pxv'] = (status: 401, body: '{}');
      expect((await site.provider().playback(bbcTestRef('m0030pxt'))).availability, ReplayAvailability.loginRequired);
    });

    test('an HLS master with a key system is treated as protected', () async {
      final site = BbcFakeSite()..hlsManifest = bbcFixtureText('synthetic_master_keyed.m3u8');
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a DASH manifest with content protection is treated as protected', () async {
      final site = BbcFakeSite()
        ..selector['m0030pxv'] = (status: 200, body: bbcFixtureText('synthetic_mediaselector_dash_only.json'));
      expect((await site.provider().playback(bbcTestRef('m0030pxt'))).availability, ReplayAvailability.drmProtected);
    });

    test('an expired or not yet open window never reaches the selector', () async {
      final site = BbcFakeSite();
      final late = await site.provider(now: DateTime.utc(2028)).playback(bbcTestRef('m0030pxt'));
      final early = await site.provider(now: DateTime.utc(2026, 9)).playback(bbcTestRef('m0030pxt'));
      expect(late.availability, ReplayAvailability.expired);
      expect(early.availability, ReplayAvailability.upcoming);
      expect(site.selectorRequests, isEmpty);
    });

    test('statuses coming soon and unavailable are not played', () async {
      final site = BbcFakeSite();
      site.episodes['m0030pxt'] = _episodeWith({'status': 'coming_soon'});
      expect((await site.provider().playback(bbcTestRef('m0030pxt'))).availability, ReplayAvailability.upcoming);
      site.episodes['m0030pxt'] = _episodeWith({'status': 'unavailable'});
      expect((await site.provider().playback(bbcTestRef('m0030pxt'))).availability, ReplayAvailability.expired);
      expect(site.selectorRequests, isEmpty);
    });

    test('a missing episode is expired and a season is never played', () async {
      final site = BbcFakeSite();
      expect((await site.provider().playback(bbcTestRef('m9999999'))).availability, ReplayAvailability.expired);
      expect((await site.provider().playback(bbcTestRef('m0synth/all'))).isPlayable, isFalse);
    });

    test('rate limiting is reported without throwing', () async {
      final site = BbcFakeSite()..selector['m0030pxv'] = (status: 429, body: '{}');
      final playback = await site.provider().playback(bbcTestRef('m0030pxt'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a one-off plays through its own version', () async {
      final site = BbcFakeSite();
      final playback = await site.provider().playback(bbcTestRef('m001fyf7'));
      expect(playback.isPlayable, isTrue);
      expect(site.selectorRequests.single.url.path, contains('/vpid/m001fyf6/'));
    });
  });
}
