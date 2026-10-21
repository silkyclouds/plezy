import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/auth/replay_auth.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_provider.dart';

import 'rtlplay_auth_support.dart';

ReplayRef _ref(String id) => ReplayRef('rtlplay', id);

Future<(FakeRtlPlay, RtlPlayProvider, ReplaySession)> _signedIn() async {
  final rtl = FakeRtlPlay();
  final provider = rtl.provider();
  final session = await provider.authenticator.signIn(login: syntheticLogin, password: syntheticPassword);
  provider.useSession(session);
  rtl.log.clear();
  return (rtl, provider, session);
}

Iterable<http.Request> _playerCalls(FakeRtlPlay rtl) =>
    rtl.log.where((r) => r.url.host == 'videoplayer-service.dpgmedia.net' || r.url.path.startsWith('/rtlplay/player/'));

void main() {
  group('RtlPlay signed-in playback', () {
    test('the session cookies go to the player page and its bearer to the stream service', () async {
      final (rtl, provider, session) = await _signedIn();
      final playback = await provider.playback(_ref(film));

      final page = rtl.log.singleWhere((r) => r.url.path == '/rtlplay/player/$film');
      expect(page.headers['cookie'], contains('lfvp_rtlplay_auth=${session.values['lfvp_rtlplay_auth']}'));
      final config = rtl.log.singleWhere((r) => r.url.host == 'videoplayer-service.dpgmedia.net');
      expect(config.url.path, '/play-config/$film');
      expect(config.headers['authorization'], 'Bearer ${rtl.bearer}');
      expect(config.headers['x-api-key'], isNotEmpty);
      expect(config.headers['popcorn-sdk-version'], '8');
      expect(jsonDecode(config.body), {'deviceType': 'web', 'zone': 'rtlplay'});
      expect(playback.isPlayable, isTrue);
    });

    test('only unprotected streams are offered, HLS first, with subtitles', () async {
      final (_, provider, _) = await _signedIn();
      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.playable);
      expect(playback.streams.map((s) => s.url.toString()), [
        'https://media.example.invalid/clear/master.m3u8',
        'https://media.example.invalid/clear/manifest.mpd',
      ]);
      expect(playback.subtitles.map((s) => (s.languageCode, s.label)), [('fr', 'FR'), ('fr', 'FR (SDH)')]);
    });

    test('an episode is played by its own id', () async {
      final (rtl, provider, _) = await _signedIn();
      await provider.playback(_ref('$series/3/$seriesEpisode'));

      expect(rtl.log.any((r) => r.url.path == '/rtlplay/player/$seriesEpisode'), isTrue);
      expect(rtl.log.any((r) => r.url.path == '/play-config/$seriesEpisode'), isTrue);
    });

    test('a stream that is only available with DRM is reported as protected', () async {
      final (rtl, provider, _) = await _signedIn();
      rtl.playConfig = (200, authFixture('play_config_drm_only_synthetic.json'));
      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('the stream service refusals map to their availability', () async {
      final (rtl, provider, _) = await _signedIn();
      Future<ReplayAvailability> answer(int status, String body) async {
        rtl.playConfig = (status, body);
        return (await provider.playback(_ref(film))).availability;
      }

      expect(await answer(401, authFixture('play_config_unauthorized_401.json')), ReplayAvailability.loginRequired);
      expect(await answer(403, authFixture('play_config_geoblocked_synthetic.json')), ReplayAvailability.geoBlocked);
      expect(await answer(404, authFixture('play_config_expired_synthetic.json')), ReplayAvailability.expired);
      expect(await answer(500, ''), ReplayAvailability.unknown);
    });

    test('a player page that sends the visitor to the login means signing in again', () async {
      final (rtl, provider, _) = await _signedIn();
      rtl.playerStatus = 302;
      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(rtl.requestsTo('videoplayer-service.dpgmedia.net'), isEmpty);
    });

    test('a lost connection to the stream service is reported, not thrown', () async {
      final (rtl, provider, _) = await _signedIn();
      rtl.failureForHost = ('videoplayer-service.dpgmedia.net', http.ClientException('offline'));
      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('the bearer token is reused until it expires', () async {
      final (rtl, provider, _) = await _signedIn();
      await provider.playback(_ref(film));
      await provider.playback(_ref(film));

      expect(rtl.log.where((r) => r.url.path == '/rtlplay/player/$film'), hasLength(1));
      expect(rtl.log.where((r) => r.url.host == 'videoplayer-service.dpgmedia.net'), hasLength(2));
    });

    test('signing out returns to anonymous and asks nothing of the stream service', () async {
      final (rtl, provider, _) = await _signedIn();
      provider.useSession(null);
      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(_playerCalls(rtl), isEmpty);
    });

    test('a provider that was never signed in behaves as before', () async {
      final rtl = FakeRtlPlay();
      final playback = await rtl.provider().playback(_ref(film));

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(_playerCalls(rtl), isEmpty);
    });
  });

  group('RtlPlay session renewal', () {
    ReplaySession expiredSession(FakeRtlPlay rtl) {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      return ReplaySession(
        accountLabel: syntheticLogin,
        values: {'lfvp_rtlplay_auth': syntheticJwt(past)},
        expiresAt: past,
      );
    }

    test('an expired session is renewed before playing and the renewal is reported', () async {
      final rtl = FakeRtlPlay();
      final provider = rtl.provider();
      final renewedToken = syntheticJwt(DateTime.now().toUtc().add(const Duration(hours: 1)));
      rtl.homeSetCookie = 'lfvp_rtlplay_auth=$renewedToken; Path=/';
      final heard = <ReplaySession>[];
      provider.onSessionRenewed = heard.add;
      provider.useSession(expiredSession(rtl));

      final playback = await provider.playback(_ref(film));

      expect(playback.isPlayable, isTrue);
      expect(heard.single.values['lfvp_rtlplay_auth'], renewedToken);
      final page = rtl.log.singleWhere((r) => r.url.path == '/rtlplay/player/$film');
      expect(page.headers['cookie'], contains(renewedToken));
    });

    test('cookies the site rotates on the player page are reported', () async {
      final (rtl, provider, session) = await _signedIn();
      final rotated = syntheticJwt(DateTime.now().toUtc().add(const Duration(hours: 2)));
      rtl.playerSetCookie = 'lfvp_rtlplay_auth=$rotated; Path=/';
      final heard = <ReplaySession>[];
      provider.onSessionRenewed = heard.add;

      await provider.playback(_ref(film));

      expect(heard, hasLength(1));
      expect(heard.single.values['lfvp_rtlplay_auth'], rotated);
      expect(heard.single.values['lfvp_device_id'], session.values['lfvp_device_id']);
      expect(heard.single.accountLabel, session.accountLabel);
    });

    test('an unchanged session is not reported', () async {
      final (_, provider, _) = await _signedIn();
      final heard = <ReplaySession>[];
      provider.onSessionRenewed = heard.add;

      await provider.playback(_ref(film));

      expect(heard, isEmpty);
    });

    test('a listener set to null is no longer called', () async {
      final (rtl, provider, _) = await _signedIn();
      rtl.playerSetCookie = 'lfvp_rtlplay_auth=${syntheticJwt(DateTime.now().toUtc().add(const Duration(hours: 2)))}';
      final heard = <ReplaySession>[];
      provider.onSessionRenewed = heard.add;
      provider.onSessionRenewed = null;

      await provider.playback(_ref(film));

      expect(heard, isEmpty);
    });

    test('an expired session that cannot be renewed asks to sign in again', () async {
      final rtl = FakeRtlPlay();
      final provider = rtl.provider();
      final heard = <ReplaySession>[];
      provider.onSessionRenewed = heard.add;
      provider.useSession(expiredSession(rtl));

      final playback = await provider.playback(_ref(film));

      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(heard, isEmpty);
      expect(_playerCalls(rtl), isEmpty);
    });
  });
}
