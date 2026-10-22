import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import 'rtbf_test_support.dart';

void main() {
  group('RtbfProvider source', () {
    test('describes Auvio as partly playable French', () {
      final source = rtbfProvider().source;
      expect(source.id, 'auvio');
      expect(source.name, 'Auvio');
      expect(source.language, 'fr');
      expect(source.support, ReplayPlaybackSupport.partial);
    });
  });

  group('RtbfProvider browsing', () {
    test('home keeps programme and media rows and drops the rest', () async {
      final rails = await rtbfProvider().home();
      expect(rails.map((r) => r.id), containsAll(['18601', '22683']));
      expect(rails.every((r) => r.titles.isNotEmpty), isTrue);
      expect(rails.expand((r) => r.titles).every((t) => t.ref.source == 'auvio'), isTrue);
    });

    test('a row the broadcaster fails to serve is skipped, the others stay', () async {
      final rails = await rtbfProvider(
        handler: (request) => request.url.path.endsWith('/widgets/22683') ? rtbfReply({'error': 'x'}, status: 500) : null,
      ).home();

      expect(rails.map((r) => r.id), contains('18601'));
      expect(rails.map((r) => r.id), isNot(contains('22683')));
    });

    test('a row with more pages points to its full grid', () async {
      final rails = await rtbfProvider().home();
      expect(rails.firstWhere((r) => r.id == '22683').moreBrowseId, 'widget:22683');
    });

    test('programme cards are shows or movies, never audio', () async {
      final rails = await rtbfProvider().home();
      final shows = rails.firstWhere((r) => r.id == '22683').titles;
      expect(shows.first.ref, rtbfRef('p32284'));
      expect(shows.first.kind, ReplayKind.show);
      expect(shows.first.posterUrl, contains('/2x3/1248xauto/'));
    });

    test('media cards of a series become numbered episodes', () async {
      final rails = await rtbfProvider().home();
      final episode = rails.firstWhere((r) => r.id == '18601').titles.first;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.seasonNumber, 3);
      expect(episode.episodeNumber, 1);
      expect(episode.showTitle, 'Les Douze - Meurtres au Botox');
      expect(episode.showRef, rtbfRef('p32471'));
      expect(episode.title, "L'enfant aux 1000 visages");
    });

    test('numbered episodes without a season marker are season one', () async {
      final rails = await rtbfProvider().home();
      final episode = rails
          .firstWhere((r) => r.id == '18601')
          .titles
          .firstWhere((t) => t.showTitle == 'Les disparus des Argonnes');
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
    });

    test('a media without numbers is a movie with its tagline', () async {
      final rails = await rtbfProvider().home();
      final movie = rails.firstWhere((r) => r.id == '18601').titles.firstWhere((t) => t.kind == ReplayKind.movie);
      expect(movie.title, startsWith('Hollywood'));
      expect(movie.subtitle, contains('MeToo'));
      expect(movie.showRef, isNull);
    });

    test('categories come from the home row and hide the paid section', () async {
      final categories = await rtbfProvider().categories();
      expect(categories.first.id, 'categorie/series-35');
      expect(categories.first.title, 'Séries');
      expect(categories.any((c) => c.id == 'premium'), isFalse);
    });

    test('a category page opens by its path and refuses odd ids', () async {
      final provider = rtbfProvider();
      expect(await provider.category('categorie/series-35'), isNotEmpty);
      expect(await provider.category('../users/me'), isEmpty);
      expect(await provider.category('categorie/unknown-1'), isEmpty);
    });

    test('the whole-catalogue listing drops audio and ends exactly', () async {
      final provider = rtbfProvider();
      final page = await provider.listing(replayAllBrowseId);
      expect(page.titles, hasLength(10));
      expect(page.titles.any((t) => t.title.contains('Podcast')), isFalse);
      expect(page.totalCount, 10);
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a row grid lists the widget behind it', () async {
      final page = await rtbfProvider().listing('widget:22683');
      expect(page.titles.first.ref, rtbfRef('p32284'));
    });

    test('an unknown browse id lists nothing', () async {
      expect((await rtbfProvider().listing('nonsense')).titles, isEmpty);
    });
  });

  group('RtbfProvider search', () {
    test('programmes come before media and paid offers are skipped', () async {
      final titles = await rtbfProvider().search('planete');
      final firstMedia = titles.indexWhere((t) => t.ref.nativeId.startsWith('m'));
      expect(titles.take(firstMedia).every((t) => t.ref.nativeId.startsWith('p')), isTrue);
      expect(titles.any((t) => t.ref.nativeId == 'm3261284'), isFalse);
    });

    test('audio programmes and audio media are left out', () async {
      final titles = await rtbfProvider().search('planete');
      expect(titles.any((t) => t.ref.nativeId == 'p23855'), isFalse);
      expect(titles.any((t) => t.ref.nativeId == 'm3540154'), isFalse);
      expect(titles.any((t) => t.ref.nativeId == 'p23824'), isTrue);
    });

    test('an empty or unmatched query returns nothing', () async {
      final provider = rtbfProvider();
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });
  });

  group('RtbfProvider shows', () {
    test('a series lists one season per tab with numbers and counts', () async {
      final seasons = await rtbfProvider().children(rtbfRef('p32284'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5]);
      expect(seasons.map((s) => s.childCount), [6, 7, 7, 7, 7]);
      expect(seasons.first.ref, rtbfRef('p32284/s1'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == rtbfRef('p32284')), isTrue);
    });

    test('a season lists episodes with numbers read from the subtitle', () async {
      final provider = rtbfProvider();
      final season = (await provider.children(rtbfRef('p32284'))).firstWhere((s) => s.seasonNumber == 2);
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.first.title, 'Visite guidée');
      expect(episodes.first.seasonNumber, 2);
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.showRef, rtbfRef('p32284'));
      expect(episodes.first.showTitle, 'Ghosts');
      expect(episodes.first.durationSeconds, 1778);
      expect(episodes.first.contentRating, '-10');
      expect(episodes.first.backdropUrl, contains('/16x9/770x433/'));
    });

    test('episodes that need an account are flagged from the asset rights', () async {
      final provider = rtbfProvider();
      final episodes = await provider.children(rtbfRef('p32284/s2'));
      expect(episodes.every((e) => e.availability == ReplayAvailability.loginRequired), isTrue);
    });

    test('year tabs become seasons numbered by year', () async {
      final seasons = await rtbfProvider().children(rtbfRef('p29169'));
      expect(seasons.map((s) => s.ref.nativeId), ['p29169/y2026', 'p29169/y2025']);
      expect(seasons.map((s) => s.seasonNumber), [2026, 2025]);
      expect(seasons.first.childCount, 5);
    });

    test('magazine episodes have a title and no episode number', () async {
      final episodes = await rtbfProvider().children(rtbfRef('p29169/y2026'));
      expect(episodes, hasLength(3));
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.title, "L'approche régionale de la RTBF");
      expect(episodes.first.showTitle, 'Table Média');
      expect(episodes.first.episodeNumber, isNull);
      expect(episodes.first.seasonNumber, 2026);
      expect(episodes.first.availability, ReplayAvailability.playable);
    });

    test('numbered episodes in one tab with no season marker are season one', () async {
      final provider = rtbfProvider();
      final seasons = await provider.children(rtbfRef('p32462'));
      expect(seasons.map((s) => s.ref.nativeId), ['p32462/n1']);
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Saison 1');
      expect(seasons.single.childCount, 12);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(episodes.every((e) => e.seasonNumber == 1 && e.seasonRef == seasons.single.ref), isTrue);
    });

    test('one tab holding two seasons becomes two seasons', () async {
      final cards = [
        for (final (season, episode) in [(1, 1), (1, 2), (2, 1)])
          {
            'resourceType': 'MEDIA',
            'type': 'VIDEO',
            'id': '${360000 + season * 10 + episode}',
            'programId': 32462,
            'title': 'Louca  S0$season',
            'subtitle': '0$episode - Episode $episode',
          },
      ];
      final provider = rtbfProvider(
        handler: (request) => request.url.path.endsWith('/widgets/18800')
            ? rtbfReply({
                'data': {'content': cards},
                'links': {'next': null},
              })
            : null,
      );
      final seasons = await provider.children(rtbfRef('p32462'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.map((s) => s.childCount), [2, 1]);
      final second = await provider.children(rtbfRef('p32462/n2'));
      expect(second.map((e) => e.ref.nativeId), ['m360021']);
      expect(second.single.seasonNumber, 2);
    });

    test('a magazine with one tab keeps it as one season of every episode', () async {
      final provider = rtbfProvider();
      final seasons = await provider.children(rtbfRef('p29170'));
      expect(seasons.map((s) => s.ref.nativeId), ['p29170/all']);
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Tous les épisodes');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(3));
      expect(episodes.every((e) => e.seasonNumber == 1 && e.episodeNumber == null), isTrue);
    });

    test('a single year tab is one season, not a season numbered by year', () async {
      final provider = rtbfProvider();
      final seasons = await provider.children(rtbfRef('p29171'));
      expect(seasons.map((s) => s.ref.nativeId), ['p29171/all']);
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Année 2026');
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(3));
      expect(episodes.every((e) => e.seasonNumber == 1), isTrue);
    });

    test('a season that no longer exists has no episodes', () async {
      expect(await rtbfProvider().children(rtbfRef('p32284/s9')), isEmpty);
    });

    test('a one-off programme is a movie with no children', () async {
      final provider = rtbfProvider();
      final film = await provider.title(rtbfRef('p32596'));
      expect(film!.kind, ReplayKind.movie);
      expect(film.title, 'Harceleurs');
      expect(film.durationSeconds, 5379);
      expect(film.availability, ReplayAvailability.loginRequired);
      expect(await provider.children(film.ref), isEmpty);
    });

    test('a show page keeps the poster of the card it was opened from', () async {
      final provider = rtbfProvider();
      await provider.home();
      final show = await provider.title(rtbfRef('p32284'));
      expect(show!.kind, ReplayKind.show);
      expect(show.childCount, 5);
      expect(show.posterUrl, contains('/2x3/'));
      expect(show.backdropUrl, contains('/media/program/background/'));
      expect(show.summary, isNot(endsWith(' ')));
    });

    test('audio programmes and unknown ids are not titles', () async {
      final provider = rtbfProvider();
      expect(await provider.title(rtbfRef('p21283')), isNull);
      expect(await provider.children(rtbfRef('p21283')), isEmpty);
      expect(await provider.title(rtbfRef('p1')), isNull);
      expect(await provider.title(rtbfRef('m1')), isNull);
    });

    test('a season title is found by its reference', () async {
      final season = await rtbfProvider().title(rtbfRef('p32284/s3'));
      expect(season!.kind, ReplayKind.season);
      expect(season.seasonNumber, 3);
    });
  });

  group('RtbfProvider media pages', () {
    test('an episode page knows its show, numbers, cast and crew', () async {
      final episode = await rtbfProvider().title(rtbfRef('m3507958'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, rtbfRef('p32284'));
      expect(episode.seasonNumber, 2);
      expect(episode.episodeNumber, 1);
      expect(episode.directors, ['Tom Kingsley']);
      expect(episode.cast, contains('Charlotte Ritchie'));
      expect(episode.cast, isNot(contains('Tom Kingsley')));
      expect(episode.genres, ['Comédie']);
      expect(episode.availability, ReplayAvailability.loginRequired);
    });

    test('a media page takes its picture from the page, which has none in its content', () async {
      final episode = await rtbfProvider().title(rtbfRef('m3507958'));
      expect(episode!.backdropUrl, startsWith('https://static-content.rtbf.be/image/media/object/'));
    });

    test('a film without a programme is a movie with its crew', () async {
      final film = await rtbfProvider().title(rtbfRef('m3530011'));
      expect(film!.kind, ReplayKind.movie);
      expect(film.directors, ['Steven Spielberg']);
      expect(film.cast, isNot(contains('Ernest Cline')));
      expect(film.airDate, DateTime.utc(2026, 10, 18, 21, 36));
      expect(film.availableUntil, DateTime.utc(2026, 10, 25, 22, 55));
    });

    test('an episode of a magazine belongs to its programme', () async {
      final episode = await rtbfProvider().title(rtbfRef('m3516005'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, rtbfRef('p29169'));
      expect(episode.availability, ReplayAvailability.playable);
    });

    test('titles past their window are expired', () async {
      final provider = rtbfProvider(now: DateTime.utc(2026, 12, 1));
      final film = await provider.title(rtbfRef('m3530011'));
      expect(film!.availability, ReplayAvailability.expired);
    });
  });

  group('RtbfProvider playback', () {
    test('a clear programme yields its HLS master only', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3516005'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams, hasLength(1));
      expect(playback.streams.single.url.path, endsWith('/vod-idx.ism/.m3u8'));
      expect(playback.streams.single.label, 'Auvio');
    });

    test('a programme with subtitles still yields one HLS stream', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3529347'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('.m3u8'));
    });

    test('an audio-only item yields its MP3', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3541035'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('.mp3'));
      expect(playback.streams.single.label, 'Audio');
    });

    test('a DRM-protected programme is reported and offers no stream', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3516216'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a programme that needs an account says so', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3507958'));
      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.message, contains('compte'));
    });

    test('a paid offer is reported as needing an account', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3532118'));
      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.message, contains('payante'));
    });

    test('a geoblocked programme says why', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3600001'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
    });

    test('a publication that starts later is upcoming', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3600002'));
      expect(playback.availability, ReplayAvailability.upcoming);
    });

    test('a removed programme is reported as expired', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m9999999'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await rtbfProvider().playback(rtbfRef('m3600003'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a one-off programme plays through its film', () async {
      final playback = await rtbfProvider().playback(rtbfRef('p32596'));
      expect(playback.availability, ReplayAvailability.loginRequired);
    });

    test('shows and seasons are never played directly', () async {
      final provider = rtbfProvider();
      expect((await provider.playback(rtbfRef('p32284'))).isPlayable, isFalse);
      expect((await provider.playback(rtbfRef('p32284/s1'))).isPlayable, isFalse);
    });

    test('the session is opened once and sent as a bearer token', () async {
      final log = <http.Request>[];
      final provider = rtbfProvider(log: log);
      await provider.playback(rtbfRef('m3516005'));
      await provider.playback(rtbfRef('m3529347'));
      expect(log.where((r) => r.url.path.endsWith('/auth/anonymous')), hasLength(1));
      final play = log.firstWhere((r) => r.url.path.contains('/entitlement/'));
      expect(play.headers['Authorization'], 'Bearer <redacted>');
      expect(play.url.queryParameters['supportedFormats'], 'hls,mp3');
      expect(play.headers['User-Agent'], startsWith('Plezy-Replay'));
    });

    test('a rejected token is replaced once and the request repeated', () async {
      final log = <http.Request>[];
      var sessions = 0;
      final provider = rtbfProvider(
        log: log,
        handler: (request) {
          if (request.url.path.endsWith('/auth/anonymous')) {
            sessions++;
            return rtbfReply({
              'sessionToken': sessions == 1 ? 'stale' : '<redacted>',
              'expirationDateTime': '2026-11-20T07:35:11Z',
            });
          }
          return null;
        },
      );
      final playback = await provider.playback(rtbfRef('m3516005'));
      expect(sessions, 2);
      expect(playback.isPlayable, isTrue);
    });
  });

  test('a native id with a slash survives a ref round trip', () {
    final ref = ReplayRef.tryParse('auvio:p32284/s2');
    expect(ref, rtbfRef('p32284/s2'));
    expect(ReplayRef.tryParse(ref.toString()), ref);
  });
}
