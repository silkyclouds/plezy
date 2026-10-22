import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_title.dart';

import 'nrktv_test_support.dart';

ReplayTitle _movie(String programId) =>
    ReplayTitle(ref: nrkTestRef('program/$programId'), kind: ReplayKind.movie, title: programId);

int _lookups(List<http.Request> log) => log.where((r) => r.url.path.startsWith('/tv/catalog/programs/')).length;

void registerNrkForecastCases() {
  group('NrkTvProvider availability forecast', () {
    test('in Norway nothing is predicted and nothing is asked', () async {
      final log = <http.Request>[];
      final verdicts = await nrkProvider(log: log).predictAvailability([_movie('KMNO10057925')], 'no');
      expect(verdicts, isEmpty);
      expect(log, isEmpty);
    });

    test('episodes met in a season are judged without a request', () async {
      final log = <http.Request>[];
      final provider = nrkProvider(log: log);
      final episodes = await provider.children(nrkTestRef('series/dagsrevyen/202610'));
      final before = log.length;
      final verdicts = await provider.predictAvailability(episodes, 'BE');
      expect(log, hasLength(before));
      expect(verdicts[nrkTestRef('program/NNFA19101826')], ReplayAvailability.geoBlocked);
      expect(verdicts[nrkTestRef('program/NNFA19102126')], ReplayAvailability.playable);
    });

    test('unknown programmes are looked up once each', () async {
      final log = <http.Request>[];
      final provider = nrkProvider(log: log);
      final titles = [_movie('OFAA21000105'), _movie('KMNO10057925')];
      final verdicts = await provider.predictAvailability(titles, 'BE');
      expect(verdicts[titles[0].ref], ReplayAvailability.playable);
      expect(verdicts[titles[1].ref], ReplayAvailability.geoBlocked);
      expect(_lookups(log), 2);
      await provider.predictAvailability(titles, 'BE');
      expect(_lookups(log), 2);
    });

    test('series are left unjudged', () async {
      final show = ReplayTitle(ref: nrkTestRef('series/humoretaten'), kind: ReplayKind.show, title: 'Humoretaten');
      final log = <http.Request>[];
      expect(await nrkProvider(log: log).predictAvailability([show], 'BE'), isEmpty);
      expect(log, isEmpty);
    });

    test('a failed lookup leaves the title unjudged', () async {
      expect(await nrkProvider().predictAvailability([_movie('UNKNOWN00000')], 'BE'), isEmpty);
    });

    test('a list never costs more than sixteen lookups', () async {
      final log = <http.Request>[];
      final titles = [for (var i = 0; i < 30; i++) _movie('UNKNOWN$i')];
      await nrkProvider(log: log).predictAvailability(titles, 'BE');
      expect(_lookups(log), 16);
    });

    test('playback teaches the forecast what the manifest said', () async {
      final log = <http.Request>[];
      final provider = nrkProvider(log: log);
      await provider.playback(nrkTestRef('program/KMNO10057925'));
      final verdicts = await provider.predictAvailability([_movie('KMNO10057925')], 'BE');
      expect(verdicts.values.single, ReplayAvailability.geoBlocked);
      expect(_lookups(log), 0);
    });
  });
}
