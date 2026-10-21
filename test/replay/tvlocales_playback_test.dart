import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tvlocales/tvcom_provider.dart';

import 'tvlocales_fake_site.dart';
import 'tvlocales_fixtures.dart';

void main() {
  group('episode details', () {
    test('an episode takes duration and poster from the Freecaster video', () async {
      final provider = fakeTelemb();
      final episode = (await provider.title(mbRef(mbEpisode)))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Les Infos du mardi 20 octobre 2026');
      expect(episode.showRef, mbRef('les-infos'));
      expect(episode.showTitle, 'Les infos');
      expect(episode.durationSeconds, 1176);
      expect(episode.summary, 'Retrouvez Les Infos, du lundi au samedi à 18h.');
      expect(provider.ownsImage(episode.backdropUrl!), isTrue);
      expect(
        provider.imageUrl(episode.backdropUrl!, width: 640),
        endsWith('/telemb/a30728c1-8f75-4470-8c04-ff1008c4a6ea/C3UteH5DqyJ3fYhBkGVJ1WyS/640x360.jpg'),
      );
    });

    test('an episode opened from a season keeps that season', () async {
      final provider = fakeTelemb();
      await provider.children(mbRef('les-infos/~all'));
      final episode = (await provider.title(mbRef(mbEpisode)))!;
      expect(episode.seasonRef, mbRef('les-infos/~all'));
      expect(episode.seasonNumber, 1);
    });

    test('an archive video without HD keeps its single poster', () async {
      final episode = (await fakeTvlux().title(luxRef('archeosphere/archeosphere-2eme-partie_19074')))!;
      expect(episode.durationSeconds, 1324);
      expect(episode.backdropUrl, endsWith('/2e2f89f0-df74-343f-ac3d-88023b2fab46-1684335884/640x360.jpg'));
      expect(episode.summary, contains('l\u2019archéologie wallonne'));
      expect(episode.airDate, DateTime.utc(2015, 5, 6, 12, 47));
    });

    test('a refusal from Freecaster leaves the page detail', () async {
      final episode = await fakeTelemb().title(mbRef('les-infos/limited/2'));
      expect(episode, isNotNull);
    });

    test('a page the site no longer has is not an episode', () async {
      expect(await fakeTelemb().title(mbRef('les-infos/gone/9')), isNull);
    });
  });

  group('playback', () {
    test('an episode resolves to the HLS master, with no headers', () async {
      final log = TvLocalesLog();
      final playback = await fakeTelemb(log: log).playback(mbRef(mbEpisode));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.toString(), '$hlsOfTelemb/C3UteH5DqyJ3fYhBkGVJ1WyS.m3u8');
      expect(playback.streams.single.label, 'VF');
      expect(playback.streams.single.headers, isEmpty);
      expect(
        log.requests.last.url.toString(),
        'https://tvlocales-player.freecaster.com/embed/a30728c1-5ff5-4435-a10b-0f0454743de2.json',
      );
    });

    test('the Freecaster request carries no cookie or referer', () async {
      final log = TvLocalesLog();
      await fakeTelemb(log: log).playback(mbRef(mbEpisode));
      final headers = log.requests.last.headers.keys.map((k) => k.toLowerCase());
      expect(headers, isNot(contains('cookie')));
      expect(headers, isNot(contains('referer')));
    });

    test('subtitle files come with the stream', () async {
      final playback = await fakeTvlux().playback(luxRef('jt/jt-du-20-10-2026_52614'));
      expect(playback.isPlayable, isTrue);
      expect(playback.subtitles.single.languageCode, 'fr');
    });

    test('an MP4-only video offers its best rendition', () async {
      final playback = await fakeTelemb().playback(mbRef('les-infos/mp4-only/4'));
      expect(playback.streams.single.url.path, endsWith('_11.mp4'));
    });

    test('an article without a video is not playable and says so', () async {
      final playback = await TvcomProvider.withApi(
        tvLocalesApi(tvLocalesRoute),
      ).playback(ReplayRef('tvcom', 'le-22h30/article/5'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('pas de vidéo'));
    });

    test('a page that is gone is reported as expired', () async {
      expect((await fakeTelemb().playback(mbRef('les-infos/gone/9'))).availability, ReplayAvailability.expired);
    });

    test('a video Freecaster no longer has is reported as expired', () async {
      expect((await fakeTelemb().playback(mbRef('les-infos/expired/1'))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported with its delay, without throwing', () async {
      final playback = await fakeTelemb().playback(mbRef('les-infos/limited/2'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('30'));
    });

    test('a configuration with no stream is unknown, not playable', () async {
      final playback = await fakeTelemb().playback(mbRef('les-infos/no-streams/3'));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('shows, seasons and bad ids are never played', () async {
      final provider = fakeTelemb();
      for (final id in ['les-infos', 'les-infos/~all', '../x']) {
        expect((await provider.playback(mbRef(id))).isPlayable, isFalse, reason: id);
      }
    });
  });

  group('TV Lux', () {
    test('the index lists each show with its image', () async {
      final page = await fakeTvlux().listing(replayAllBrowseId);
      expect(page.titles.map((t) => t.ref.nativeId), [
        'jt',
        'le-22h30-le-journal-de-vivre-ici',
        'l-hebdo',
        'archeosphere',
      ]);
      expect(page.titles.first.posterUrl, 'https://www.tvlux.be/medias/emissions/00000133_info-le-journal.jpeg');
    });

    test('a show has one synthetic season with its newest episodes', () async {
      final log = TvLocalesLog();
      final provider = fakeTvlux(log: log);
      final seasons = await provider.children(luxRef('jt'));
      expect(seasons.single.ref.nativeId, 'jt/~all');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.ref.nativeId), [
        'jt/jt-du-20-10-2026_52614',
        'jt/jt-du-19-10-2026_52613',
        'jt/jt-du-16-10-2026_52612',
        'jt/jt-du-15-10-2026_52611',
        'jt/jt-du-14-10-2026_52610',
      ]);
      expect(episodes.first.title, 'JT du 20/10/2026');
      expect(episodes.first.showTitle, 'JT');
      expect(episodes.first.seasonRef, seasons.single.ref);
      expect(log.paths, ['/replay/jt'], reason: 'one page serves the seasons and the episodes');
    });

    test('home opens with the newest episodes of the JT', () async {
      final rails = await fakeTvlux().home();
      expect(rails.map((r) => r.id), ['latest', 'emissions']);
      expect(rails.first.title, 'JT : derniers épisodes');
      expect(rails.first.titles, hasLength(5));
    });

    test('search finds a show by a word of its name', () async {
      expect((await fakeTvlux().search('hebdo')).map((t) => t.title), ["L'Hebdo"]);
    });
  });
}
