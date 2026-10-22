import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import '3cat_fake_site.dart';

ReplayRef _ref(String id) => ReplayRef('3cat', id);

/// Programme 99001 has 700 videos: the first page holds season 1, the last season 3, and season 2 is only known to
/// the server's season filter.
http.Response? _largeProgramme(http.Request request) {
  final query = request.url.queryParameters;
  if (request.url.host != 'api.3cat.cat' || query['programatv_id'] != '99001') return null;
  Map<String, dynamic> video(int id, String season, int number) => threeCatVideoItem(
    id: id,
    title: 'T${season.split('_').last}xC$number - Capítol $number',
    programmeId: '99001',
    season: season,
    number: number,
  );
  final totals = {'PUTEMP_1': 300, 'PUTEMP_2': 250, 'PUTEMP_3': 150};
  final filter = query['temporada'];
  if (filter != null) {
    final number = int.parse(filter.split('_').last);
    final items = [for (var n = 1; n <= 4; n++) video(number * 100 + n, filter, n)];
    final size = int.parse(query['items_pagina']!);
    return json(listAnswer(items.take(size).toList(), size: size, total: totals[filter]));
  }
  final page = int.parse(query['pagina']!);
  final season = page == 1 ? 'PUTEMP_1' : 'PUTEMP_3';
  final items = [for (var n = 1; n <= 3; n++) video(page * 1000 + n, season, n)];
  return json(listAnswer(items, total: 700));
}

