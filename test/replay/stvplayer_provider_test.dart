import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'stvplayer_playback_cases.dart';
import 'stvplayer_test_support.dart';
import 'stvplayer_unit_cases.dart';

void main() {
  group('StvPlayerProvider browsing', () {
    test('categories keep the catalogue order and names', () async {
      final categories = await stvHarness().provider.categories();
      expect(categories.first.id, 'dramas');
      expect(categories.first.title, 'Dramas');
      expect(categories.map((c) => c.id), contains('news-current-affairs'));
    });

    test('home has recent, viewed, popular and news clip rows', () async {
      final rails = await stvHarness().provider.home();
      expect(rails.map((r) => r.id), ['_recent', '_viewed', '_popular', '_clips']);
      expect(rails.every((r) => r.titles.isNotEmpty && r.moreBrowseId == r.id), isTrue);
      expect(rails.first.titles.first.kind, ReplayKind.episode);
      expect(rails.first.titles.first.showTitle, 'Scotland Tonight');
      expect(rails.last.titles.every((t) => t.kind == ReplayKind.clip), isTrue);
    });

    test('a category page offers popular and A to Z rows', () async {
      final rails = await stvHarness().provider.category('dramas');
      expect(rails.map((r) => r.id), ['popular', 'az']);
      expect(rails.last.moreBrowseId, 'dramas');
      expect(rails.last.titles.first.ref.nativeId, 'the-party');
    });

    test('the whole catalogue reports its size and runs out of pages', () async {
      final provider = stvHarness().provider;
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 704);
      expect(first.titles.map((t) => t.ref.nativeId), ['chase-celebrity', 'britains-got-talent', 'taggart']);
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a category listing and the episode feeds page through the server', () async {
      final harness = stvHarness();
      expect((await harness.provider.listing('dramas')).totalCount, 117);
      expect((await harness.provider.listing('_recent')).titles, hasLength(2));
      final request = harness.requests.last;
      expect(request.url.queryParameters['orderBy'], '-availability.from');
      expect(request.url.queryParameters['limit'], '24');
    });

    test('catalogue requests identify the app', () async {
      final harness = stvHarness();
      await harness.provider.categories();
      expect(harness.requests.single.headers['User-Agent'], contains('Plezy-Replay'));
    });
  });

  group('StvPlayerProvider search', () {
    test('finds a programme by name and by synopsis', () async {
      final provider = stvHarness().provider;
      expect((await provider.search('taggart')).map((t) => t.ref.nativeId), ['taggart']);
      expect((await provider.search('Bradley Walsh')).map((t) => t.ref.nativeId), ['chase-celebrity']);
    });

    test('ignores punctuation and case, and puts name matches first', () async {
      final provider = stvHarness().provider;
      expect((await provider.search('CHASE celebrity')).map((t) => t.ref.nativeId), ['chase-celebrity']);
      final hits = await provider.search('talent');
      expect(hits.single.ref.nativeId, 'britains-got-talent');
    });

    test('a blank or unmatched query returns nothing', () async {
      final provider = stvHarness().provider;
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('the programme list is paged by offset, not by page length', () async {
      final harness = stvHarness();
      await harness.provider.search('taggart');
      final offsets = [for (final r in harness.requests) r.url.queryParameters['offset']];
      expect(offsets, ['0', '299']);
    });

    test('the programme list is fetched once for several searches', () async {
      final harness = stvHarness();
      await harness.provider.search('taggart');
      final calls = harness.requests.length;
      await harness.provider.search('talent');
      expect(harness.requests.length, calls);
    });
  });

  group('StvPlayerProvider shows', () {
    test('a programme with series lists one season per series, in order', () async {
      final seasons = await stvHarness().provider.children(stvRef('taggart'));
      expect(seasons, hasLength(27));
      expect(seasons.map((s) => s.seasonNumber), List.generate(27, (i) => i + 1));
      expect(seasons.first.title, 'Series 1');
      expect(seasons.first.ref, stvRef('taggart/taggart-series-1'));
      expect(seasons.first.showRef, stvRef('taggart'));
    });

    test('series named by episode ranges are numbered from one', () async {
      final seasons = await stvHarness().provider.children(stvRef('stv-beat-the-bridge'));
      expect(seasons.map((s) => s.title), ['Episodes 1 - 25', 'Episodes 26 - 50']);
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
    });

    test('a programme without series gets one synthetic season', () async {
      final provider = stvHarness().provider;
      final seasons = await provider.children(stvRef('chase-celebrity'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, stvRef('chase-celebrity/_all'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.childCount, 1);
    });

    test('a series lists its episodes with the series numbering', () async {
      final provider = stvHarness().provider;
      final episodes = await provider.children(stvRef('taggart/taggart-series-1'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.seasonNumber == 1), isTrue);
      expect(episodes.first.seasonRef, stvRef('taggart/taggart-series-1'));
      expect(episodes.first.showTitle, 'Taggart');
      expect(episodes.first.durationSeconds, 7864);
      expect(episodes.first.summary, contains('Contains crime scene violence'));
    });

    test('episodes of a later range series come back in viewing order', () async {
      final episodes = await stvHarness().provider.children(
        stvRef('stv-beat-the-bridge/stv-beat-the-bridge-episodes-26-50'),
      );
      expect(episodes.map((e) => e.episodeNumber), [49, 50]);
      expect(episodes.every((e) => e.seasonNumber == 2), isTrue);
    });

    test('dated episodes of a flat show are listed newest first without numbers', () async {
      final provider = stvHarness().provider;
      final season = (await provider.children(stvRef('scotland-tonight'))).single;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.airDate), [
        DateTime.utc(2026, 10, 21),
        DateTime.utc(2026, 9, 28),
        DateTime.utc(2026, 9, 23),
        DateTime.utc(2026, 9, 22),
      ]);
      expect(episodes.first.title, 'Wed 21 Oct, 10.40 pm');
      expect(episodes.every((e) => e.episodeNumber == null && e.seasonNumber == 1), isTrue);
      expect(episodes.first.seasonRef, season.ref);
    });

    test('an episode page knows its series, number and broadcast date', () async {
      final episode = await stvHarness().provider.title(stvRef('episode:129137'));
      expect(episode!.title, 'Death Trap');
      expect(episode.seasonNumber, 18);
      expect(episode.episodeNumber, 1);
      expect(episode.airDate, DateTime.utc(2002, 1, 14));
      expect(episode.seasonRef, stvRef('taggart/taggart-series-18'));
      expect(episode.genres, ['Drama', 'Crime']);
    });

    test('shows, seasons and clips resolve by reference', () async {
      final provider = stvHarness().provider;
      final show = await provider.title(stvRef('taggart'));
      expect(show!.kind, ReplayKind.show);
      expect(show.childCount, 27);
      expect(show.genres, isNotEmpty);
      final season = await provider.title(stvRef('taggart/taggart-series-2'));
      expect(season!.seasonNumber, 2);
      final clip = await provider.title(stvRef('clip:412286'));
      expect(clip!.kind, ReplayKind.clip);
      expect(clip.durationSeconds, 275);
    });

    test('missing programmes and episodes are null or empty', () async {
      final provider = stvHarness().provider;
      expect(await provider.title(stvRef('no-such-show')), isNull);
      expect(await provider.title(stvRef('episode:1')), isNull);
      expect(await provider.children(stvRef('no-such-show')), isEmpty);
      expect(await provider.children(stvRef('episode:129137')), isEmpty);
    });
  });

  group('StvPlayerProvider availability', () {
    test('a viewer outside the UK sees UK-only episodes as geo-blocked', () async {
      final provider = stvHarness().provider;
      final episodes = (await provider.home()).first.titles;
      final verdicts = await (provider as ReplayAvailabilityPredictor).predictAvailability(episodes, 'BE');
      expect(verdicts.keys.toSet(), episodes.map((e) => e.ref).toSet());
      expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
    });

    test('a viewer in Great Britain gets no verdict', () async {
      final provider = stvHarness().provider;
      final episodes = (await provider.home()).first.titles;
      final predictor = provider as ReplayAvailabilityPredictor;
      expect(await predictor.predictAvailability(episodes, 'GB'), isEmpty);
      expect(await predictor.predictAvailability(episodes, 'gb'), isEmpty);
    });

    test('shows, clips and unseen episodes get no verdict', () async {
      final provider = stvHarness().provider;
      final shows = (await provider.listing(replayAllBrowseId)).titles;
      final clips = (await provider.home()).last.titles;
      final unseen = await provider.title(stvRef('episode:129137'));
      final fresh = stvHarness().provider as ReplayAvailabilityPredictor;
      final predictor = provider as ReplayAvailabilityPredictor;
      expect(await predictor.predictAvailability([...shows, ...clips], 'BE'), isEmpty);
      expect(await fresh.predictAvailability([unseen!], 'BE'), isEmpty);
    });

    test('the home episodes carry the catalogue state, not the viewer', () async {
      final episodes = (await stvHarness().provider.home()).first.titles;
      expect(episodes.every((e) => e.availability == ReplayAvailability.playable), isTrue);
    });
  });

  stvPlaybackCases();
  stvUnitCases();
}
