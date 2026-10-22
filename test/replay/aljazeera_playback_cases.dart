import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'aljazeera_fake_site.dart';

ReplayRef _ref(String id) => ReplayRef('aljazeera', id);

Map<String, dynamic> _recorded() =>
    jsonDecode(jsonEncode(aljazeeraFixture('brightcove_playback'))) as Map<String, dynamic>;

List<Map<String, dynamic>> _sources(Map<String, dynamic> body) =>
    (body['sources'] as List).cast<Map<String, dynamic>>();

Future<ReplayPlayback> _play(FakeAljazeera site, String video) =>
    providerOver(site).playback(_ref('inside-story/e/$video'));

void definePlaybackCases() {
  group('AljazeeraProvider playback', () {
    test('a video plays from its HLS master first and MP4 second', () async {
      final playback = await _play(FakeAljazeera(), recordedVideo);
      expect(playback.isPlayable, isTrue);
      expect(playback.streams, hasLength(2));
      final hls = playback.streams.first.url;
      expect(hls.scheme, 'https');
      expect(hls.host, 'manifest.prod.boltdns.net');
      expect(hls.path, contains('/hls/v4/clear/'));
      expect(hls.path, endsWith('master.m3u8'));
      expect(hls.queryParameters, contains('fastly_token'));
      expect(playback.streams.last.url.host, 'ajmn-aje-vod.akamaized.net');
      expect(playback.streams.last.label, 'MP4 1080p');
    });

    test('captions come from the HLS master, not as a second track', () async {
      expect((await _play(FakeAljazeera(), recordedVideo)).subtitles, isEmpty);
    });

    test('a clip plays the same way', () async {
      final playback = await providerOver(FakeAljazeera()).playback(_ref('v/$recordedVideo'));
      expect(playback.isPlayable, isTrue);
    });

    test('without HLS the MP4 plays and the captions are added', () async {
      final site = FakeAljazeera();
      final body = _recorded();
      body['sources'] = _sources(body).where((s) => s['container'] == 'MP4').toList();
      site.videos['300'] = (200, body);
      final playback = await _play(site, '300');
      expect(playback.streams.map((s) => s.label), ['MP4 1080p']);
      expect(playback.subtitles.single.languageCode, 'en');
      expect(playback.subtitles.single.url.scheme, 'https');
      expect(playback.subtitles.single.url.path, endsWith('text.vtt'));
    });

    test('plain http copies of a source are never used', () async {
      final site = FakeAljazeera();
      final body = _recorded();
      for (final source in _sources(body)) {
        source['src'] = (source['src'] as String).replaceFirst('https://', 'http://');
      }
      site.videos['301'] = (200, body);
      expect((await _play(site, '301')).isPlayable, isFalse);
    });

    test('an encrypted video is reported as protected', () async {
      final site = FakeAljazeera();
      final body = _recorded();
      for (final source in _sources(body)) {
        source['key_systems'] = {'com.widevine.alpha': <String, Object>{}};
      }
      site.videos['302'] = (200, body);
      final playback = await _play(site, '302');
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a video with no sources is unavailable for an unknown reason', () async {
      final site = FakeAljazeera();
      site.videos['303'] = (200, {..._recorded(), 'sources': <Object>[]});
      expect((await _play(site, '303')).availability, ReplayAvailability.unknown);
    });

    test('a removed video is reported as expired with the site message', () async {
      final playback = await _play(FakeAljazeera(), '1');
      expect(playback.availability, ReplayAvailability.expired);
      expect(playback.message, contains('not found'));
    });

    test('a country restriction is reported as geoblocked', () async {
      final site = FakeAljazeera();
      site.videos['304'] = (
        403,
        [
          {'error_code': 'CLIENT_GEO', 'message': 'Not available in your location'},
        ],
      );
      final playback = await _play(site, '304');
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, 'Not available in your location');
    });

    test('any other refusal is unknown and keeps the message', () async {
      final site = FakeAljazeera();
      site.videos['305'] = (
        403,
        [
          {'error_code': 'ACCESS_DENIED', 'message': 'Denied'},
        ],
      );
      final playback = await _play(site, '305');
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, 'Denied');
    });

    test('rate limiting is reported without throwing', () async {
      final site = FakeAljazeera()
        ..status = 429
        ..statusHeaders = {'retry-after': '30'};
      final playback = await _play(site, recordedVideo);
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a rate limited api waits instead of asking again', () async {
      final site = FakeAljazeera()
        ..status = 429
        ..statusHeaders = {'retry-after': '30'};
      final provider = providerOver(site);
      await provider.playback(_ref('inside-story/e/$recordedVideo'));
      final asked = site.requests.length;
      await provider.playback(_ref('inside-story/e/$recordedVideo'));
      expect(site.requests.length, asked);
    });

    test('a rotated player key is read again and the video plays', () async {
      final site = FakeAljazeera()..acceptedKey = rotatedKey;
      final provider = providerOver(site);
      expect((await provider.playback(_ref('inside-story/e/$recordedVideo'))).isPlayable, isTrue);
      final scripts = site.requests.where((r) => r.url.host == 'players.brightcove.net').length;
      expect(scripts, 1);
      expect((await provider.playback(_ref('v/$recordedVideo'))).isPlayable, isTrue);
      expect(site.requests.where((r) => r.url.host == 'players.brightcove.net').length, scripts);
    });

    test('a key that stays refused is reported, not retried forever', () async {
      final site = FakeAljazeera()..acceptedKey = 'BCpkSomethingElse';
      final playback = await _play(site, recordedVideo);
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('no longer accepts'));
      expect(site.requests.where((r) => r.url.host == 'edge.api.brightcove.com'), hasLength(2));
    });

    test('shows, seasons and empty ids are never played', () async {
      final site = FakeAljazeera();
      final provider = providerOver(site);
      for (final id in ['inside-story', 'inside-story/2026', 'inside-story/e/', 'nonsense/a/b/c']) {
        expect((await provider.playback(_ref(id))).availability, ReplayAvailability.unknown, reason: id);
      }
      expect(site.requests, isEmpty);
    });

    test('the player key and the identifying agent are sent', () async {
      final site = FakeAljazeera();
      await _play(site, recordedVideo);
      final request = site.requests.single;
      expect(request.headers['Accept'], startsWith('application/json;pk=BCpk'));
      expect(request.headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
      expect(request.url.path, '/playback/v1/accounts/665003303001/videos/$recordedVideo');
    });
  });
}