void threeCatSeasonCases() {
  group('ThreeCatProvider seasons', () {
    test('a show with one season lists it with its episode count', () async {
      final seasons = await ThreeCatFakeSite().provider().children(_ref('p76976'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('p76976/PUTEMP_1'));
      expect(seasons.single.kind, ReplayKind.season);
      expect(seasons.single.title, '1a Temporada');
      expect((seasons.single.seasonNumber, seasons.single.childCount), (1, 3));
      expect(seasons.single.showRef, _ref('p76976'));
      expect(seasons.single.showTitle, 'Wonderblocks');
    });

    test('a show with several seasons lists them in order', () async {
      final seasons = await ThreeCatFakeSite().provider().children(_ref('p54076'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.map((s) => s.title), ['1a Temporada', '2a Temporada']);
      expect(seasons.map((s) => s.childCount), [3, 3]);
    });

    test('a season lists its episodes in order with their numbers', () async {
      final provider = ThreeCatFakeSite().provider();
      final episodes = await provider.children(_ref('p76976/PUTEMP_1'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.map((e) => e.title), ['Som-hi', 'Prou', 'Bot']);
      expect(episodes.every((e) => e.seasonNumber == 1 && e.kind == ReplayKind.episode), isTrue);
      expect(episodes.first.ref, _ref('v6430199'));
      expect(episodes.first.seasonRef, _ref('p76976/PUTEMP_1'));
      expect(episodes.first.showRef, _ref('p76976'));
      expect(episodes.first.showTitle, 'Wonderblocks');
      expect(episodes.first.durationSeconds, 299);
      expect(episodes.first.availableUntil, DateTime.utc(2029, 5, 29, 21, 59, 59));
      expect(episodes.first.backdropUrl, 'https://img.3cat.cat/multimedia/jpg/3/7/1792249131273.jpg');
    });

    test('only the episodes of the asked season come back', () async {
      final episodes = await ThreeCatFakeSite().provider().children(_ref('p54076/PUTEMP_2'));
      expect(episodes.map((e) => e.title), ['Els Presocràtics', 'Thomas Hobbes', 'Els estoics']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.every((e) => e.seasonNumber == 2), isTrue);
    });

    test('a season is found by its ref', () async {
      final season = await ThreeCatFakeSite().provider().title(_ref('p54076/PUTEMP_2'));
      expect(season!.title, '2a Temporada');
      expect(await ThreeCatFakeSite().provider().title(_ref('p54076/PUTEMP_9')), isNull);
    });

    test('seasons are read from the title when the data has none', () async {
      final site = ThreeCatFakeSite(
        programmes: {
          '99002': [
            threeCatVideoItem(id: 1, title: 'T4xC37 - 25/06/2009', programmeId: '99002', programmeName: 'Polònia'),
            threeCatVideoItem(id: 2, title: 'T4xC36 - 18/06/2009', programmeId: '99002', programmeName: 'Polònia'),
            threeCatVideoItem(id: 3, title: 'T5xC1 - 10/09/2009', programmeId: '99002', programmeName: 'Polònia'),
          ],
        },
      );
      final provider = site.provider();
      final seasons = await provider.children(_ref('p99002'));
      expect(seasons.map((s) => s.seasonNumber), [4, 5]);
      expect(seasons.map((s) => s.title), ['Temporada 4', 'Temporada 5']);
      expect(seasons.map((s) => s.childCount), [2, 1]);

      final episodes = await provider.children(seasons.first.ref);
      expect(episodes.map((e) => e.episodeNumber), [36, 37]);
      expect(episodes.first.title, 'Polònia - 18/06/2009');
      expect(episodes.first.seasonNumber, 4);
      expect(episodes.first.seasonRef, _ref('p99002/T4'));
    });

    test('a title-derived season joins the matching broadcaster season', () async {
      final site = ThreeCatFakeSite(
        programmes: {
          '99004': [
            threeCatVideoItem(id: 1, title: 'T1xC1 - Un', programmeId: '99004', season: 'PUTEMP_1', number: 1),
            threeCatVideoItem(id: 2, title: 'T2xC1 - Dos', programmeId: '99004', season: 'PUTEMP_2', number: 1),
            threeCatVideoItem(id: 3, title: 'T2xC2 - Tres', programmeId: '99004'),
          ],
        },
      );
      final provider = site.provider();
      final seasons = await provider.children(_ref('p99004'));
      expect(seasons.map((s) => s.ref.nativeId), ['p99004/PUTEMP_1', 'p99004/PUTEMP_2']);
      expect(seasons.map((s) => s.childCount), [1, 2]);
      final episodes = await provider.children(seasons.last.ref);
      expect(episodes.map((e) => e.title), ['Dos', 'Tres']);
    });

    test('a show without seasons has one synthetic season', () async {
      final site = ThreeCatFakeSite(
        programmes: {
          '99003': [
            threeCatVideoItem(
              id: 1,
              title: 'Telenotícies - 02/10/2026',
              programmeId: '99003',
              programmeName: 'Telenotícies',
            ),
            threeCatVideoItem(
              id: 2,
              title: 'Telenotícies - 01/10/2026',
              programmeId: '99003',
              programmeName: 'Telenotícies',
            ),
          ],
        },
      );
      final provider = site.provider();
      final seasons = await provider.children(_ref('p99003'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('p99003/_all'));
      expect((seasons.single.seasonNumber, seasons.single.childCount), (1, 2));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.ref.nativeId), ['v1', 'v2']);
      expect(episodes.every((e) => e.seasonNumber == null && e.seasonRef == seasons.single.ref), isTrue);
    });

    test('episodes outside any season are kept as season zero', () async {
      final site = ThreeCatFakeSite(
        programmes: {
          '99005': [
            threeCatVideoItem(id: 1, title: 'T1xC1 - Un', programmeId: '99005', season: 'PUTEMP_1', number: 1),
            threeCatVideoItem(id: 2, title: 'Capítol especial', programmeId: '99005', programmeName: 'Altre'),
          ],
        },
      );
      final seasons = await site.provider().children(_ref('p99005'));
      expect(seasons.map((s) => s.seasonNumber), [1, 0]);
      expect(seasons.last.title, 'Altres capítols');
      final episodes = await site.provider().children(seasons.last.ref);
      expect(episodes.single.title, 'Capítol especial');
    });

    test('a very large show finds seasons from its ends and counts them', () async {
      final site = ThreeCatFakeSite(programmes: {'99001': const []}, custom: _largeProgramme);
      final seasons = await site.provider().children(_ref('p99001'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      expect(seasons.map((s) => s.childCount), [300, 250, 150]);
    });

    test('a large show asks the server for one season at a time', () async {
      final site = ThreeCatFakeSite(programmes: {'99001': const []}, custom: _largeProgramme);
      final episodes = await site.provider().children(_ref('p99001/PUTEMP_2'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.every((e) => e.seasonNumber == 2), isTrue);
      expect(site.requests.any((u) => u.queryParameters['temporada'] == 'PUTEMP_2'), isTrue);
    });

    test('a programme with no videos still answers', () async {
      final site = ThreeCatFakeSite(programmes: {'99006': const []});
      final provider = site.provider();
      final seasons = await provider.children(_ref('p99006'));
      expect(seasons.single.childCount, isNull);
      expect(await provider.children(seasons.single.ref), isEmpty);
    });
  });
}
