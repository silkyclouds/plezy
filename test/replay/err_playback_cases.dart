import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'err_fake_site.dart';

ReplayRef _ref(Object id) => ReplayRef('err', '$id');

const _clearEpisode = 1092243;
const _estoniaOnlyFilm = 1609804523;
const _protectedFilm = 1608311720;

/// A page with no video, as ERR serves a recording it has not published yet or has taken down.
Map<String, dynamic> _pageWithoutVideo({required int publicStart}) => {
  'mainContent': {'id': 8001, 'type': 'movie', 'heading': 'Tühi', 'publicStart': publicStart, 'medias': []},
};

void errPlaybackCases() {
  group('ErrProvider playback', () {
    test('a clear title yields its HLS master without asking the CDN', () async {
      final site = ErrFakeSite();
      final playback = await site.provider().playback(_ref(_clearEpisode));
      expect(playback.isPlayable, isTrue);
      expect(
        playback.streams.single.url.toString(),
        'https://vod.err.ee/hls/vod/0d21cd541e3b83d98c2c28b817fa38fb/3/v/master.m3u8',
      );
      expect(playback.streams.single.label, 'ET');
      expect(site.requestsTo('vod.err.ee'), isEmpty);
    });

    test('an Estonia-only title is geoblocked when the CDN refuses the viewer', () async {
      final site = ErrFakeSite();
      final playback = await site.provider().playback(_ref(_estoniaOnlyFilm));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('Estonia'));
      expect(site.requestsTo('vod.err.ee'), hasLength(1));
    });

    test('an Estonia-only title plays for a viewer the CDN accepts', () async {
      final site = ErrFakeSite()..viewerInEstonia = true;
      final playback = await site.provider().playback(_ref(_estoniaOnlyFilm));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'vod.err.ee');
    });

    test('a copy-protected title is never fetched or played', () async {
      final site = ErrFakeSite();
      final playback = await site.provider().playback(_ref(_protectedFilm));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(site.requestsTo('vod.err.ee'), isEmpty);
    });

    test('a programme is not played as a whole', () async {
      final playback = await ErrFakeSite().provider().playback(_ref(1038279));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, isNotEmpty);
    });

    test('an id ERR does not know is reported as expired', () async {
      expect((await ErrFakeSite().provider().playback(_ref(999))).availability, ReplayAvailability.expired);
    });

    test('a page without video is expired, or upcoming before its date', () async {
      final site = ErrFakeSite();
      final provider = site.provider();
      site.pageOverrides[8001] = _pageWithoutVideo(publicStart: 1000000000);
      expect((await provider.playback(_ref(8001))).availability, ReplayAvailability.expired);
      final future = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
      site.pageOverrides[8001] = _pageWithoutVideo(publicStart: future);
      expect((await provider.playback(_ref(8001))).availability, ReplayAvailability.upcoming);
    });

    test('a master that vanished from the CDN is expired', () async {
      final page = errFixture('movie_page_geoblocked');
      final media = ((page['mainContent'] as Map)['medias'] as List).first as Map<String, dynamic>;
      (media['src'] as Map)['hls'] = '//vod.err.ee/hls/gone/1/v/master.m3u8';
      final site = ErrFakeSite()
        ..pageOverrides[8002] = {
          'mainContent': {...page['mainContent'] as Map<String, dynamic>, 'id': 8002},
        };
      expect((await site.provider().playback(_ref(8002))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await ErrFakeSite().provider().playback(_ref(429));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a season ref is not playable', () async {
      expect((await ErrFakeSite().provider().playback(_ref('1038279/1'))).isPlayable, isFalse);
    });

    test('each play reads the page again, never from the cache', () async {
      final site = ErrFakeSite();
      final provider = site.provider();
      await provider.playback(_ref(_clearEpisode));
      await provider.playback(_ref(_clearEpisode));
      expect(site.pageRequests(_clearEpisode), 2);
    });
  });

  group('ErrProvider availability forecast', () {
    ReplayTitle film(int id) => ReplayTitle(ref: _ref(id), kind: ReplayKind.movie, title: '$id');

    test('outside Estonia, restricted and protected titles are flagged', () async {
      final verdicts = await ErrFakeSite().provider().predictAvailability([
        film(_clearEpisode),
        film(_estoniaOnlyFilm),
        film(_protectedFilm),
      ], 'BE');
      expect(verdicts, {
        _ref(_estoniaOnlyFilm): ReplayAvailability.geoBlocked,
        _ref(_protectedFilm): ReplayAvailability.drmProtected,
      });
    });

    test('in Estonia only the protected titles are flagged', () async {
      final verdicts = await ErrFakeSite().provider().predictAvailability([
        film(_clearEpisode),
        film(_estoniaOnlyFilm),
        film(_protectedFilm),
      ], 'ee');
      expect(verdicts, {_ref(_protectedFilm): ReplayAvailability.drmProtected});
    });

    test('verdicts are remembered, so a second list costs no requests', () async {
      final site = ErrFakeSite();
      final provider = site.provider();
      await provider.predictAvailability([film(_estoniaOnlyFilm)], 'BE');
      await provider.predictAvailability([film(_estoniaOnlyFilm)], 'DE');
      expect(site.pageRequests(_estoniaOnlyFilm), 1);
    });

    test('a title ERR does not answer for is left out', () async {
      final verdicts = await ErrFakeSite().provider().predictAvailability([film(999), film(429)], 'BE');
      expect(verdicts, isEmpty);
    });

    test('seasons are not asked about', () async {
      final site = ErrFakeSite();
      final season = ReplayTitle(ref: _ref('1038279/1'), kind: ReplayKind.season, title: 'Hooaeg 1');
      expect(await site.provider().predictAvailability([season], 'BE'), isEmpty);
      expect(site.requests, isEmpty);
    });

    test('a long list is looked up in bounded batches', () async {
      final site = ErrFakeSite();
      final titles = [for (var id = 100; id < 160; id++) film(id)];
      await site.provider().predictAvailability(titles, 'BE');
      expect(site.requests.length, lessThanOrEqualTo(24));
    });
  });
}
