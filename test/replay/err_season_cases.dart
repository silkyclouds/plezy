import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'err_fake_site.dart';

ReplayRef _ref(Object id) => ReplayRef('err', '$id');

/// A programme page whose episodes carry no numbers, only titles that say them.
Map<String, dynamic> _unnumberedProgramme() => {
  'mainContent': {'id': 7001, 'type': 'episode', 'heading': 'Kodu', 'rootContentId': 7000, 'statsSeriesTitle': 'Kodu'},
  'seasonList': {
    'type': 'seasonal',
    'contentOrder': 'asc',
    'items': [
      {
        'id': 1,
        'name': '1',
        'firstContentId': 7001,
        'active': true,
        'contents': [
          {'id': 7001, 'type': 'episode', 'heading': 'Kodu', 'subHeading': '1. osa: Tulek', 'season': 0, 'episode': 0},
          {'id': 7002, 'type': 'episode', 'heading': 'Kodu', 'subHeading': 'Osa 2', 'season': 0, 'episode': 0},
          {'id': 7003, 'type': 'episode', 'heading': 'Kodu', 'subHeading': 'Lõpp', 'season': 0, 'episode': 0},
        ],
      },
    ],
  },
};

void errSeasonCases() {
  group('ErrProvider seasons', () {
    test('a series lists its seasons in order, named by number', () async {
      final seasons = await ErrFakeSite().provider().children(_ref(1038279));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(seasons.first.title, 'Hooaeg 1');
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref(1038279)), isTrue);
    });

    test('only the season the page opened on knows its episode count', () async {
      final seasons = await ErrFakeSite().provider().children(_ref(1038279));
      expect(seasons.first.childCount, 8);
      expect(seasons[1].childCount, isNull);
    });

    test('the open season lists its episodes with numbers and parents', () async {
      final provider = ErrFakeSite().provider();
      final episodes = await provider.children(_ref('1038279/1'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(episodes.first.title, 'Britid tulevad');
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonNumber, 1);
      expect(episodes.first.seasonRef, _ref('1038279/1'));
      expect(episodes.first.showRef, _ref(1038279));
      expect(episodes.first.showTitle, 'Allo Allo!');
    });

    test('another season is read from the page of its first episode', () async {
      final site = ErrFakeSite();
      final episodes = await site.provider().children(_ref('1038279/2'));
      expect(episodes.map((e) => e.ref), [_ref(906025), _ref(906041), _ref(908214)]);
      expect(episodes.map((e) => e.seasonNumber).toSet(), {2});
      expect(site.pageRequests(906025), 1);
    });

    test('a short series has one season named after the show', () async {
      final provider = ErrFakeSite().provider();
      final seasons = await provider.children(_ref(1610145704));
      expect(seasons, hasLength(1));
      expect(seasons.single.title, 'Neeme Järvi meistrikursus');
      expect(seasons.single.seasonNumber, 1);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.single.episodeNumber, 2);
      expect(episodes.single.title, 'Olari Elts');
    });

    test('a programme filed by month has one season per year', () async {
      final seasons = await ErrFakeSite().provider().children(_ref(1038506));
      expect(seasons.map((s) => s.seasonNumber), [2025, 2026]);
      expect(seasons.map((s) => s.title), ['2025', '2026']);
    });

    test('a year reads its months oldest first and episodes in order', () async {
      final site = ErrFakeSite();
      final episodes = await site.provider().children(_ref('1038506/2025'));
      expect(episodes.map((e) => e.episodeNumber), [185, 186, 187, 200, 201, 202]);
      expect(episodes.map((e) => e.seasonNumber).toSet(), {2025});
      expect(site.pageRequests(1609876568), 1);
      expect(site.pageRequests(1609850767), 1);
    });

    test('a month that came with the show page is not requested again', () async {
      final site = ErrFakeSite();
      final episodes = await site.provider().children(_ref('1038506/2026'));
      expect(episodes.map((e) => e.episodeNumber), [143, 144, 145, 158, 159, 160]);
      expect(site.pageRequests(1610160944), 0);
    });

    test('a programme without a season list gets one synthetic season', () async {
      final provider = ErrFakeSite().provider();
      final seasons = await provider.children(_ref(1092236));
      expect(seasons.single.ref, _ref('1092236/1'));
      expect(seasons.single.title, 'Pätu');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.single.ref, _ref(1092243));
    });

    test('a film has no children', () async {
      expect(await ErrFakeSite().provider().children(_ref(1210984)), isEmpty);
    });

    test('an unknown season of a known programme is empty', () async {
      expect(await ErrFakeSite().provider().children(_ref('1038279/42')), isEmpty);
    });

    test('a season is found by its ref', () async {
      final season = await ErrFakeSite().provider().title(_ref('1038279/3'));
      expect(season!.kind, ReplayKind.season);
      expect(season.seasonNumber, 3);
    });

    test('episode numbers come from the titles when ERR sends none', () async {
      final site = ErrFakeSite()..pageOverrides[7000] = _unnumberedProgramme();
      final episodes = await site.provider().children(_ref('7000/1'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, null]);
      expect(episodes.map((e) => e.seasonNumber).toSet(), {1});
    });
  });
}
