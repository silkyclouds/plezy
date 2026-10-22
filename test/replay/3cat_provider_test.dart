import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

import '3cat_fake_site.dart';
import '3cat_playback_cases.dart';
import '3cat_season_cases.dart';
import '3cat_unit_cases.dart';

ReplayRef _ref(String id) => ReplayRef('3cat', id);

void main() {
  group('ThreeCatProvider browsing', () {
    test('home keeps programme and video rows only', () async {
      final rails = await ThreeCatFakeSite().provider().home();
      final names = rails.map((r) => r.title).toList();
      expect(names, containsAll(['Novetats', 'Sèries destacades', 'Entreteniment', 'Grans pel·lícules']));
      expect(names, isNot(contains('Directes')));
      expect(names, isNot(contains('Estic veient')));
      expect(names, isNot(contains('Temàtiques')));
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.title);
        expect(rail.titles.every((t) => t.ref.source == '3cat'), isTrue);
      }
    });

    test('a long home row links to a listing of the same question', () async {
      final rails = await ThreeCatFakeSite().provider().home();
      final novelties = rails.firstWhere((r) => r.title == 'Novetats');
      expect(novelties.moreBrowseId, 'q:tot?frontal=trescat-tresplay-novtotweb');
    });

    test('every request names the app', () async {
      final site = ThreeCatFakeSite();
      await site.provider().home();
      expect(site.userAgents, isNotEmpty);
      expect(site.userAgents.every((ua) => ua == 'Plezy-Replay (+https://github.com/silkyclouds/plezy)'), isTrue);
    });

    test('a category page maps programmes and drops radio shows', () async {
      final provider = ThreeCatFakeSite().provider();
      expect((await provider.categories()).map((c) => c.id), contains('series'));
      final rails = await provider.category('series');
      final titles = rails.single.titles;
      expect(titles.map((t) => t.title), ['Wonderblocks', 'In vitro']);
      expect(titles.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(rails.single.moreBrowseId, 'q:tot?frontal=trescat-tresplseri-prodesweb');
    });

    test('an unknown category is empty', () async {
      expect(await ThreeCatFakeSite().provider().category('nope'), isEmpty);
    });

    test('a listing asks the server for the next page', () async {
      final site = ThreeCatFakeSite();
      final page = await site.provider().listing('q:tot?frontal=trescat-tresplay-novtotweb', page: 2);
      final asked = site.requestsTo('api.3cat.cat').single.queryParameters;
      expect(asked['pagina'], '3');
      expect(asked['items_pagina'], '30');
      expect(asked['frontal'], 'trescat-tresplay-novtotweb');
      expect(page.totalCount, 200);
    });

    test('the whole catalogue is the A-Z page, paged locally', () async {
      final provider = ThreeCatFakeSite().provider();
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 5);
      expect(first.titles.map((t) => t.title), ['10+2', '10 cites', '12 punts', '13 anys i un dia', '13x13']);
      expect(first.titles.first.ref, _ref('p177212487'));
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('an unknown listing id is an empty page', () async {
      final page = await ThreeCatFakeSite().provider().listing('nope');
      expect(page.totalCount, 0);
    });
  });

  group('ThreeCatProvider search', () {
    test('shows come first and articles are dropped', () async {
      final titles = await ThreeCatFakeSite().provider().search('silenci');
      expect(titles.map((t) => t.ref.nativeId), ['p76976', 'p77036', 'v6427755', 'v6430473']);
    });

    test('an empty query asks nothing', () async {
      final site = ThreeCatFakeSite();
      expect(await site.provider().search('  '), isEmpty);
      expect(site.requests, isEmpty);
    });

    test('a query with no hit is empty', () async {
      expect(await ThreeCatFakeSite().provider().search('cap resultat'), isEmpty);
    });

    test('a numbered hit knows its show and season', () async {
      final titles = await ThreeCatFakeSite().provider().search('silenci');
      final episode = titles.firstWhere((t) => t.ref == _ref('v6427755'));
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Silenci (reial monestir de Santa Maria de Poblet)');
      expect(episode.showRef, _ref('p77076'));
      expect(episode.showTitle, 'Patrimonis');
      expect(episode.seasonRef, _ref('p77076/PUTEMP_1'));
      expect((episode.seasonNumber, episode.episodeNumber), (1, 8));
      expect(episode.durationSeconds, 29 * 60 + 53);
    });

    test('a dated news hit belongs to its show without a season', () async {
      final titles = await ThreeCatFakeSite().provider().search('silenci');
      final news = titles.firstWhere((t) => t.ref == _ref('v6430473'));
      expect(news.kind, ReplayKind.episode);
      expect(news.title, 'Telenotícies comarques - 15/10/2026');
      expect(news.seasonRef, _ref('p136938435/_all'));
      expect(news.seasonNumber, isNull);
      expect(news.episodeNumber, isNull);
    });
  });

  group('ThreeCatProvider titles', () {
    test('a show carries its text, year, rating and artwork', () async {
      final show = await ThreeCatFakeSite().provider().title(_ref('p76976'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Wonderblocks');
      expect(show.summary, contains('sèrie educativa'));
      expect(show.summary, isNot(contains('Origen')));
      expect(show.summary, isNot(contains('<')));
      expect(show.year, 2025);
      expect(show.contentRating, 'TP');
      expect(show.posterUrl, 'https://img.3cat.cat/multimedia/jpg/8/9/1791988484198.jpg');
      expect(show.backdropUrl, 'https://img.3cat.cat/multimedia/jpg/0/5/1791988464550.jpg');
      expect(show.logoUrl, 'https://img.3cat.cat/multimedia/png/7/0/1791988281707.png');
    });

    test('a show lists its cast from the characters', () async {
      final show = await ThreeCatFakeSite().provider().title(_ref('p54076'));
      expect(show!.cast, contains('Carlos Cuevas'));
      expect(show.genres, containsAll(['Sèrie dramàtica', 'Ficció']));
      expect(show.contentRating, '13+');
      expect(show.backdropUrl, 'https://img.3cat.cat/multimedia/jpg/2/8/1678793401682.jpg');
    });

    test('a missing programme is null and has no seasons', () async {
      final provider = ThreeCatFakeSite().provider();
      expect(await provider.title(_ref('p1')), isNull);
      expect(await provider.children(_ref('p1')), isEmpty);
    });

    test('a video is described by its media answer', () async {
      final video = await ThreeCatFakeSite().provider().title(_ref('v6431752'));
      expect(video!.title, 'Telenotícies migdia - 21/10/2026');
      expect(video.kind, ReplayKind.episode);
      expect(video.durationSeconds, 3168);
      expect(video.airDate, DateTime.utc(2026, 10, 21, 12, 30));
      expect(video.genres, ['Actualitat']);
      expect(video.summary, contains('Lluís Puig'));
    });

    test('an unknown video and a malformed ref are null', () async {
      final provider = ThreeCatFakeSite().provider();
      expect(await provider.title(_ref('v1')), isNull);
      expect(await provider.title(_ref('zz')), isNull);
      expect(await provider.children(_ref('v6431752')), isEmpty);
    });

    test('the source describes itself in Catalan', () {
      final source = ThreeCatFakeSite().provider().source;
      expect((source.id, source.language), ('3cat', 'ca'));
    });
  });

  threeCatSeasonCases();
  threeCatPlaybackCases();
  threeCatUnitCases();
}
