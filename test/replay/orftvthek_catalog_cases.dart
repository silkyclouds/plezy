import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';

import 'orftvthek_test_support.dart';

/// Show -> season -> episode, derived from profile names and episode titles.
void orfCatalogCases() {
  group('OrfTvthekProvider series', () {
    test('profiles named by season become one show with seasons', () async {
      final site = OrfFakeSite();
      final seasons = await site.provider.children(orfTestRef('series/kiwi'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.map((s) => s.title), ['Staffel 1', 'Staffel 2']);
      expect(seasons.map((s) => s.childCount), [26, 52]);
      expect(seasons.map((s) => s.ref.nativeId), ['season/13897581/s1', 'season/13898827/s2']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showTitle == 'Kiwi'), isTrue);
      expect(site.apiPaths.where((p) => p.endsWith('/episodes')), isEmpty);
    });

    test('episodes without numbers are numbered by broadcast date', () async {
      final provider = OrfFakeSite().provider;
      final episodes = await provider.children(orfTestRef('season/13898827/s2'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      expect(episodes.first.ref.nativeId, 'episode/14322919');
      expect(episodes.last.ref.nativeId, 'episode/14322960');
      expect(episodes.map((e) => e.title).first, 'Die Meerjungfrau');
    });

    test('an episode knows its show, season and numbers', () async {
      final episodes = await OrfFakeSite().provider.children(orfTestRef('season/13898827/s2'));
      final episode = episodes.first;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, orfTestRef('series/kiwi'));
      expect(episode.showTitle, 'Kiwi');
      expect(episode.seasonRef, orfTestRef('season/13898827/s2'));
      expect((episode.seasonNumber, episode.episodeNumber), (2, 1));
    });

    test('stated counters give the numbers and a trailer stays unnumbered', () async {
      final episodes = await OrfFakeSite().provider.children(orfTestRef('season/13899279/s5'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7, null]);
      expect(episodes.first.title, 'Bodycheck');
      expect(episodes.last.title, 'Trailer: "Soko Linz" Staffel 5');
    });

    test('a series show reports its season count', () async {
      final show = await OrfFakeSite().provider.title(orfTestRef('series/kiwi'));
      expect(show!.kind, ReplayKind.show);
      expect((show.title, show.childCount), ('Kiwi', 2));
    });

    test('a single numbered profile is still a show with one season', () async {
      final seasons = await OrfFakeSite().provider.children(orfTestRef('series/soko-linz'));
      expect(seasons.map((s) => s.seasonNumber), [5]);
    });

    test('a season page resolves to its season', () async {
      final provider = OrfFakeSite().provider;
      final season = await provider.title(orfTestRef('season/13898827/s2'));
      expect((season!.kind, season.seasonNumber, season.title), (ReplayKind.season, 2, 'Staffel 2'));
      expect(await provider.title(orfTestRef('season/13898827/s9')), isNull);
    });

    test('an unknown series has no seasons', () async {
      final provider = OrfFakeSite().provider;
      expect(await provider.children(orfTestRef('series/nothing')), isEmpty);
      expect(await provider.title(orfTestRef('series/nothing')), isNull);
    });
  });

  group('OrfTvthekProvider plain shows', () {
    test('a long-running show is split by broadcast year', () async {
      final seasons = await OrfFakeSite().provider.children(orfTestRef('profile/13844820'));
      expect(seasons.map((s) => s.seasonNumber), [2020, 2023, 2024, 2025, 2026]);
      expect(seasons.map((s) => s.childCount), [2, 2, 2, 2, 2]);
      expect(seasons.last.ref.nativeId, 'season/13844820/y2026');
    });

    test('a year season lists its episodes oldest first without the show name', () async {
      final episodes = await OrfFakeSite().provider.children(orfTestRef('season/13844820/y2026'));
      expect(episodes.map((e) => e.title), ['Bauer sucht Geld', 'Wenn das Dorf stirbt']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(episodes.every((e) => e.showTitle == 'Dok 1'), isTrue);
    });

    test('a daily show has one synthetic season', () async {
      final provider = OrfFakeSite().provider;
      final seasons = await provider.children(orfTestRef('profile/1203'));
      expect(seasons, hasLength(1));
      expect((seasons.single.ref.nativeId, seasons.single.title), ('season/1203/all', 'Alle Folgen'));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.title), ['ZIB 1 vom 20.10.2026', 'ZIB 1 vom 21.10.2026']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
    });

    test('a profile missing from the index is looked up on its own', () async {
      final site = OrfFakeSite(
        overrides: {
          'profile/999': orfEdited('profile', (json) {
            json['id'] = 999;
            json['title'] = 'Einzelsendung';
          }),
          'profile/999/episodes': orfFixture('profile_episodes.json'),
        },
      );
      final seasons = await site.provider.children(orfTestRef('profile/999'));
      expect(seasons.single.showTitle, 'Einzelsendung');
      expect(seasons.single.childCount, 2);
    });

    test('an unknown profile has no seasons and no page', () async {
      final provider = OrfFakeSite().provider;
      expect(await provider.children(orfTestRef('profile/13888476')), isEmpty);
      expect(await provider.title(orfTestRef('profile/13888476')), isNull);
    });

    test('episodes of a show are fetched once for several views', () async {
      final site = OrfFakeSite();
      final provider = site.provider;
      final seasons = await provider.children(orfTestRef('profile/1203'));
      final fetched = site.apiPaths.where((p) => p.startsWith('profile/1203/episodes')).length;
      await provider.children(seasons.single.ref);
      expect(site.apiPaths.where((p) => p.startsWith('profile/1203/episodes')), hasLength(fetched));
    });

    test('sign-language episodes are dropped from a show', () async {
      final site = OrfFakeSite(
        overrides: {
          'profile/1203/episodes': orfEdited('profile_episodes', (json) {
            ((json['_embedded'] as Map)['items'] as List).first['is_oegs'] = true;
          }),
        },
      );
      final seasons = await site.provider.children(orfTestRef('profile/1203'));
      expect(seasons.single.childCount, 1);
    });
  });

  group('OrfTvthekProvider titles', () {
    test('a programme page knows its show and when it ends', () async {
      final title = await OrfFakeSite().provider.title(orfTestRef('episode/14343509'));
      expect(title!.kind, ReplayKind.episode);
      expect(title.showRef, orfTestRef('profile/2616703'));
      expect(title.showTitle, 'Tom Turbo');
      expect(title.durationSeconds, 1585);
      expect(title.availableUntil, DateTime.utc(2026, 10, 24, 6, 14, 37));
      expect(title.genres, ['Kinder & Familie']);
    });

    test('a film is a movie', () async {
      final title = await OrfFakeSite().provider.title(orfTestRef('episode/14343582'));
      expect(title!.kind, ReplayKind.movie);
      expect(title.isPlayable, isTrue);
    });

    test('an episode of a numbered profile carries its season and number', () async {
      final title = await OrfFakeSite().provider.title(orfTestRef('episode/14343468'));
      expect(title!.showRef, orfTestRef('series/babylon-berlin'));
      expect(title.seasonRef, orfTestRef('season/13899392/s3'));
      expect((title.seasonNumber, title.episodeNumber), (3, 4));
      expect(title.availability, ReplayAvailability.drmProtected);
    });

    test('a chapter page is a clip', () async {
      final title = await OrfFakeSite().provider.title(orfTestRef('segment/16174066'));
      expect(title!.kind, ReplayKind.clip);
      expect(title.ref.nativeId, 'segment/16174066');
    });

    test('a programme ORF no longer has is null', () async {
      expect(await OrfFakeSite().provider.title(orfTestRef('episode/1')), isNull);
      expect(await OrfFakeSite().provider.title(orfTestRef('segment/1')), isNull);
      expect(await OrfFakeSite().provider.title(orfTestRef('nothing')), isNull);
    });

    test('a programme is never a parent', () async {
      expect(await OrfFakeSite().provider.children(orfTestRef('episode/14343509')), isEmpty);
    });
  });
}
