import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_index.dart';

import 'nrktv_forecast_cases.dart';
import 'nrktv_test_support.dart';
import 'nrktv_text_cases.dart';

void main() {
  group('NrkTvProvider source', () {
    test('describes NRK TV as a partly playable Norwegian source', () {
      final source = nrkProvider().source;
      expect([source.id, source.name, source.language], ['nrktv', 'NRK TV', 'no']);
      expect(source.support, ReplayPlaybackSupport.partial);
      expect(nrkProvider(), isA<ReplayAvailabilityPredictor>());
    });
  });

  group('NrkTvProvider browsing', () {
    test('categories are the category pages', () async {
      final categories = await nrkProvider().categories();
      expect(categories.map((c) => c.id), ['drama-serier', 'dokumentar', 'barn', 'dyr', 'familie']);
      expect(categories.first.title, 'Serier');
    });

    test('home keeps rows of titles and drops login prompts and promos', () async {
      final rails = await nrkProvider().home();
      expect(rails.map((r) => r.title), ['Anbefalt', 'Nytt og aktuelt', 'Mest sett']);
      expect(rails.every((r) => r.titles.every((t) => t.ref.source == 'nrktv')), isTrue);
    });

    test('plugs become shows, episodes and movies without live or page links', () async {
      final rails = await nrkProvider().home();
      expect(rails[0].titles.map((t) => t.kind), [ReplayKind.show, ReplayKind.episode]);
      final news = rails[1].titles;
      expect(news.map((t) => t.kind), [ReplayKind.episode, ReplayKind.show, ReplayKind.movie]);
      expect(news.first.showRef, isNotNull);
      expect(news.first.seasonRef, isNotNull);
      expect(news.last.durationSeconds, isNotNull);
    });

    test('a plug with only a fallback picture still gets artwork', () async {
      final show = (await nrkProvider().home())[1].titles[1];
      expect(show.backdropUrl, startsWith('https://gfx.nrk.no/'));
    });

    test('a category page gives the rows of that page', () async {
      final rails = await nrkProvider().category('dokumentar');
      expect(rails.map((r) => r.title), ['Nytt og aktuelt', 'Norske dokumentarfilmer']);
      expect(rails.last.titles, hasLength(3));
    });

    test('listing a category flattens its rows and pages them', () async {
      final provider = nrkProvider();
      final first = await provider.listing('dokumentar');
      final second = await provider.listing('dokumentar', page: 1);
      expect(first.totalCount, first.titles.length);
      expect(second.titles, isEmpty);
    });

    test('the whole catalogue is the A-Z index, letters in order', () async {
      final page = await nrkProvider().listing(replayAllBrowseId);
      expect(page.titles, hasLength(10));
      expect(page.totalCount, 10);
    });

    test('a page of the index loads only the letters it needs', () async {
      final log = <http.Request>[];
      final index = NrkIndex(nrkApi(log: log), () => nrkNow);
      final first = await index.page(0, 4);
      expect(first.titles, hasLength(4));
      expect(first.totalCount, 5 + 4);
      expect(log.where((r) => r.url.path.endsWith('/b/indexelements')), isEmpty);

      final second = await index.page(1, 4);
      expect(second.titles, hasLength(4));
      expect(second.totalCount, 10);
      expect((await index.page(2, 4)).titles, hasLength(2));
      expect((await index.page(3, 4)).titles, isEmpty);
    });

    test('a letter is fetched once while it is kept', () async {
      final log = <http.Request>[];
      final index = NrkIndex(nrkApi(log: log), () => nrkNow);
      await index.page(0, 4);
      await index.page(0, 4);
      expect(log.where((r) => r.url.path.endsWith('/a/indexelements')), hasLength(1));
    });

    test('index rows without rights or repeated are dropped', () async {
      final titles = (await nrkProvider().listing(replayAllBrowseId)).titles;
      expect(titles.map((t) => t.title), isNot(contains('Uten rettigheter')));
      expect(titles.map((t) => t.ref).toSet(), hasLength(titles.length));
      expect(titles.map((t) => t.kind).toSet(), {ReplayKind.show, ReplayKind.movie});
    });

    test('search maps shows, programmes and episodes', () async {
      final hits = await nrkProvider().search('natur');
      expect(hits.map((t) => t.kind), [ReplayKind.show, ReplayKind.show, ReplayKind.movie, ReplayKind.episode]);
      final episode = hits.last;
      expect(episode.title, 'Babblarnas julevise');
      expect(episode.showTitle, 'Babblarna');
      expect(episode.showRef, nrkTestRef('series/babblarna'));
      expect(episode.seasonRef, nrkTestRef('series/babblarna/1'));
      expect(episode.backdropUrl, isNotNull);
    });

    test('search drops hits without rights and repeated hits', () async {
      final hits = await nrkProvider().search('natur');
      expect(hits.map((t) => t.title), isNot(contains('Uten rettigheter')));
      expect(hits.map((t) => t.ref).toSet(), hasLength(hits.length));
    });

    test('a blank search asks nothing and an empty one finds nothing', () async {
      final log = <http.Request>[];
      final provider = nrkProvider(log: log);
      expect(await provider.search('   '), isEmpty);
      expect(log, isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });
  });

  group('NrkTvProvider sequential series', () {
    test('seasons are numbered and listed in order', () async {
      final seasons = await nrkProvider().children(nrkTestRef('series/humoretaten'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4]);
      expect(seasons.map((s) => s.title), ['Sesong 1', 'Sesong 2', 'Sesong 3', 'Sesong 4']);
      expect(seasons.every((s) => s.kind == ReplayKind.season), isTrue);
      expect(seasons.every((s) => s.showRef == nrkTestRef('series/humoretaten')), isTrue);
      expect(seasons.first.ref, nrkTestRef('series/humoretaten/1'));
    });

    test('a season NRK marks as empty is not listed', () async {
      final provider = nrkProvider(
        overrides: {
          '/tv/catalog/series/humoretaten': nrkEdited('series_sequential', (json) {
            final seasons = (json['_embedded'] as Map)['seasons'] as List;
            (seasons[1] as Map)['hasAvailableEpisodes'] = false;
          }),
        },
      );
      final seasons = await provider.children(nrkTestRef('series/humoretaten'));
      expect(seasons.map((s) => s.seasonNumber), [1, 3, 4]);
    });

    test('the show carries its pictures, genre and the poster of a season', () async {
      final show = (await nrkProvider().title(nrkTestRef('series/humoretaten')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Humoretaten');
      expect(show.genres, ['Humor']);
      expect(show.summary, startsWith('Stjernekomikere'));
      expect(show.posterUrl, isNotNull);
      expect(show.backdropUrl, isNotNull);
      expect(show.logoUrl, isNotNull);
      expect(show.childCount, 4);
    });

    test('episodes keep NRK numbers and lose the counter in their title', () async {
      final provider = nrkProvider();
      final episodes = await provider.children(nrkTestRef('series/humoretaten/4'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.first.title, 'Krompen er konge');
      expect(episodes.first.ref, nrkTestRef('program/IUFH21002126'));
      expect(episodes.first.seasonNumber, 4);
      expect(episodes.first.seasonRef, nrkTestRef('series/humoretaten/4'));
      expect(episodes.first.showRef, nrkTestRef('series/humoretaten'));
      expect(episodes.first.showTitle, 'Humoretaten');
    });

    test('an episode carries its details', () async {
      final episode = (await nrkProvider().children(nrkTestRef('series/humoretaten/4'))).first;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.contentRating, '9+');
      expect(episode.cast, contains('Javad El Bakali'));
      expect(episode.durationSeconds, greaterThan(0));
      expect(episode.airDate!.toUtc(), DateTime.utc(2026, 9, 4, 10));
      expect(episode.availableUntil, isNull);
      expect(episode.availability, ReplayAvailability.playable);
      expect(episode.backdropUrl, startsWith('https://gfx.nrk.no/'));
    });

    test('a season without stated numbers is numbered by release date', () async {
      final unnumbered = nrkEdited('season_sequential_4', (json) {
        final episodes = ((json['_embedded'] as Map)['episodes'] as List).cast<Map<String, dynamic>>();
        for (final episode in episodes) {
          episode.remove('sequenceNumber');
          final titles = episode['titles'] as Map<String, dynamic>;
          titles['title'] = (titles['title'] as String).replaceFirst(RegExp(r'^\d+\. '), '');
        }
        (json['_embedded'] as Map)['episodes'] = episodes.reversed.toList();
      });
      final provider = nrkProvider(overrides: {'/tv/catalog/series/humoretaten/seasons/4': unnumbered});
      final episodes = await provider.children(nrkTestRef('series/humoretaten/4'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.first.title, 'Krompen er konge');
      expect(episodes.last.title, 'Er dette en verna bedrift?');
    });

    test('an unknown series has no seasons and no title', () async {
      final provider = nrkProvider();
      expect(await provider.children(nrkTestRef('series/nope')), isEmpty);
      expect(await provider.title(nrkTestRef('series/nope')), isNull);
      expect(await provider.children(nrkTestRef('series/nope/1')), isEmpty);
    });
  });

  group('NrkTvProvider standard and news series', () {
    test('a standard series has one season per year', () async {
      final seasons = await nrkProvider().children(nrkTestRef('series/hestesport'));
      expect(seasons.map((s) => s.seasonNumber), [2014, 2015, 2016, 2017, 2018, 2019, 2021, 2022]);
      expect(seasons.last.title, '2022');
      expect(seasons.last.ref, nrkTestRef('series/hestesport/2022'));
    });

    test('instalments are numbered by release date inside their year', () async {
      final episodes = await nrkProvider().children(nrkTestRef('series/hestesport/2022'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.first.ref, nrkTestRef('program/MSPO31156322'));
      expect(episodes.first.title, 'Dressurridning');
      expect(episodes.every((e) => e.seasonNumber == 2022), isTrue);
      expect(episodes.every((e) => e.showTitle == 'Hestesport'), isTrue);
    });

    test('a news series has one season per month, numbered year and month', () async {
      final seasons = await nrkProvider().children(nrkTestRef('series/dagsrevyen'));
      expect(seasons.map((s) => s.seasonNumber), [202608, 202609, 202610]);
      expect(seasons.last.title, 'Oktober 2026');
    });

    test('news editions are named with their real date, oldest first', () async {
      final episodes = await nrkProvider().children(nrkTestRef('series/dagsrevyen/202610'));
      expect(episodes.map((e) => e.title), [
        '17. oktober · Nye sammenstøt',
        '18. oktober · – Alt er ødelagt',
        '19. oktober · Vil hindre folk i å gå ut',
        '20. oktober · Møtes i Oslo',
        '21. oktober · Orienterte Støre',
        '22. oktober',
      ]);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
    });

    test('tonight edition is upcoming until its time', () async {
      final episodes = await nrkProvider().children(nrkTestRef('series/dagsrevyen/202610'));
      expect(episodes.last.availability, ReplayAvailability.upcoming);
      expect(episodes.take(5).every((e) => e.availability == ReplayAvailability.playable), isTrue);
    });

    test('a series without a season list gets one stand-in season', () async {
      final provider = nrkProvider(
        overrides: {
          '/tv/catalog/series/hestesport': nrkEdited('series_standard', (json) {
            (json['_links'] as Map).remove('seasons');
          }),
        },
      );
      final seasons = await provider.children(nrkTestRef('series/hestesport'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, nrkTestRef('series/hestesport/_all'));
      expect(seasons.single.seasonNumber, 1);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(3));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.first.seasonNumber, 1);
    });

    test('a season resolves by its ref', () async {
      final season = (await nrkProvider().title(nrkTestRef('series/hestesport/2022')))!;
      expect(season.kind, ReplayKind.season);
      expect(season.seasonNumber, 2022);
      expect(await nrkProvider().title(nrkTestRef('series/hestesport/1999')), isNull);
    });
  });

  group('NrkTvProvider programmes', () {
    test('a standalone programme is a movie with its details', () async {
      final movie = (await nrkProvider().title(nrkTestRef('program/OFAA21000105')))!;
      expect(movie.kind, ReplayKind.movie);
      expect(movie.title, 'Været i Norge 2005');
      expect(movie.durationSeconds, 1741);
      expect(movie.year, 2005);
      expect(movie.genres, ['Natur']);
      expect(movie.contentRating, 'A');
      expect(movie.showRef, isNull);
      expect(movie.backdropUrl, isNotNull);
    });

    test('a programme of a counted season is an episode of its show', () async {
      final episode = (await nrkProvider().title(nrkTestRef('program/MSUI42006021')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Babblarnas julevise');
      expect(episode.episodeNumber, 28);
      expect(episode.seasonNumber, 5);
      expect(episode.showRef, nrkTestRef('series/babblarna'));
      expect(episode.seasonRef, nrkTestRef('series/babblarna/5'));
      expect(episode.showTitle, 'Babblarna');
    });

    test('a news programme is dated and belongs to its month', () async {
      final episode = (await nrkProvider().title(nrkTestRef('program/NNFA19102126')))!;
      expect(episode.title, '21. oktober · Orienterte Støre');
      expect(episode.episodeNumber, isNull);
      expect(episode.seasonRef, nrkTestRef('series/dagsrevyen/202610'));
      expect(episode.showTitle, 'Dagsrevyen');
    });

    test('an unknown programme has no title', () async {
      expect(await nrkProvider().title(nrkTestRef('program/NOPE')), isNull);
    });

    test('an id that is not ours has no title, children or stream', () async {
      final provider = nrkProvider();
      expect(await provider.title(nrkTestRef('whatever')), isNull);
      expect(await provider.children(nrkTestRef('program/OFAA21000105')), isEmpty);
      expect((await provider.playback(nrkTestRef('series/humoretaten'))).isPlayable, isFalse);
    });
  });

  group('NrkTvProvider playback', () {
    test('a playable programme yields the master without its query', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/IUFH21002726'));
      expect(playback.isPlayable, isTrue);
      expect(
        playback.streams.single.url.toString(),
        'https://nrk-od-world-45.akamaized.net/open/ps/iufh/iufh21002726/d4866612-21.smil/muxed.m3u8',
      );
      expect(playback.credits, isNull);
    });

    test('Norwegian subtitles come as external files', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/IUFH21002726'));
      final subtitle = playback.subtitles.single;
      expect(subtitle.url.host, 'undertekst.nrk.no');
      expect(subtitle.languageCode, 'nb');
      expect(subtitle.label, contains('Norsk'));
    });

    test('credits start where NRK says the end sequence begins', () async {
      final provider = nrkProvider(
        overrides: {
          '/playback/manifest/program/IUFH21002726': nrkEdited('manifest_playable', (json) {
            (json['playable'] as Map)['endSequenceStartTime'] = 'PT25M10S';
          }),
        },
      );
      final credits = (await provider.playback(nrkTestRef('program/IUFH21002726'))).credits!;
      expect(credits.start, const Duration(minutes: 25, seconds: 10));
      expect(credits.end, const Duration(minutes: 26, seconds: 22, milliseconds: 800));
    });

    test('a programme limited to Norway is geoblocked, in NRK words', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/KMNO10057925'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, 'Ikke tilgjengelig utenfor Norge');
      expect(playback.streams, isEmpty);
    });

    test('a channel manifest is geoblocked too', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/CHANNEL'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
    });

    test('an edition that has not started is upcoming', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/NNFA19102226'));
      expect(playback.availability, ReplayAvailability.upcoming);
      expect(playback.message, startsWith('Kommer'));
    });

    test('rights that have ended are expired', () async {
      final provider = nrkProvider(
        overrides: {
          '/playback/manifest/program/KMNO10057925': nrkEdited('manifest_geoblocked', (json) {
            (json['availability'] as Map)['isGeoBlocked'] = false;
            ((json['availability'] as Map)['onDemand'] as Map)['to'] = '2020-01-01T00:00:00+01:00';
            (json['nonPlayable'] as Map)['messageType'] = 'ProgramRightsHasExpired';
          }),
        },
      );
      expect((await provider.playback(nrkTestRef('program/KMNO10057925'))).availability, ReplayAvailability.expired);
    });

    test('an encrypted asset is reported as protected and never offered', () async {
      final provider = nrkProvider(
        overrides: {
          '/playback/manifest/program/IUFH21002726': nrkEdited('manifest_playable', (json) {
            final asset = ((json['playable'] as Map)['assets'] as List).first as Map;
            asset['encrypted'] = true;
            asset['encryptionScheme'] = 'cenc';
          }),
        },
      );
      final playback = await provider.playback(nrkTestRef('program/IUFH21002726'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a programme NRK no longer has is expired, not an error', () async {
      final playback = await nrkProvider().playback(nrkTestRef('program/GONE00000000'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported and pauses further requests', () async {
      final log = <http.Request>[];
      final provider = nrkProvider(log: log);
      final limited = await provider.playback(nrkTestRef('program/RATELIMITED'));
      expect(limited.isPlayable, isFalse);
      expect(limited.message, contains('30'));
      final sent = log.length;
      final next = await provider.playback(nrkTestRef('program/IUFH21002726'));
      expect(next.isPlayable, isFalse);
      expect(log, hasLength(sent));
    });
  });

  registerNrkForecastCases();
  registerNrkTextCases();
}
