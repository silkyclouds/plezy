import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/lrt/lrt_forecast.dart';

import 'lrt_test_support.dart';

/// What plays and what does not, and the forecast that lists use to mark Lithuania-only recordings.
void lrtPlaybackCases() {
  group('LrtProvider playback', () {
    test('a recording plays its HLS playlist without a token', () async {
      final site = LrtFakeSite();
      final playback = await lrtProviderOver(site).playback(lrtRecording('2000901016'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.toString(), lrtMasterUrl);
      expect(playback.streams.single.label, 'LT');
      expect(playback.streams.single.headers, isEmpty);
      expect(playback.subtitles, isEmpty);
    });

    test('an old recording with a short id plays like any other', () async {
      final playback = await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('31066'));
      expect(playback.isPlayable, isTrue);
    });

    test('the Lithuania-only placeholder is reported as geoblocked', () async {
      final playback = await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('2000587152'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('Lithuania'));
    });

    test('a file the CDN no longer has is expired', () async {
      final playback = await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('2000000001'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('a forbidden playlist is geoblocked', () async {
      final playback = await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('2000000005'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
    });

    test('a record the site does not know is expired', () async {
      expect(
        (await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('1000000'))).availability,
        ReplayAvailability.expired,
      );
    });

    test('a lookup answered with a page instead of JSON is unknown', () async {
      final playback = await lrtProviderOver(LrtFakeSite()).playback(lrtRecording('2000000004'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('an audio file plays without fetching a playlist', () async {
      final site = LrtFakeSite();
      final playback = await lrtProviderOver(site).playback(lrtRecording('2000000003'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('radio.mp3'));
      expect(site.requestsTo('stream-vod3'), 0);
    });

    test('a server error on the lookup is thrown, a 404 is expired', () async {
      await expectLater(
        lrtProviderOver(LrtFakeSite()).playback(lrtRecording('2000000006')),
        throwsA(isA<MediaServerHttpException>()),
      );
      final site = LrtFakeSite()..overrides['/servisai/stream_url/vod/media_info/'] = (_) => http.Response('', 404);
      expect(
        (await lrtProviderOver(site).playback(lrtRecording('2000901016'))).availability,
        ReplayAvailability.expired,
      );
    });

    test('rate limiting is reported, then no further request is made', () async {
      final site = LrtFakeSite();
      final provider = lrtProviderOver(site);
      final first = await provider.playback(lrtRecording('2000000002'));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));
      final before = site.requests.length;
      final second = await provider.playback(lrtRecording('2000901016'));
      expect(second.isPlayable, isFalse);
      expect(site.requests.length, before);
    });

    test('shows and seasons are never played directly', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      expect((await provider.playback(lrtRef('zinios'))).isPlayable, isFalse);
      expect((await provider.playback(lrtRef('zinios/2025'))).isPlayable, isFalse);
    });
  });

  group('LrtProvider availability forecast', () {
    List<ReplayTitle> titles(Iterable<String> ids) => [
      for (final id in ids) ReplayTitle(ref: lrtRecording(id), kind: ReplayKind.episode, title: id),
    ];

    test('recordings licensed for Lithuania are flagged for a viewer abroad', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final verdicts = await (provider as ReplayAvailabilityPredictor).predictAvailability(
        titles(['2000901016', '2000587152']),
        'BE',
      );
      expect(verdicts[lrtRecording('2000587152')], ReplayAvailability.geoBlocked);
      expect(verdicts[lrtRecording('2000901016')], ReplayAvailability.playable);
    });

    test('a viewer in Lithuania costs no request', () async {
      final site = LrtFakeSite();
      final verdicts = await lrtProviderOver(site).predictAvailability(titles(['2000587152']), 'lt');
      expect(verdicts, isEmpty);
      expect(site.requests, isEmpty);
    });

    test('shows and seasons are not looked up', () async {
      final site = LrtFakeSite();
      final shows = [
        ReplayTitle(ref: lrtRef('zinios'), kind: ReplayKind.show, title: 'Žinios'),
        ReplayTitle(ref: lrtRef('zinios/2025'), kind: ReplayKind.season, title: '2025'),
      ];
      expect(await lrtProviderOver(site).predictAvailability(shows, 'BE'), isEmpty);
      expect(site.requests, isEmpty);
    });

    test('a long list is answered in steps and verdicts are kept', () async {
      final site = LrtFakeSite();
      final provider = lrtProviderOver(site);
      final ids = [for (var i = 0; i < 40; i++) '${2000300000 + i}'];
      final first = await provider.predictAvailability(titles(ids), 'BE');
      expect(first, hasLength(LrtForecast.maxLookups));
      expect(site.requestsTo('media_info'), LrtForecast.maxLookups);
      final second = await provider.predictAvailability(titles(ids), 'BE');
      expect(second, hasLength(LrtForecast.maxLookups * 2));
      expect(site.requestsTo('media_info'), LrtForecast.maxLookups * 2);
    });

    test('a failed or rate-limited lookup leaves the title unjudged', () async {
      final provider = lrtProviderOver(LrtFakeSite());
      final verdicts = await provider.predictAvailability(titles(['2000000006', '2000000002', '2000901016']), 'BE');
      expect(verdicts.keys, [lrtRecording('2000901016')]);
    });

    test('a record that is gone is left to the player to report', () async {
      final verdicts = await lrtProviderOver(LrtFakeSite()).predictAvailability(titles(['1000000']), 'BE');
      expect(verdicts, isEmpty);
    });
  });
}
