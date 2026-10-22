import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'bbciplayer_test_support.dart';

/// How shows are split into seasons and episodes, with the three shapes iPlayer uses: structural slices, editorial
/// slices, and no slice at all.
void bbcSeasonCases() {
  group('BbcIplayerProvider seasons', () {
    test('a structural slice is a series named after its number', () async {
      final seasons = await BbcFakeSite().provider().children(bbcTestRef('m002csng'));
      expect(seasons, hasLength(1));
      expect(seasons.single.title, 'Series 2');
      expect(seasons.single.seasonNumber, 2);
      expect(seasons.single.childCount, 4);
      expect(seasons.single.ref, bbcTestRef('m002csng/structural-2-m0030pxs'));
      expect(seasons.single.showRef, bbcTestRef('m002csng'));
    });

    test('episodes use the position stated in the series, oldest first', () async {
      final provider = BbcFakeSite().provider();
      final season = (await provider.children(bbcTestRef('m002csng'))).single;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [3, 4, 5, 6]);
      expect(episodes.first.title, 'Episode 3');
      expect(episodes.first.subtitle, 'The Celebrity Traitors');
      expect(episodes.every((e) => e.seasonNumber == 2 && e.seasonRef == season.ref), isTrue);
    });

    test('series, extras and several slices come out in order', () async {
      final provider = BbcFakeSite().provider();
      final seasons = await provider.children(bbcTestRef('m0synth'));
      expect(seasons.map((s) => s.title), ['Series 1', 'Series 2', 'Extras']);
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 0]);
      final second = await provider.children(seasons[1].ref);
      expect(second.map((e) => e.ref.nativeId), ['x0000001', 'x0000002']);
      expect(second.map((e) => e.episodeNumber), [1, 2]);
    });

    test('editorial slices become seasons after the numbered series', () async {
      final seasons = await BbcFakeSite().provider().children(bbcTestRef('b006m8dq'));
      expect(seasons.map((s) => s.title), [
        'Series 23',
        'Series 24',
        'Lights up',
        'Weekly rewind',
        'Dances',
        'Pro dances',
        'Training room diaries',
        'Launch show highlights',
      ]);
      expect(seasons.map((s) => s.seasonNumber), [23, 24, 25, 26, 27, 28, 29, 30]);
    });

    test('episodes without a stated position are numbered by release date', () async {
      final provider = BbcFakeSite().provider();
      final seasons = await provider.children(bbcTestRef('b006m8dq'));
      final episodes = await provider.children(seasons[1].ref);
      expect(episodes.map((e) => e.title), ['Icons Week', 'Week 4 Results']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(episodes.every((e) => e.seasonNumber == 24), isTrue);
    });

    test('a show that states series in subtitles gets one season each', () async {
      final provider = BbcFakeSite().provider();
      final seasons = await provider.children(bbcTestRef('m000vbrk'));
      expect(seasons.map((s) => s.title), ['Series 1', 'Series 2', 'Series 3']);
      final third = await provider.children(seasons.last.ref);
      expect(third.map((e) => e.episodeNumber), [27, 28]);
      expect(third.first.title, 'Musical Statues');
    });

    test('a show with no series gets one synthetic season', () async {
      final provider = BbcFakeSite().provider();
      final seasons = await provider.children(bbcTestRef('b006t14n'));
      expect(seasons, hasLength(1));
      expect(seasons.single.title, 'Panorama');
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.ref.nativeId, endsWith('/all'));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(5));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5]);
      expect(episodes.last.airDate!.isAfter(episodes.first.airDate!), isTrue);
      expect(episodes.first.title, isNot('Panorama'));
    });

    test('a season can be fetched by its own reference', () async {
      final provider = BbcFakeSite().provider();
      final season = (await provider.children(bbcTestRef('m0synth')))[1];
      final fetched = await provider.title(season.ref);
      expect(fetched!.kind, ReplayKind.season);
      expect(fetched.seasonNumber, 2);
    });

    test('a one-off has no seasons and an unknown show has none either', () async {
      final provider = BbcFakeSite().provider();
      expect(await provider.children(bbcTestRef('m001fyf7')), isEmpty);
      expect(await provider.children(bbcTestRef('m9999999')), isEmpty);
    });
  });
}
