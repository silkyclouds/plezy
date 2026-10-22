import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/geo/replay_geo_service.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/provider/replay_source_info.dart';

http.Response _ok(String body) => http.Response(body, 200);

void main() {
  group('location', () {
    test('the country comes from the first service that answers', () async {
      final calls = <String>[];
      final service = ReplayGeoService(
        client: MockClient((request) async {
          calls.add(request.url.host);
          return _ok('fl=1\nip=1.2.3.4\nloc=BE\ntls=TLSv1.3\n');
        }),
      );
      expect(await service.resolve(), 'BE');
      expect(calls, ['www.cloudflare.com']);
    });

    test('a failing service hands over to the next one', () async {
      final service = ReplayGeoService(
        client: MockClient((request) async {
          if (request.url.host == 'ipwho.is') return _ok('{"country_code":"gb"}');
          return http.Response('down', 503);
        }),
      );
      expect(await service.resolve(), 'GB');
    });

    test('no answer means no country, so nothing is greyed out on a guess', () async {
      final service = ReplayGeoService(client: MockClient((_) async => http.Response('', 500)));
      expect(await service.resolve(), isNull);
    });

    test('the viewer can override the detected country and clear the override', () async {
      final service = ReplayGeoService(client: MockClient((_) async => _ok('loc=BE\n')));
      await service.resolve();
      await service.setOverride('au');
      expect(service.country, 'AU');
      expect(service.detected, 'BE');
      await service.setOverride(null);
      expect(service.country, 'BE');
    });

    test('a fresh result is not fetched again', () async {
      var calls = 0;
      final service = ReplayGeoService(
        client: MockClient((_) async {
          calls++;
          return _ok('loc=BE\n');
        }),
      );
      await service.resolve();
      await service.resolve();
      expect(calls, 1);
    });
  });

  group('blanket restriction', () {
    const restricted = ReplaySourceInfo(
      id: 'x',
      name: 'X',
      support: ReplayPlaybackSupport.clear,
      country: 'FR',
      languages: ['fr'],
      availableIn: {'FR'},
    );
    const open = ReplaySourceInfo(
      id: 'y',
      name: 'Y',
      support: ReplayPlaybackSupport.clear,
      country: 'FR',
      languages: ['fr'],
    );

    test('a viewer outside the listed countries is restricted; unknown or inside is not', () {
      expect(restricted.restrictsViewerIn('BE'), isTrue);
      expect(restricted.restrictsViewerIn('FR'), isFalse);
      expect(restricted.restrictsViewerIn(null), isFalse);
      expect(open.restrictsViewerIn('BE'), isFalse);
    });

    test('only playable titles are stamped geo-blocked; shows stay browsable', () {
      const source = ReplaySource(id: 'x', name: 'X', language: 'fr', support: ReplayPlaybackSupport.clear);
      const mapper = ReplayMapper(serverId: 'replay', source: source, blanketGeoBlock: true);
      final episode = mapper.item(ReplayTitle(ref: ReplayRef('x', 'e'), kind: ReplayKind.episode, title: 'E'));
      final show = mapper.item(ReplayTitle(ref: ReplayRef('x', 's'), kind: ReplayKind.show, title: 'S'));
      final drm = mapper.item(
        ReplayTitle(
          ref: ReplayRef('x', 'd'),
          kind: ReplayKind.episode,
          title: 'D',
          availability: ReplayAvailability.drmProtected,
        ),
      );
      expect(replayAvailabilityOf(episode), ReplayAvailability.geoBlocked);
      expect(replayAvailabilityOf(show), ReplayAvailability.playable);
      expect(replayAvailabilityOf(drm), ReplayAvailability.drmProtected);
    });
  });
}
