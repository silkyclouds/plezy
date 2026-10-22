import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'err_fake_site.dart';
import 'err_playback_cases.dart';
import 'err_season_cases.dart';
import 'err_unit_cases.dart';

ReplayRef _ref(Object id) => ReplayRef('err', '$id');

Iterable<ReplayTitle> _all(List<ReplayRail> rails) => rails.expand((r) => r.titles);

void main() {
  group('ErrProvider browsing', () {
    test('home drops the promotional banner and keeps named rows', () async {
      final rails = await ErrFakeSite().provider().home();
      expect(rails.map((r) => r.title), ['Enim vaadatud', 'Päevakajaline', 'Mati Põldre 90']);
      expect(_all(rails).every((t) => t.ref.source == 'err'), isTrue);
    });

    test('cards tell programmes from films, episodes and clips', () async {
      final titles = _all(await ErrFakeSite().provider().home());
      expect(titles.firstWhere((t) => t.ref == _ref(1038278)).kind, ReplayKind.show);
      expect(titles.firstWhere((t) => t.ref == _ref(1609334438)).kind, ReplayKind.movie);
      expect(titles.firstWhere((t) => t.ref == _ref(1610171461)).kind, ReplayKind.clip);
      expect(titles.firstWhere((t) => t.ref == _ref(1610094860)).kind, ReplayKind.episode);
    });

    test('an episode card points at its programme', () async {
      final titles = _all(await ErrFakeSite().provider().home());
      final episode = titles.firstWhere((t) => t.ref == _ref(1610094860));
      expect(episode.showRef, _ref(1609403068));
      expect(episode.showTitle, 'La Promesa');
    });

    test('every request names the app', () async {
      final site = ErrFakeSite();
      await site.provider().home();
      final agents = site.requests.map((r) => r.headers['User-Agent']);
      expect(agents, isNotEmpty);
      expect(agents.every((ua) => ua == 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'), isTrue);
    });

    test('a section row links to the genre page of the same name', () async {
      final rails = await ErrFakeSite().provider().category('filmid');
      expect(rails.single.title, 'Eesti');
      expect(rails.single.moreBrowseId, 'eesti');
    });

    test('a genre page is one row linking to its full listing', () async {
      final rails = await ErrFakeSite().provider().category('eesti');
      expect(rails, hasLength(1));
      expect(rails.single.moreBrowseId, 'eesti');
      final kinds = rails.single.titles.map((t) => t.kind).toSet();
      expect(kinds, {ReplayKind.movie, ReplayKind.show});
    });

    test('an unknown category is empty', () async {
      expect(await ErrFakeSite().provider().category('nope'), isEmpty);
    });

    test('categories include the section pages by slug', () async {
      final categories = await ErrFakeSite().provider().categories();
      expect(categories.map((c) => c.id), containsAll(['sarjad', 'filmid', 'v-saated', 'dokumentaal']));
    });

    test('the whole catalogue is sorted A to Z with containers as shows', () async {
      final page = await ErrFakeSite().provider().listing(replayAllBrowseId);
      expect(page.totalCount, 3);
      expect(page.titles.map((t) => t.title), ['"Laine" laulab laevalael', '100 000 minutit ninapidi koos', '1895']);
      expect(page.titles.map((t) => t.kind), [ReplayKind.movie, ReplayKind.show, ReplayKind.movie]);
    });

    test('the catalogue is downloaded once for every page', () async {
      final site = ErrFakeSite();
      final provider = site.provider();
      await provider.listing(replayAllBrowseId);
      final next = await provider.listing(replayAllBrowseId, page: 1);
      expect(next.titles, isEmpty);
      expect(site.requests.where((r) => r.url.path.endsWith('getSeriesData')), hasLength(1));
    });

    test('a genre listing pages through the items of the page', () async {
      final provider = ErrFakeSite().provider();
      final first = await provider.listing('eesti');
      expect(first.totalCount, 6);
      expect(first.titles, hasLength(6));
      expect((await provider.listing('eesti', page: 1)).titles, isEmpty);
    });

    test('a section page lists the cards of its rows once', () async {
      final page = await ErrFakeSite().provider().listing('filmid');
      expect(page.totalCount, 2);
      expect(page.titles.map((t) => t.kind).toSet(), {ReplayKind.movie});
    });

    test('search returns cards and passes the site scope', () async {
      final site = ErrFakeSite();
      final hits = await site.provider().search('loodus');
      expect(hits.map((t) => t.kind).toSet(), {ReplayKind.show});
      final options = jsonDecode(site.requests.last.url.queryParameters['options']!) as Map;
      expect(options['phrase'], 'loodus');
      expect(options['domain'], 'jupiter.err.ee');
      expect(options['rootId'], 3905);
    });

    test('an empty or unmatched search returns nothing', () async {
      final provider = ErrFakeSite().provider();
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('   '), isEmpty);
    });
  });

  group('ErrProvider titles', () {
    test('a film page carries credits, year, length and genres', () async {
      final film = await ErrFakeSite().provider().title(_ref(1210984));
      expect(film!.kind, ReplayKind.movie);
      expect(film.title, 'Kaamera käib! Võte!!!');
      expect(film.year, 2018);
      expect(film.durationSeconds, 1718);
      expect(film.cast, contains('Andrus Vaarik'));
      expect(film.genres, ['Saated', 'Meelelahutus']);
      expect(film.availability, ReplayAvailability.playable);
    });

    test('an episode page knows its programme and season', () async {
      final episode = await ErrFakeSite().provider().title(_ref(1092243));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref(1092236));
      expect(episode.seasonRef, _ref('1092236/1'));
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.summary, isNot(contains('<')));
      expect(episode.durationSeconds, 1590);
    });

    test('a programme id opens the programme, not its first episode', () async {
      final show = await ErrFakeSite().provider().title(_ref(1038279));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Allo Allo!');
      expect(show.childCount, 9);
    });

    test('a copy-protected film is marked as protected in its record', () async {
      final protected = await ErrFakeSite().provider().title(_ref(1608311720));
      expect(protected!.availability, ReplayAvailability.drmProtected);
    });

    test('an unknown id has no title', () async {
      expect(await ErrFakeSite().provider().title(_ref(999)), isNull);
      expect(await ErrFakeSite().provider().title(_ref('abc')), isNull);
    });
  });

  test('a native id with a slash survives a ref round trip', () {
    final ref = ReplayRef.tryParse('err:1038279/2');
    expect(ref, _ref('1038279/2'));
    expect(ReplayRef.tryParse(ref.toString()), ref);
  });

  errSeasonCases();
  errPlaybackCases();
  errUnitCases();
}
