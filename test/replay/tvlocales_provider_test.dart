import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tvlocales/antennecentre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/canalzoom_provider.dart';
import 'package:plezy/replay/providers/tvlocales/telemb_provider.dart';
import 'package:plezy/replay/providers/tvlocales/telesambre_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvcom_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvlux_provider.dart';

import 'tvlocales_fake_site.dart';
import 'tvlocales_fixtures.dart';

void main() {
  group('the six channels', () {
    final providers = <ReplayProvider>[
      TvLuxProvider.withApi(tvLocalesApi(tvLocalesRoute)),
      TeleMbProvider.withApi(tvLocalesApi(tvLocalesRoute)),
      TelesambreProvider.withApi(tvLocalesApi(tvLocalesRoute)),
      TvcomProvider.withApi(tvLocalesApi(tvLocalesRoute)),
      AntenneCentreProvider.withApi(tvLocalesApi(tvLocalesRoute)),
      CanalZoomProvider.withApi(tvLocalesApi(tvLocalesRoute)),
    ];

    test('each has its own id and name, in French', () {
      expect(
        [for (final p in providers) p.source.id],
        ['tvlux', 'telemb', 'telesambre', 'tvcom', 'antennecentre', 'canalzoom'],
      );
      expect(
        [for (final p in providers) p.source.name],
        ['TV Lux', 'Télé MB', 'Télésambre', 'TVCOM', 'Antenne Centre', 'Canal Zoom'],
      );
      expect(providers.every((p) => p.source.language == 'fr'), isTrue);
    });

    test('every channel plays clear streams', () {
      expect(providers.every((p) => p.source.support == ReplayPlaybackSupport.clear), isTrue);
    });

    test('titles carry the source id of their own channel', () async {
      for (final provider in providers) {
        final page = await provider.listing(replayAllBrowseId);
        expect(page.titles, isNotEmpty, reason: provider.source.id);
        expect(page.titles.every((t) => t.ref.source == provider.source.id), isTrue);
      }
    });

    test('each channel owns only artwork from its own site', () {
      const actv = 'https://tvlocales-posters.freecaster.com/videos/actv/a/b/%{SIZE}.jpg';
      expect(providers[1].ownsImage('https://www.telemb.be/cdn/ff/a.png'), isTrue);
      expect(providers[1].ownsImage('https://www.telesambre.be/sites/a.png'), isFalse);
      expect(providers[4].ownsImage(actv), isTrue);
      expect(providers[2].ownsImage(actv), isFalse);
    });

    test('requests go to the channel site and name the app', () async {
      final log = TvLocalesLog();
      await CanalZoomProvider.withApi(tvLocalesApi(tvLocalesRoute, log: log)).listing(replayAllBrowseId);
      final request = log.requests.single;
      expect(request.url.host, 'www.canalzoom.be');
      expect(request.headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
      expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
    });
  });

  group('Drupal channel browsing', () {
    test('the listing keeps the site order and reports the total', () async {
      final page = await fakeTelesambre().listing(replayAllBrowseId);
      expect(page.totalCount, 4);
      expect(page.titles.map((t) => t.title), ['Le JT', 'C à découvrir', 'Pense-Bêtes', 'Arthème']);
      expect(page.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(page.titles.first.posterUrl, startsWith('https://www.telesambre.be/sites/default/files/'));
    });

    test('a page past the end is empty and an unknown listing too', () async {
      final provider = fakeTelesambre();
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
      expect((await provider.listing('nothing')).totalCount, 0);
    });

    test('the show list is fetched once for repeated calls', () async {
      final log = TvLocalesLog();
      final provider = fakeTelesambre(log: log);
      await provider.listing(replayAllBrowseId);
      await provider.search('jt');
      await provider.category('emissions');
      expect(log.paths, ['/emissions']);
    });

    test('search ignores case and accents and needs every word', () async {
      final provider = fakeTelesambre();
      expect((await provider.search('C A DECOUVRIR')).map((t) => t.title), ['C à découvrir']);
      expect((await provider.search('pense betes')).map((t) => t.title), ['Pense-Bêtes']);
      expect(await provider.search('jt pense'), isEmpty);
      expect(await provider.search('  '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('search also finds episodes that were already opened', () async {
      final provider = fakeTelesambre();
      final seasons = await provider.children(sambreRef('le-jt'));
      await provider.children(seasons.first.ref);
      final hits = await provider.search('jt du lundi 19 octobre');
      expect(hits.map((t) => t.kind), [ReplayKind.episode]);
      expect(hits.single.ref.nativeId, 'le-jt/jt-du-lundi-19-octobre-2026/81975');
    });

    test('there is one category, which holds the shows', () async {
      final provider = fakeTelemb();
      expect((await provider.categories()).single.title, 'Émissions');
      final rails = await provider.category('emissions');
      expect(rails.single.titles, hasLength(4));
      expect(await provider.category('unknown'), isEmpty);
    });

    test('home opens with the newest episodes of the news show', () async {
      final rails = await fakeTelemb().home();
      expect(rails.map((r) => r.id), ['latest', 'emissions']);
      expect(rails.first.title, 'Les infos : derniers épisodes');
      expect(rails.first.titles.map((t) => t.kind).toSet(), {ReplayKind.episode});
      expect(rails.first.titles.first.seasonRef, isNull);
      expect(rails.last.titles, hasLength(4));
    });

    test('home still lists the shows when the news show is gone', () async {
      final rails = await AntenneCentreProvider.withApi(tvLocalesApi(tvLocalesRoute)).home();
      expect(rails.map((r) => r.id), ['emissions']);
    });
  });

  group('Drupal channel seasons and episodes', () {
    test('a show with a season filter has one season per filter value', () async {
      final seasons = await fakeTelesambre().children(sambreRef('le-jt'));
      expect(seasons.map((s) => s.title), ['Saison 2024', 'Saison 2023']);
      expect(seasons.map((s) => s.seasonNumber), [2024, 2023]);
      expect(seasons.map((s) => s.ref.nativeId), ['le-jt/~62881', 'le-jt/~59856']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == sambreRef('le-jt')), isTrue);
      expect(seasons.first.showTitle, 'Le JT');
    });

    test('a season lists its episodes newest first, placed in the season', () async {
      final provider = fakeTelesambre();
      final season = (await provider.children(sambreRef('le-jt'))).first;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.ref.nativeId), [
        'le-jt/jt-du-mardi-20-octobre-2026/81976',
        'le-jt/jt-du-lundi-19-octobre-2026/81975',
        'le-jt/jt-du-vendredi-16-octobre-2026/83378',
      ]);
      expect(episodes.every((e) => e.kind == ReplayKind.episode && e.isPlayable), isTrue);
      expect(episodes.every((e) => e.seasonRef == season.ref && e.seasonNumber == 2024), isTrue);
      expect(episodes.first.showTitle, 'Le JT');
      expect(episodes.first.airDate, DateTime.utc(2026, 10, 20, 16, 20));
      expect(episodes.first.durationSeconds, 1200);
      expect(episodes.last.durationSeconds, isNull);
      expect(episodes.first.episodeNumber, isNull);
    });

    test('an older season is requested through the site filter', () async {
      final log = TvLocalesLog();
      final provider = fakeTelesambre(log: log);
      final episodes = await provider.children(sambreRef('le-jt/~59856'));
      expect(episodes.map((e) => e.seasonNumber).toSet(), {2023});
      expect(log.paths.last, '/emission/le-jt?f%5B0%5D=saison%3A59856');
    });

    test('a show without a filter has one synthetic season', () async {
      final seasons = await fakeTelemb().children(mbRef('les-infos'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref.nativeId, 'les-infos/~all');
      expect(seasons.single.title, 'Tous les épisodes');
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.showTitle, 'Les infos');
    });

    test('the synthetic season reads every slice of the list', () async {
      final log = TvLocalesLog();
      final episodes = await fakeTelemb(log: log).children(mbRef('les-infos/~all'));
      expect(episodes, hasLength(5));
      expect(episodes.map((e) => e.seasonRef?.nativeId).toSet(), {'les-infos/~all'});
      expect(log.paths, ['/emission/les-infos', '/emission/les-infos?page=1']);
    });

    test('a failing later slice keeps the episodes already read', () async {
      final episodes = await fakeTelemb().children(mbRef('flaky/~all'));
      expect(episodes, hasLength(3));
    });

    test('a show of articles only has no seasons', () async {
      expect(
        await TvcomProvider.withApi(tvLocalesApi(tvLocalesRoute)).children(ReplayRef('tvcom', 'le-22h30')),
        isEmpty,
      );
    });

    test('a show the site does not know is empty, not an error', () async {
      final provider = fakeTelemb();
      expect(await provider.children(mbRef('gone')), isEmpty);
      expect(await provider.children(mbRef('gone/~all')), isEmpty);
      expect(await provider.title(mbRef('gone')), isNull);
    });

    test('an episode id has no children, and a bad id none either', () async {
      final provider = fakeTelemb();
      expect(await provider.children(mbRef(mbEpisode)), isEmpty);
      expect(await provider.children(mbRef('../etc')), isEmpty);
      expect(await provider.title(mbRef('a b')), isNull);
    });

    test('a show page gives its title and both artworks', () async {
      final show = (await fakeTelemb().title(mbRef('les-infos')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'Les infos');
      expect(show.posterUrl, contains('portrait_large'));
      expect(show.backdropUrl, contains('program_large'));
    });

    test('a season is found by its ref and an unknown one is not', () async {
      final provider = fakeTelesambre();
      expect((await provider.title(sambreRef('le-jt/~59856')))!.title, 'Saison 2023');
      expect(await provider.title(sambreRef('le-jt/~1')), isNull);
    });

    test('an explicit episode number in a title is kept', () async {
      final api = tvLocalesApi((request) {
        final page = tvLocalesSitePage(request);
        if (page == null || request.url.path != '/emission/les-infos') return page;
        final body = tvLocalesFixture('drupal_show_telemb_les_infos_last.html');
        return htmlResponse(body.replaceAll('Les Infos du samedi 10 octobre 2026', 'Les Infos - Épisode 7'));
      });
      final episodes = await TeleMbProvider.withApi(api).children(mbRef('les-infos/~all'));
      expect(episodes.map((e) => e.episodeNumber), [7, null]);
    });
  });
}
