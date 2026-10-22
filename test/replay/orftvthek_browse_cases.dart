import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'orftvthek_test_support.dart';

/// Landing page, genres, flat listings, search and artwork.
void orfBrowseCases() {
  group('OrfTvthekProvider browsing', () {
    test('home lists the hero row, the newest programmes and the lanes', () async {
      final rails = await OrfFakeSite().provider.home();
      expect([for (final r in rails) r.id], ['highlights', 'recent', 'lane-13870317', 'lane-mostviewed']);
      expect(rails.first.titles, hasLength(4));
      expect(rails.every((r) => r.titles.every((t) => t.ref.source == 'orftvthek')), isTrue);
    });

    test('home survives a lane that ORF removed', () async {
      final site = OrfFakeSite();
      final rails = await site.provider.home();
      expect(site.apiPaths, contains('lane/13869361'));
      expect(rails, isNotEmpty);
    });

    test('rails offer a see-all listing that the provider can serve', () async {
      final provider = OrfFakeSite().provider;
      final rails = await provider.home();
      final lane = rails.firstWhere((r) => r.id == 'lane-13870317');
      expect(lane.moreBrowseId, 'lane:13870317');
      expect((await provider.listing(lane.moreBrowseId!)).titles, hasLength(3));
      expect(rails.firstWhere((r) => r.id == 'recent').moreBrowseId, 'recent');
    });

    test('sign-language versions are left out of lists', () async {
      final rails = await OrfFakeSite().provider.home();
      final recent = rails.firstWhere((r) => r.id == 'recent');
      expect(recent.titles.map((t) => t.ref.nativeId), ['episode/14344633']);
    });

    test('a chapter that is its programme maps to the programme', () async {
      final rails = await OrfFakeSite().provider.home();
      final popular = rails.firstWhere((r) => r.id == 'lane-mostviewed').titles;
      expect(popular.first.ref.nativeId, 'episode/14343824');
      expect(popular.first.kind, ReplayKind.episode);
      expect(popular.first.episodeNumber, 1);
    });

    test('a chapter cut from a programme is a clip', () async {
      final rails = await OrfFakeSite().provider.home();
      final lane = rails.firstWhere((r) => r.id == 'lane-13870317').titles;
      expect(lane.first.kind, ReplayKind.clip);
      expect(lane.first.ref.nativeId, 'segment/16173844');
      expect(lane.first.isPlayable, isTrue);
    });

    test('a film of the Film genre is a movie', () async {
      final rails = await OrfFakeSite().provider.home();
      final popular = rails.firstWhere((r) => r.id == 'lane-mostviewed').titles;
      expect(popular.firstWhere((t) => t.title == 'Alter weißer Mann').kind, ReplayKind.movie);
    });

    test('categories are the genres', () async {
      final categories = await OrfFakeSite().provider.categories();
      expect(categories, hasLength(18));
      expect((categories.first.id, categories.first.title), ('2703825', 'ZIB & Info'));
    });

    test('a genre page offers newest programmes and shows', () async {
      final rails = await OrfFakeSite().provider.category('1178');
      expect([for (final r in rails) r.id], ['genre-episodes', 'genre-shows']);
      expect(rails.last.titles.map((t) => t.ref.nativeId), contains('profile/7028409'));
      expect(rails.last.titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('the whole catalogue lists each show once, series merged', () async {
      final page = await OrfFakeSite().provider.listing(replayAllBrowseId);
      expect(page.totalCount, 10);
      final names = page.titles.map((t) => t.title).toList();
      expect(names, [
        '(T)Raumschiff Surprise',
        'Babylon Berlin',
        'Death in Paradise',
        'Dok 1',
        'Die Schlümpfe',
        'Kiwi',
        'Soko Linz',
        'Tom Turbo',
        'Universum',
        'ZIB 1',
      ]);
      expect(names, isNot(contains('ZIB 1 (ÖGS)')));
      final seasons = {for (final t in page.titles) t.title: t.childCount};
      expect((seasons['Death in Paradise'], seasons['Kiwi'], seasons['Dok 1']), (4, 2, null));
    });

    test('a page past the end of the catalogue is empty', () async {
      final page = await OrfFakeSite().provider.listing(replayAllBrowseId, page: 1);
      expect(page.titles, isEmpty);
      expect(page.totalCount, 10);
    });

    test('the newest-first listing reports ORF total', () async {
      final site = OrfFakeSite();
      final page = await site.provider.listing('recent', page: 2);
      expect(page.totalCount, 17351);
      expect(site.requestsTo('api-tvthek.orf.at').last.url.queryParameters['page'], '3');
    });

    test('a genre listing of shows reports ORF total', () async {
      final page = await OrfFakeSite().provider.listing('genre-shows:1178');
      expect(page.totalCount, 95);
      expect(page.titles, hasLength(4));
    });

    test('an unknown listing is empty rather than an error', () async {
      final page = await OrfFakeSite().provider.listing('nothing:1');
      expect(page.titles, isEmpty);
      expect(page.totalCount, 0);
    });

    test('a list item flagged as protected says so', () async {
      final site = OrfFakeSite(
        overrides: {
          'episodes': orfEdited('episodes_page', (json) {
            ((json['_embedded'] as Map)['items'] as List).first['is_drm_protected'] = true;
          }),
        },
      );
      final rails = await site.provider.home();
      final recent = rails.firstWhere((r) => r.id == 'recent');
      expect(recent.titles.single.availability, ReplayAvailability.drmProtected);
    });
  });

  group('OrfTvthekProvider search', () {
    test('finds matching shows first, then programmes and archive items', () async {
      final titles = await OrfFakeSite().provider.search('zib');
      expect(titles.map((t) => t.ref.nativeId), [
        'profile/1203',
        'episode/14343864',
        'episode/14344212',
        'episode/14261364',
      ]);
      expect(titles.first.kind, ReplayKind.show);
    });

    test('the query is sent as one encoded path segment', () async {
      final site = OrfFakeSite();
      await site.provider.search('zeit im bild');
      expect(
        site.requestsTo('api-tvthek.orf.at').map((r) => r.url.path),
        contains('/api/v4.3/search/zeit%20im%20bild'),
      );
    });

    test('a blank or unmatched query returns nothing', () async {
      final provider = OrfFakeSite().provider;
      expect(await provider.search('  '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('an empty profile index leaves the programme results', () async {
      final site = OrfFakeSite(overrides: {'profiles': '{"unexpected":true}'});
      final titles = await site.provider.search('zib');
      expect(titles, isNotEmpty);
      expect(titles.first.ref.nativeId, 'episode/14343864');
    });
  });

  group('OrfTvthekProvider artwork', () {
    test('a programme gets a landscape picture its provider owns', () async {
      final provider = OrfFakeSite().provider;
      final rails = await provider.home();
      final title = rails.firstWhere((r) => r.id == 'lane-mostviewed').titles.first;
      expect(title.backdropUrl, startsWith('https://api-tvthek.orf.at/assets/'));
      expect(provider.ownsImage(title.backdropUrl!), isTrue);
      expect(provider.imageUrl(title.backdropUrl!, width: 300), endsWith('_list.jpg'));
    });

    test('a list without embedded pictures yields none', () async {
      final site = OrfFakeSite(
        overrides: {
          'episodes': orfEdited('episodes_page', (json) {
            for (final item in (json['_embedded'] as Map)['items'] as List) {
              (item as Map).remove('_embedded');
            }
          }),
        },
      );
      final rails = await site.provider.home();
      final recent = rails.firstWhere((r) => r.id == 'recent').titles.single;
      expect(recent.backdropUrl, isNull);
      expect(recent.posterUrl, isNull);
    });

    test('a news synopsis reads as lines, not a bar-joined list', () async {
      final provider = OrfFakeSite().provider;
      final seasons = await provider.children(orfTestRef('profile/1203'));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.last.summary, contains('\n'));
      expect(episodes.last.summary, isNot(contains(' | ')));
    });
  });
}
