import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'stvplayer_test_support.dart';

Future<ReplayPlayback> _play(String episodeId, {StvHarness? harness}) =>
    (harness ?? stvHarness()).provider.playback(stvRef('episode:$episodeId'));

/// Playback goes episode record, Brightcove video, sources. The Brightcove answers for a UK viewer are synthetic
/// (the recordings were made outside the UK); only the geo-blocked answer is a real recording.
void stvPlaybackCases() {
  group('StvPlayerProvider playback', () {
    test('an episode resolves to its HTTPS HLS source and subtitles', () async {
      final playback = await _play('235340');
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.toString(), 'https://manifest.example.test/hls/master.m3u8?token=a');
      expect(playback.subtitles.single.url.host, 'files.stv.tv');
      expect(playback.subtitles.single.languageCode, 'en');
    });

    test('the Brightcove call carries the public policy key and the app agent', () async {
      final harness = stvHarness();
      await _play('235340', harness: harness);
      final call = harness.requests.last;
      expect(call.url.path, '/playback/v1/accounts/1486976045/videos/6407203218112');
      expect(call.headers['Accept'], startsWith('application/json;pk=BCpk'));
      expect(call.headers['User-Agent'], contains('Plezy-Replay'));
    });

    test('caption tracks from Brightcove stand in for a missing subtitle file', () async {
      final playback = await _play(stvNoSubtitlesEpisode);
      expect(playback.subtitles.single.url.toString(), 'https://files.example.test/captions/en.vtt');
    });

    test('a clip plays through the same chain', () async {
      final playback = await stvHarness().provider.playback(stvRef('clip:412286'));
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles.single.url.host, 'files.example.test');
    });

    test('Brightcove 403 CLIENT_GEO is reported as geo-blocked, with no second try', () async {
      final harness = stvHarness();
      final playback = await _play('129138', harness: harness);
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('United Kingdom'));
      expect(playback.streams, isEmpty);
      expect(harness.requests.where((r) => r.url.host == 'edge.api.brightcove.com'), hasLength(1));
    });

    test('sources with key systems are copy-protected, never offered', () async {
      final playback = await _play('129137');
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a programme flagged as protected is not even requested', () async {
      final harness = stvHarness();
      final playback = await _play(stvProtectedEpisode, harness: harness);
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(harness.requests.where((r) => r.url.host == 'edge.api.brightcove.com'), isEmpty);
    });

    test('DASH is used when no HLS is offered, ahead of a plain file', () async {
      final playback = await _play('230665');
      expect(playback.streams.single.url.path, '/dash/manifest.mpd');
    });

    test('a catalogue window that closed or has not opened is said so', () async {
      expect((await _play(stvExpiredEpisode)).availability, ReplayAvailability.expired);
      expect((await _play(stvUpcomingEpisode)).availability, ReplayAvailability.upcoming);
    });

    test('an exclusive episode asks for an account', () async {
      expect((await _play(stvAccountEpisode)).availability, ReplayAvailability.loginRequired);
    });

    test('a video Brightcove no longer has counts as expired', () async {
      expect((await _play('234350')).availability, ReplayAvailability.expired);
    });

    test('a missing episode counts as expired, and a missing video as unknown', () async {
      expect((await _play('1')).availability, ReplayAvailability.expired);
      expect((await _play(stvNoVideoEpisode)).availability, ReplayAvailability.unknown);
    });

    test('a rejected policy key keeps Brightcove message', () async {
      final playback = await _play('234391');
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('Policy key'));
    });

    test('an HTTP-only manifest is not offered', () async {
      final playback = await _play('234537');
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('shows and seasons have nothing to play', () async {
      final provider = stvHarness().provider;
      expect((await provider.playback(stvRef('taggart'))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(stvRef('taggart/taggart-series-1'))).availability, ReplayAvailability.unknown);
    });
  });
}
