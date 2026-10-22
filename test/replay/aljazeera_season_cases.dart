import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'aljazeera_fake_site.dart';

ReplayRef _ref(String id) => ReplayRef('aljazeera', id);

/// Posts of one programme spaced [hours] apart, newest first, ending on [newest].
List<Map<String, dynamic>> _hourly(int count, DateTime newest, {int hours = 6}) => [
  for (var i = 0; i < count; i++) episodePost('inside-story', count - i, newest.subtract(Duration(hours: i * hours))),
];

List<int> _yearsOf(List<Map<String, dynamic>> posts) =>
    {for (final p in posts) DateTime.parse('${p['date']}Z').year}.toList()..sort();

void defineSeasonCases() {
  group('AljazeeraProvider seasons', () {
    test('a programme becomes one season per calendar year', () async {
      final seasons = await providerOver(FakeAljazeera()).children(_ref('inside-story'));
      expect(seasons.map((s) => s.title), ['2026']);
      expect(seasons.single.kind, ReplayKind.season);
      expect(seasons.single.seasonNumber, 2026);
      expect(seasons.single.ref, _ref('inside-story/2026'));
      expect(seasons.single.showRef, _ref('inside-story'));
      expect(seasons.single.showTitle, 'Inside Story');
    });

    test('a season takes the picture of its show', () async {
      final provider = providerOver(FakeAljazeera());
      final show = (await provider.title(_ref('inside-story')))!;
      final season = (await provider.children(_ref('inside-story'))).single;
      expect(season.posterUrl, show.posterUrl);
      expect(season.backdropUrl, show.backdropUrl);
    });

    test('a season lists its episodes oldest first with numbers', () async {
      final provider = providerOver(FakeAljazeera());
      final episodes = await provider.children(_ref('inside-story/2026'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.map((e) => e.airDate!.day), [16, 17, 18, 20]);
      expect(episodes.first.ref, _ref('inside-story/e/6406969682112'));
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.seasonNumber == 2026), isTrue);
      expect(episodes.every((e) => e.seasonRef == _ref('inside-story/2026')), isTrue);
      expect(episodes.every((e) => e.showRef == _ref('inside-story') && e.showTitle == 'Inside Story'), isTrue);
    });

    test('a season opened by id is the same season', () async {
      final provider = providerOver(FakeAljazeera());
      expect((await provider.title(_ref('inside-story/2026')))!.title, '2026');
      expect(await provider.title(_ref('inside-story/1999')), isNull);
    });

    test('years are found across a deep archive in a few probes', () async {
      final site = FakeAljazeera()
        ..posts['inside-story'] = postHistory('inside-story', DateTime.utc(2026, 10, 20), 3000);
      final seasons = await providerOver(site).children(_ref('inside-story'));
      expect(seasons.map((s) => s.seasonNumber), [for (var y = 2018; y <= 2026; y++) y]);
      expect(site.postRequests, lessThan(30));
    });

    test('a middle year is read from where it starts', () async {
      final posts = postHistory('inside-story', DateTime.utc(2026, 10, 20), 1500);
      final site = FakeAljazeera()..posts['inside-story'] = posts;
      final expected = posts.where((p) => '${p['date']}'.startsWith('2023')).toList();
      final episodes = await providerOver(site).children(_ref('inside-story/2023'));
      expect(episodes, hasLength(expected.length));
      expect(episodes.every((e) => e.airDate!.year == 2023), isTrue);
      expect(episodes.map((e) => e.episodeNumber), [for (var i = 1; i <= expected.length; i++) i]);
      expect(episodes.first.airDate!.isBefore(episodes.last.airDate!), isTrue);
    });

    test('every year of a long programme is covered exactly once', () async {
      final posts = postHistory('inside-story', DateTime.utc(2026, 3, 9), 900, days: 2);
      final site = FakeAljazeera()..posts['inside-story'] = posts;
      final provider = providerOver(site);
      final seasons = await provider.children(_ref('inside-story'));
      expect(seasons.map((s) => s.seasonNumber), _yearsOf(posts));
      final refs = <ReplayRef>{};
      for (final season in seasons) {
        refs.addAll((await provider.children(season.ref)).map((e) => e.ref));
      }
      expect(refs, hasLength(posts.length));
    });

    test('an episode just after midnight on New Year belongs to the new year', () async {
      final site = FakeAljazeera()
        ..posts['inside-story'] = [
          episodePost('inside-story', 3, DateTime.utc(2026, 1, 1, 0, 10)),
          episodePost('inside-story', 2, DateTime.utc(2025, 12, 31, 23, 30)),
          episodePost('inside-story', 1, DateTime.utc(2025, 12, 31)),
        ];
      final provider = providerOver(site);
      expect((await provider.children(_ref('inside-story'))).map((s) => s.seasonNumber), [2025, 2026]);
      expect((await provider.children(_ref('inside-story/2026'))).map((e) => e.ref.nativeId), ['inside-story/e/93']);
      expect((await provider.children(_ref('inside-story/2025'))).map((e) => e.episodeNumber), [1, 2]);
    });

    test('a year too long to read in full is cut and left unnumbered', () async {
      final site = FakeAljazeera()..posts['inside-story'] = _hourly(700, DateTime.utc(2026, 10, 20));
      final episodes = await providerOver(site).children(_ref('inside-story/2026'));
      expect(episodes, hasLength(600));
      expect(episodes.every((e) => e.episodeNumber == null), isTrue);
    });

    test('posts without a video are skipped and numbers stay consecutive', () async {
      final site = FakeAljazeera()
        ..posts['inside-story'] = [
          for (var i = 0; i < 9; i++)
            episodePost('inside-story', 9 - i, DateTime.utc(2026, 10, 20 - i), withVideo: i % 3 != 1),
        ];
      final episodes = await providerOver(site).children(_ref('inside-story/2026'));
      expect(episodes, hasLength(6));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      for (final skipped in ['98', '95', '92']) {
        expect(episodes.map((e) => e.ref.nativeId), isNot(contains('inside-story/e/$skipped')));
      }
    });

    test('a programme without posts has no seasons', () async {
      final site = FakeAljazeera()..posts.remove('inside-story');
      final provider = providerOver(site);
      expect(await provider.children(_ref('inside-story')), isEmpty);
      expect(await provider.children(_ref('inside-story/2026')), isEmpty);
    });

    test('a programme the site does not list has no seasons', () async {
      expect(await providerOver(FakeAljazeera()).children(_ref('no-such-programme')), isEmpty);
    });

    test('a year outside the programme has no episodes', () async {
      final provider = providerOver(FakeAljazeera());
      expect(await provider.children(_ref('inside-story/2031')), isEmpty);
      expect(await provider.children(_ref('inside-story/1999')), isEmpty);
    });

    test('measuring a programme twice costs its probes once', () async {
      final site = FakeAljazeera()
        ..posts['inside-story'] = postHistory('inside-story', DateTime.utc(2026, 10, 20), 400);
      final provider = providerOver(site);
      await provider.children(_ref('inside-story'));
      final probes = site.postRequests;
      await provider.children(_ref('inside-story'));
      expect(site.postRequests, probes);
    });

    test('a programme whose only posts are on YouTube has no playable year', () async {
      final provider = providerOver(FakeAljazeera());
      expect(await provider.children(_ref('witness/2026')), isEmpty);
    });
  });
}
