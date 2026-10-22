import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'pbs_fixture_server.dart';

ReplayRef _ref(String nativeId) => ReplayRef('pbs', nativeId);

/// Browsing, grouping into seasons and episodes, search and title lookup against recorded pages.
void pbsCatalogCases() {
  group('PBS browsing', () {
    test('home puts popular shows first, then the front page rows', () async {
      final rails = await PbsFixtureServer().provider().home();
      expect(rails.map((r) => r.title), ['Popular shows', 'Ken Burns Collection']);
      expect(rails.first.titles.map((t) => t.title), ['The Gold', 'PBS News Hour', 'Professor T', 'Maigret']);
      expect(rails.every((r) => r.titles.every((t) => t.kind == ReplayKind.show && t.ref.source == 'pbs')), isTrue);
    });

    test('a genre page keeps its rows in page order and drops stubs', () async {
      final rails = await PbsFixtureServer().provider().category('science-and-nature');
      expect(rails.map((r) => r.title), [
        'Top 10 Science and Nature Shows Today',
        'PBS Digital Studios: Science, Space and Nature Explained',
      ]);
      expect(rails.first.titles.map((t) => t.ref.nativeId), ['show:nova', 'show:nature', 'show:eons']);
    });

    test('an unknown genre has no rows and asks PBS nothing', () async {
      final server = PbsFixtureServer();
      expect(await server.provider().category('../secret'), isEmpty);
      expect(server.requests, isEmpty);
    });

    test('the whole catalogue is every genre merged and sorted by name', () async {
      final provider = PbsFixtureServer().provider();
      final page = await provider.listing(replayAllBrowseId);
      expect(page.totalCount, 8);
      expect(page.titles.map((t) => t.title), [
        'Deep Look',
        'Eons',
        'Nature',
        'NOVA',
        'Overview',
        'PBS Space Time',
        'The National Parks',
        'Weathered',
      ]);
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('the menu offers genres that have shows', () async {
      final categories = await PbsFixtureServer().provider().categories();
      expect(categories.map((c) => c.id), contains('science-and-nature'));
      expect(categories.map((c) => c.id), isNot(contains('passport')));
    });
  });

  group('PBS shows', () {
    test('a show lists its seasons oldest first, with extras and specials', () async {
      final seasons = await PbsFixtureServer().provider().children(_ref('show:frontline'));
      expect(seasons.map((s) => s.title), ['1983', '2022', '2023', '2024', '2025', '2026 extras', 'Specials']);
      expect(seasons.map((s) => s.seasonNumber), [1983, 2022, 2023, 2024, 2025, 2026, 0]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show:frontline')), isTrue);
    });

    test('a season without episodes or clips is not offered', () async {
      final seasons = await PbsFixtureServer().provider().children(_ref('show:frontline'));
      expect(seasons.map((s) => s.seasonNumber), isNot(contains(1990)));
    });

    test('a season lists its episodes by episode number', () async {
      final provider = PbsFixtureServer().provider();
      final season = _ref('season:frontline/$frontline2023');
      final episodes = await provider.children(season);
      expect(episodes.map((e) => e.title), ['Two Strikes/Tutwiler', 'The Astros Edge', 'Inside the Uvalde Response']);
      expect(episodes.map((e) => e.episodeNumber), [14, 16, 20]);
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.seasonNumber == 2023), isTrue);
      expect(episodes.every((e) => e.seasonRef == season && e.showRef == _ref('show:frontline')), isTrue);
      expect(episodes.first.showTitle, 'FRONTLINE');
    });

    test('an episode carries the details a detail page needs', () async {
      final episode = (await PbsFixtureServer().provider().children(_ref('season:frontline/$frontline2023'))).last;
      expect(episode.ref.nativeId, 'video:3084427035/inside-the-uvalde-response-fgxvhb');
      expect(episode.durationSeconds, 3263);
      expect(episode.airDate?.year, 2023);
      expect(episode.backdropUrl, startsWith('https://image.pbs.org/video-assets/'));
      expect(episode.summary, isNot(contains('<')));
      expect(episode.isPlayable, isTrue);
    });

    test('a season with clips only lists clips and previews', () async {
      final provider = PbsFixtureServer().provider();
      final seasons = await provider.children(_ref('show:nova'));
      expect(seasons.map((s) => s.title), ['Season 52 extras', 'Season 53 extras']);

      final clips = await provider.children(_ref('season:nova/$nova53'));
      expect(clips, hasLength(5));
      expect(clips.every((c) => c.kind == ReplayKind.clip && c.episodeNumber == null), isTrue);
      expect(clips.take(3).every((c) => c.seasonNumber == 53), isTrue);
    });

    test('specials form season zero of episodes without numbers', () async {
      final provider = PbsFixtureServer().provider();
      final ref = _ref('season:frontline/specials');
      final specials = await provider.children(ref);
      expect(specials, hasLength(3));
      expect(specials.every((s) => s.kind == ReplayKind.episode && s.seasonNumber == 0), isTrue);
      expect(specials.every((s) => s.episodeNumber == null && s.seasonRef == ref), isTrue);
      expect(specials.first.showTitle, 'FRONTLINE');
      expect((await provider.title(ref))?.title, 'Specials');
    });

    test('a show page gives the requested show with its artwork', () async {
      final show = await PbsFixtureServer().provider().title(_ref('show:frontline'));
      expect(show?.title, 'FRONTLINE');
      expect(show?.genres, ['News and Public Affairs']);
      expect(show?.posterUrl, endsWith('dPXg3dS-show-poster2x3-24fZ2Ik.png'));
    });

    test('a video page gives the show, season and episode', () async {
      final episode = await PbsFixtureServer().provider().title(
        _ref('video:3084427035/inside-the-uvalde-response-fgxvhb'),
      );
      expect(episode?.kind, ReplayKind.episode);
      expect(episode?.showRef, _ref('show:frontline'));
      expect(episode?.showTitle, 'FRONTLINE');
      expect(episode?.seasonNumber, 2023);
      expect(episode?.episodeNumber, 20);
    });

    test('missing shows, videos and malformed ids give null', () async {
      final provider = PbsFixtureServer().provider();
      expect(await provider.title(_ref('show:no-such-show')), isNull);
      expect(await provider.title(_ref('video:1/no-such-video')), isNull);
      expect(await provider.title(_ref('show:../../etc')), isNull);
      expect(await provider.title(_ref('garbage')), isNull);
      expect(await provider.children(_ref('video:3084427035/x')), isEmpty);
    });
  });

  group('PBS search', () {
    test('matching shows come first, then videos without web links', () async {
      final hits = await PbsFixtureServer().provider().search('nova');
      expect(hits.map((t) => t.kind), [
        ReplayKind.show,
        ReplayKind.show,
        ReplayKind.show,
        ReplayKind.episode,
        ReplayKind.episode,
        ReplayKind.movie,
      ]);
      expect(hits.first.title, 'NOVA');
    });

    test('a found episode knows its show and season', () async {
      final hit = (await PbsFixtureServer().provider().search('nova')).firstWhere((t) => t.kind == ReplayKind.episode);
      expect(hit.title, 'Black Hole Apocalypse');
      expect(hit.showRef, _ref('show:nova'));
      expect(hit.seasonNumber, 45);
      expect(hit.episodeNumber, 1);
      expect(hit.seasonRef?.nativeId, startsWith('season:nova/'));
    });

    test('a stand-alone special is a movie without a season', () async {
      final hit = (await PbsFixtureServer().provider().search('nova')).last;
      expect(hit.kind, ReplayKind.movie);
      expect(hit.seasonNumber, isNull);
    });

    test('blank and unmatched queries return nothing', () async {
      final server = PbsFixtureServer();
      final provider = server.provider();
      expect(await provider.search('   '), isEmpty);
      expect(server.requests, isEmpty);
      expect(await provider.search('nothing at all'), isEmpty);
    });
  });
}
