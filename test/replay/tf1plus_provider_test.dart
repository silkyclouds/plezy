import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_api.dart';
import 'package:plezy/replay/providers/tf1plus/tf1plus_provider.dart';

import 'tf1plus_fixture_server.dart';

ReplayRef _ref(String id) => ReplayRef('tf1plus', id);

void main() {
  late Tf1FixtureServer server;
  late Tf1PlusProvider provider;

  setUp(() {
    server = Tf1FixtureServer();
    provider = server.provider();
  });

  test('the source is browse only, in French, with the right id', () {
    expect(provider.source.id, 'tf1plus');
    expect(provider.source.name, 'TF1+');
    expect(provider.source.language, 'fr');
    expect(provider.source.support, ReplayPlaybackSupport.browseOnly);
  });

  group('browsing', () {
    test('categories offer only sections the catalogue can filter', () async {
      final ids = (await provider.categories()).map((c) => c.id);
      expect(ids, containsAll(['series', 'films', 'telefilms', 'jeunesse', 'divertissements', 'lci']));
      expect(ids, isNot(contains('sport')));
      expect(ids, isNot(contains('reportages')));
    });

    test('home keeps the rows that have titles', () async {
      final rails = await provider.home();
      expect(rails.map((r) => r.id), ['series', 'films', 'divertissements']);
      expect(rails.every((r) => r.moreBrowseId == r.id), isTrue);
    });

    test('a category page is one row that opens the full listing', () async {
      final rails = await provider.category('films');
      expect(rails.single.titles, hasLength(3));
      expect(rails.single.moreBrowseId, 'films');
      expect(await provider.category('unknown'), isEmpty);
    });

    test('listing maps series to shows and one-replay programmes to films', () async {
      final series = await provider.listing('series');
      expect(series.totalCount, 506);
      expect(series.titles.map((t) => t.kind).toSet(), {ReplayKind.show});
      expect(series.titles.first.ref, _ref('demain-nous-appartient'));
      expect(series.titles.first.posterUrl, startsWith('https://photos.tf1.fr/'));

      final films = await provider.listing('films');
      expect(films.titles.map((t) => t.kind).toSet(), {ReplayKind.movie});
    });

    test('listing predicts that every title is DRM protected', () async {
      final page = await provider.listing('series');
      expect(page.titles.every((t) => t.availability == ReplayAvailability.drmProtected), isTrue);
    });

    test('a programme repeated on a page is listed once', () async {
      final page = await provider.listing('divertissements');
      expect(page.titles.map((t) => t.ref.nativeId), ['koh-lanta', 'star-academy', 'la-villa-des-coeurs-brises']);
    });

    test('the whole catalogue is paged by index, 20 programmes at a time', () async {
      await provider.listing(replayAllBrowseId, page: 2);
      final sent = server.variablesOf(Tf1Operation.programs).single;
      expect(sent['offset'], 2);
      expect(sent['limit'], 20);
      expect(sent['filter'], {'channel': ''});
    });

    test('a channel section filters on the channel', () async {
      await provider.listing('tmc');
      expect(server.variablesOf(Tf1Operation.programs).single['filter'], {'channel': 'tmc'});
    });

    test('an unknown listing or a page past the end is empty, not an error', () async {
      expect((await provider.listing('nope')).titles, isEmpty);
      expect((await provider.listing('series', page: 40)).titles, isEmpty);
    });

    test('search lists programmes first, then videos with their show', () async {
      final hits = await provider.search('koh lanta');
      expect(hits.first.ref, _ref('koh-lanta'));
      expect(hits.first.kind, ReplayKind.show);
      final video = hits.firstWhere((t) => t.kind == ReplayKind.episode);
      expect(video.showRef, _ref('koh-lanta'));
      expect(video.episodeNumber, 9);
      expect(video.seasonNumber, 34);
    });

    test('an empty or blank query searches nothing', () async {
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('   '), isEmpty);
      expect(server.requests, hasLength(2));
    });
  });

  group('shows', () {
    test('a series lists its seasons in order with their episode counts', () async {
      final seasons = await provider.children(_ref('hpi'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5]);
      expect(seasons.map((s) => s.childCount), everyElement(8));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('hpi')), isTrue);
      expect(seasons[1].ref, _ref('hpi/611169bd645161a2'));
    });

    test('a magazine that files its episodes by year gets one season per year', () async {
      final seasons = await provider.children(_ref('sept-a-huit'));
      expect(seasons.map((s) => s.title), ['2024', '2025', '2026']);
      expect(seasons.map((s) => s.seasonNumber), [2024, 2025, 2026]);
    });

    test('themed seasons are numbered by their position', () async {
      final seasons = await provider.children(_ref('les-anges'));
      expect(seasons.map((s) => s.title), ['Miami', 'Asian dream', 'Back to Miami']);
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
    });

    test('a season lists its episodes with numbers taken from the labels', () async {
      final season = (await provider.children(_ref('hpi')))[1];
      final episodes = await provider.children(season.ref);
      expect(episodes, hasLength(8));
      final first = episodes.first;
      expect(first.kind, ReplayKind.episode);
      expect(first.title, '2300 calories');
      expect(first.seasonNumber, 2);
      expect(first.episodeNumber, 1);
      expect(first.seasonRef, season.ref);
      expect(first.showRef, _ref('hpi'));
      expect(first.showTitle, 'HPI');
      expect(first.durationSeconds, 3115);
      expect(first.backdropUrl, startsWith('https://photos.tf1.fr/'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('a season sent newest first is put in episode order', () async {
      final season = (await provider.children(_ref('les-anges')))[1];
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [108, 109, 110, 111]);
      expect(episodes.last.title, 'Épisode 111');
    });

    test('a year archive keeps the newest-first order of the site', () async {
      final season = (await provider.children(_ref('sept-a-huit')))[1];
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.ref.nativeId).first, 'de083777-be64-4e34-b94d-fe917791b685');
      expect(episodes.every((e) => e.seasonNumber == 2025), isTrue);
    });

    test('a show without season lists has one synthetic season of all replays', () async {
      final seasons = await provider.children(_ref('jt-20h'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('jt-20h/_all'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.childCount, 7);

      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(4));
      expect(episodes.first.seasonNumber, 1);
      expect(episodes.first.episodeNumber, 167);
      expect(episodes.first.airDate, DateTime.utc(2026, 10, 20, 17, 57, 51));
    });

    test('a show with clips only lists the clips', () async {
      final seasons = await provider.children(_ref('pyjamasques-power-heroes-le-cercle-des-heros'));
      final clips = await provider.children(seasons.single.ref);
      expect(clips, hasLength(3));
      expect(clips.map((c) => c.kind).toSet(), {ReplayKind.clip});
    });

    test('a show header carries synopsis, genres, cast and season count', () async {
      final show = (await provider.title(_ref('hpi')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'HPI');
      expect(show.summary, startsWith('Morgane a 38 ans'));
      expect(show.genres, ['Policier', 'Comédie']);
      expect(show.cast, contains('Audrey Fleurot'));
      expect(show.childCount, 5);
      expect(show.posterUrl, contains('program-card-portrait-hpi'));
      expect(show.logoUrl, endsWith('.png'));
      expect(show.durationSeconds, isNull);
      expect(show.availableUntil, isNull);
    });

    test('a film is a movie with year, length and no children', () async {
      final film = (await provider.title(_ref('aquaman')))!;
      expect(film.kind, ReplayKind.movie);
      expect(film.year, 2018);
      expect(film.durationSeconds, 7639);
      expect(film.cast, isNotEmpty);
      expect(await provider.children(film.ref), isEmpty);
    });

    test('a season and an episode can be opened by their own ref', () async {
      final season = (await provider.children(_ref('hpi')))[1];
      expect((await provider.title(season.ref))!.seasonNumber, 2);

      final episode = (await provider.title(_ref(Tf1TestVideo.loginRequired)))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Épisode 236');
      expect(episode.episodeNumber, 236);
      expect(episode.seasonNumber, 18);
      expect(episode.showRef, _ref('plus-belle-la-vie-pblv'));
      expect(episode.availability, ReplayAvailability.loginRequired);
    });

    test('a programme or video TF1+ no longer has is null', () async {
      expect(await provider.title(_ref('gone-show')), isNull);
      expect(await provider.title(_ref(Tf1TestVideo.unknown)), isNull);
      expect(await provider.title(_ref(Tf1TestVideo.notFoundStatus)), isNull);
      expect(await provider.children(_ref('gone-show')), isEmpty);
    });
  });

  group('playback', () {
    test('a replay that needs an account says so', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.loginRequired));
      expect(playback.isPlayable, isFalse);
      expect(playback.availability, ReplayAvailability.loginRequired);
      expect(playback.message, 'Permission insuffisante');
      expect(playback.streams, isEmpty);
    });

    test('a geoblocked clip is reported as geoblocked', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.geoBlockedClip));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('zone'));
    });

    test('a film licensed to France is geoblocked, not login required', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.filmFranceOnly));
      expect(playback.availability, ReplayAvailability.geoBlocked);
    });

    test('a Widevine stream is reported as DRM and never returned', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.widevine));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('widevine'));
    });

    test('a FairPlay stream is reported as DRM and never returned', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.fairplay));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('fairplay'));
    });

    test('a delivery without DRM is the only thing that plays', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.withoutDrm));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'example.invalid');
    });

    test('a video TF1+ cannot find is expired, not an error', () async {
      expect((await provider.playback(_ref(Tf1TestVideo.unknown))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref(Tf1TestVideo.notFoundStatus))).availability, ReplayAvailability.expired);
    });

    test('a film plays through its single replay', () async {
      final playback = await provider.playback(_ref('aquaman'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(server.requests.last.pathSegments.last, Tf1TestVideo.filmFranceOnly);
    });

    test('a show, a season and a missing programme are never played', () async {
      expect((await provider.playback(_ref('hpi'))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(_ref('hpi/611169bd645161a2'))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(_ref('gone-show'))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await provider.playback(_ref(Tf1TestVideo.rateLimited));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });
  });

  group('artwork', () {
    test('references are used as the API returned them', () {
      const url = 'https://photos.tf1.fr/700/933/program-card-portrait-hpi-s5-0e8976-598cad-0@1x.jpg';
      expect(provider.imageUrl(url, width: 300, height: 450), url);
      expect(provider.ownsImage(url), isTrue);
      expect(provider.ownsImage('https://api-cdn.arte.tv/img/v2/image/abc/__SIZE__'), isFalse);
    });
  });
}
