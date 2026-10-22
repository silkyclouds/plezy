import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/orftvthek/orftvthek_credentials.dart';

import 'orftvthek_test_support.dart';

String _episodeEdited(void Function(Map<String, dynamic> json) edit) => orfEdited('episode_worldwide', edit);

OrfFakeSite _siteWith(void Function(Map<String, dynamic> json) edit) =>
    OrfFakeSite(overrides: {'episode/14343509': _episodeEdited(edit)});

/// What plays and what does not, the forecast for lists, and the API credentials.
void orfPlaybackCases() {
  group('OrfTvthekProvider playback', () {
    test('a worldwide programme plays its adaptive HLS ladder with subtitles', () async {
      final site = OrfFakeSite();
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'apasfiis.sf.apa.at');
      expect(playback.streams.single.url.path, endsWith('_QXA.mp4/playlist.m3u8'));
      expect(playback.streams.single.label, 'Deutsch');
      expect(playback.subtitles.single.languageCode, 'de');
      expect(playback.subtitles.single.url.toString(), startsWith('https://api-tvthek.orf.at/assets/subtitles/'));
      expect(site.requestsTo('apasfiis.sf.apa.at'), isEmpty);
    });

    test('an Austria-only programme is geoblocked outside Austria', () async {
      final site = OrfFakeSite();
      final playback = await site.provider.playback(orfTestRef('episode/14343582'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('Austria'));
    });

    test('the same programme plays for a viewer in Austria', () async {
      final playback = await OrfFakeSite(insideAustria: true).provider.playback(orfTestRef('episode/14343582'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, contains('cms-austria'));
    });

    test('the region check carries no credentials', () async {
      final site = OrfFakeSite();
      await site.provider.playback(orfTestRef('episode/14343582'));
      final probes = site.requestsTo('apasfiis.sf.apa.at');
      expect(probes, hasLength(1));
      expect(probes.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a protected programme is reported as protected', () async {
      final site = OrfFakeSite();
      final playback = await site.provider.playback(orfTestRef('episode/14343468'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(site.requestsTo('apasfiis.sf.apa.at'), isEmpty);
    });

    test('streams that are all protected count as protected', () async {
      final site = _siteWith((json) {
        final sources = json['sources'] as Map<String, dynamic>;
        for (final kind in ['hls', 'dash']) {
          for (final entry in sources[kind] as List) {
            (entry as Map)['quality_key'] = '${entry['quality_key']}DRM';
          }
        }
      });
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.availability, ReplayAvailability.drmProtected);
    });

    test('a programme past its end date is expired', () async {
      final site = _siteWith((json) => json['killdate'] = '2026-10-20T08:14:37+02:00');
      expect((await site.provider.playback(orfTestRef('episode/14343509'))).availability, ReplayAvailability.expired);
    });

    test('a programme not yet online is upcoming', () async {
      final site = _siteWith((json) => json['livedate'] = '2026-10-30T08:14:37+01:00');
      expect((await site.provider.playback(orfTestRef('episode/14343509'))).availability, ReplayAvailability.upcoming);
    });

    test('a programme behind the evening gate names its hours', () async {
      final site = _siteWith((json) {
        json['has_active_youth_protection'] = true;
        json['youth_protection_type'] = 'limited-20-06';
      });
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.availability, ReplayAvailability.timeSlotRestricted);
      expect(playback.message, contains('20:00'));
    });

    test('a programme ORF no longer has is expired, not an error', () async {
      final playback = await OrfFakeSite().provider.playback(orfTestRef('episode/1'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await OrfFakeSite().provider.playback(orfTestRef('episode/429'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('30'));
    });

    test('a region check that fails is unknown, not blocked', () async {
      final site = OrfFakeSite(
        overrides: {
          'episode/14343582': orfEdited('episode_austria_only', (json) {
            final hls = (json['sources'] as Map)['hls'] as List;
            for (final entry in hls) {
              (entry as Map)['src'] = (entry['src'] as String).replaceFirst('cms-austria', 'cms-austria-broken');
            }
          }),
        },
      );
      final playback = await site.provider.playback(orfTestRef('episode/14343582'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, isNotNull);
    });

    test('without an adaptive ladder the best fixed rendition plays', () async {
      final site = _siteWith((json) {
        final sources = json['sources'] as Map<String, dynamic>;
        for (final kind in ['hls', 'dash']) {
          (sources[kind] as List).removeWhere((entry) => (entry as Map)['is_adaptive_stream'] == true);
        }
      });
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.streams.single.url.path, endsWith('_Q8C.mp4/playlist.m3u8'));
    });

    test('without HLS the adaptive DASH manifest plays', () async {
      final site = _siteWith((json) => (json['sources'] as Map)['hls'] = []);
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.streams.single.url.path, endsWith('manifest.mpd'));
      expect(playback.streams.single.label, contains('DASH'));
    });

    test('a programme without subtitles still plays', () async {
      final site = _siteWith((json) => (json['_links'] as Map).remove('subtitle'));
      final playback = await site.provider.playback(orfTestRef('episode/14343509'));
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles, isEmpty);
    });

    test('a chapter plays like a programme and follows the same rule', () async {
      final provider = OrfFakeSite().provider;
      expect((await provider.playback(orfTestRef('segment/16174066'))).isPlayable, isTrue);
      expect((await provider.playback(orfTestRef('segment/16173844'))).availability, ReplayAvailability.geoBlocked);
    });

    test('a show or an unknown ref is never played', () async {
      final provider = OrfFakeSite().provider;
      expect((await provider.playback(orfTestRef('profile/1203'))).isPlayable, isFalse);
      expect((await provider.playback(orfTestRef('nothing'))).availability, ReplayAvailability.unknown);
    });
  });

  group('OrfTvthekProvider forecast', () {
    test('a viewer outside Austria sees Austria-only programmes greyed', () async {
      final provider = OrfFakeSite().provider;
      final rails = await provider.home();
      final titles = orfAllTitles(rails);
      final verdicts = await provider.predictAvailability(titles, 'BE');

      expect(verdicts[orfTestRef('episode/14344351')], ReplayAvailability.geoBlocked);
      expect(verdicts[orfTestRef('segment/16173844')], ReplayAvailability.geoBlocked);
      expect(verdicts[orfTestRef('episode/14344233')], ReplayAvailability.playable);
    });

    test('a viewer in Austria sees nothing greyed', () async {
      final provider = OrfFakeSite().provider;
      final titles = orfAllTitles(await provider.home());
      expect(await provider.predictAvailability(titles, 'AT'), isEmpty);
      expect(await provider.predictAvailability(titles, 'at'), isEmpty);
    });

    test('shows and programmes never seen are left unjudged', () async {
      final provider = OrfFakeSite().provider;
      final page = await provider.listing('all');
      final unseen = ReplayTitle(ref: orfTestRef('episode/5'), kind: ReplayKind.episode, title: 'Unseen');
      final verdicts = await provider.predictAvailability([...page.titles, unseen], 'BE');
      expect(verdicts, isEmpty);
    });

    test('a season page lists its episodes with the same verdicts', () async {
      final provider = OrfFakeSite().provider;
      final episodes = await provider.children(orfTestRef('season/13898827/s2'));
      final verdicts = await provider.predictAvailability(episodes, 'DE');
      expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
      expect(verdicts, hasLength(6));
    });
  });

  group('OrfTvthekProvider credentials', () {
    test('the pair comes from the page and is read once', () async {
      final site = OrfFakeSite();
      final provider = site.provider;
      await provider.categories();
      await provider.home();
      expect(site.pageReads, 1);
      final api = site.requestsTo('api-tvthek.orf.at');
      expect(api.every((r) => r.headers['Authorization'] == orfBasic(orfTestUser, orfTestPassword)), isTrue);
      expect(
        api.every((r) => r.headers['User-Agent'] == 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'),
        isTrue,
      );
    });

    test('a pair that stops working is read from the page again', () async {
      final site = OrfFakeSite();
      final provider = site.provider;
      await provider.categories();
      site.rotatePassword('another-fake-password');
      final playback = await provider.playback(orfTestRef('episode/14343509'));
      expect(playback.isPlayable, isTrue);
      expect(site.pageReads, 2);
    });

    test('the secret never appears in a request address', () async {
      final site = OrfFakeSite();
      await site.provider.home();
      expect(site.log.every((r) => !r.url.toString().contains(orfTestPassword)), isTrue);
    });

    test('a page without the settings is reported, not guessed around', () async {
      final site = OrfFakeSite()..pageWithoutSettings = '<html>maintenance</html>';
      await expectLater(site.provider.categories(), throwsA(isA<OrfCredentialsException>()));
      expect(site.requestsTo('api-tvthek.orf.at'), isEmpty);
    });
  });
}
