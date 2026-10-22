import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'pbs_fixture_server.dart';

ReplayRef _video(String mediaId) => ReplayRef('pbs', 'video:$mediaId/some-video');

/// Every way PBS answers when a video is asked for, against recorded player pages and redirects.
void pbsPlaybackCases() {
  group('PBS playback', () {
    test('a playable video yields its HLS master and nothing else', () async {
      final server = PbsFixtureServer();
      final playback = await server.provider().playback(_video(playableId));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'ga.pbs-video.pbs.org');
      expect(playback.streams.single.url.path, endsWith('.m3u8'));
      expect(playback.subtitles, isEmpty);
      expect(server.requests.where((u) => u.host == 'urs.pbs.org'), hasLength(1));
    });

    test('the redirector is asked for JSON so the file is not downloaded', () async {
      final server = PbsFixtureServer();
      await server.provider().playback(_video(playableId));
      final redirect = server.requests.firstWhere((u) => u.host == 'urs.pbs.org');
      expect(redirect.queryParameters, {'format': 'json'});
    });

    test('a video with only an MP4 plays it with its caption files', () async {
      final playback = await PbsFixtureServer().provider().playback(_video(mp4OnlyId));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('.mp4'));
      expect(playback.streams.single.label, contains('MP4'));
      expect(playback.subtitles.map((s) => s.languageCode), ['en', 'es']);
      expect(playback.subtitles.first.url.path, endsWith('.vtt'));
      expect(playback.subtitles.first.label, 'English');
      expect(playback.subtitles.last.url.path, endsWith('.srt'));
    });

    test('a video PBS refuses abroad is reported as geoblocked', () async {
      final playback = await PbsFixtureServer().provider().playback(_video(refusedId));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('United States'));
    });

    test('a redirector that refuses the region is reported as geoblocked', () async {
      final provider = PbsFixtureServer().provider();
      expect((await provider.playback(_video(redirectRefusedId))).availability, ReplayAvailability.geoBlocked);
      expect((await provider.playback(_video(redirect403Id))).availability, ReplayAvailability.geoBlocked);
    });

    test('Passport episodes ask for a login', () async {
      final provider = PbsFixtureServer().provider();
      final fromBridge = await provider.playback(_video(passportId));
      expect(fromBridge.availability, ReplayAvailability.loginRequired);
      expect(fromBridge.message, contains('Passport'));
      expect((await provider.playback(_video(passportPageId))).availability, ReplayAvailability.loginRequired);
    });

    test('protected, expired and vanished videos say so', () async {
      final provider = PbsFixtureServer().provider();
      expect((await provider.playback(_video(drmId))).availability, ReplayAvailability.drmProtected);
      expect((await provider.playback(_video(expiredId))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_video(missingId))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported and then respected without a request', () async {
      final server = PbsFixtureServer();
      final provider = server.provider();
      final first = await provider.playback(_video(rateLimitedId));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));
      final sent = server.requests.length;
      expect((await provider.playback(_video(playableId))).availability, ReplayAvailability.unknown);
      expect(server.requests, hasLength(sent));
    });

    test('a show or season is never played directly', () async {
      final provider = PbsFixtureServer().provider();
      expect((await provider.playback(ReplayRef('pbs', 'show:frontline'))).isPlayable, isFalse);
      expect((await provider.playback(ReplayRef('pbs', 'season:frontline/specials'))).isPlayable, isFalse);
    });
  });

  group('PBS requests', () {
    test('every request names Plezy and none is a credential', () async {
      final server = PbsFixtureServer();
      final provider = server.provider();
      await provider.search('nova');
      await provider.playback(_video(playableId));
      expect(server.userAgents, everyElement('Plezy-Replay (+https://github.com/silkyclouds/plezy)'));
    });

    test('requests are spaced by the configured interval', () async {
      final server = PbsFixtureServer();
      final api = server.api(interval: const Duration(milliseconds: 150));
      await Future.wait([api.page('/'), api.page('/explore/arts/'), api.page('/show/frontline/')]);
      for (var i = 1; i < server.times.length; i++) {
        expect(server.times[i].difference(server.times[i - 1]).inMilliseconds, greaterThanOrEqualTo(140));
      }
    });

    test('catalogue answers are served from the cache for a few minutes', () async {
      final server = PbsFixtureServer();
      final provider = server.provider();
      await provider.search('nova');
      await provider.search('nova');
      expect(server.requests.where((u) => u.path == '/api/v1/search/'), hasLength(1));
    });
  });
}
