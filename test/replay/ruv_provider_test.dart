import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ruv/ruv_dates.dart';
import 'package:plezy/replay/providers/ruv/ruv_ids.dart';
import 'package:plezy/replay/providers/ruv/ruv_images.dart';
import 'package:plezy/replay/providers/ruv/ruv_numbering.dart';
import 'package:plezy/replay/providers/ruv/ruv_playback.dart';
import 'package:plezy/replay/providers/ruv/ruv_provider.dart';

import 'ruv_recorded_api.dart';

ReplayRef _ref(Object id) => ReplayRef('ruv', '$id');

Iterable<ReplayTitle> _all(List<ReplayRail> rails) => rails.expand((r) => r.titles);

ReplayTitle _named(Iterable<ReplayTitle> titles, String name) => titles.firstWhere((t) => t.title == name);

void main() {
  late RecordedRuv recorded;
  late RuvProvider provider;

  setUp(() {
    recorded = RecordedRuv();
    provider = recorded.provider();
  });

  group('RuvProvider browsing', () {
    test('home turns each panel into a row of programme cards', () async {
      final rails = await provider.home();
      expect(rails.map((r) => r.id), ['hladbord', 'leiknar-thattaradir', 'vinsaelast', 'kvikmyndir']);
      expect(rails.first.title, 'Hlaðborð');
      expect(_all(rails).every((t) => t.ref.source == 'ruv'), isTrue);
    });

    test('a card uses the programme id, not the unrelated panel id', () async {
      final card = _named(_all(await provider.home()), 'Fleiri pabbahelgar');
      expect(card.ref, _ref(domesticProgram));
      expect(card.kind, ReplayKind.show);
      expect(card.genres, ['Leikið efni']);
      expect(card.posterUrl, isNot(card.backdropUrl));
    });

    test('a single-episode programme filed under films is a movie', () async {
      final titles = _all(await provider.home());
      final film = _named(titles, 'Í takt við tímann');
      expect(film.kind, ReplayKind.movie);
      expect(film.durationSeconds, 5289);
      expect(film.availableUntil, DateTime.utc(2027, 1, 8, 23, 59, 59));
    });

    test('a series filed under films stays a show', () async {
      final rails = await provider.category('kvikmyndir');
      expect(_named(_all(rails), 'Kuldi').kind, ReplayKind.show);
    });

    test('films are told from series with one lookup for the whole list', () async {
      await provider.category('kvikmyndir');
      expect(recorded.queriesWith('episodes(limit:2)'), 1);
      await provider.category('kvikmyndir');
      expect(recorded.queriesWith('episodes(limit:2)'), 1);
    });

    test('categories come from the catalogue with their slugs as ids', () async {
      final categories = await provider.categories();
      expect(categories, hasLength(14));
      expect(categories.first.id, 'annad');
      expect(categories.map((c) => c.title), contains('KrakkaRÚV'));
    });

    test('a short category is one complete row', () async {
      final rails = await provider.category('kvikmyndir');
      expect(rails, hasLength(1));
      expect(rails.single.title, 'Kvikmyndir');
      expect(rails.single.moreBrowseId, isNull);
    });

    test('a long category is cut and offers the full listing', () async {
      final rail = (await provider.category('heimildarefni')).single;
      expect(rail.titles, hasLength(30));
      expect(rail.moreBrowseId, 'heimildarefni');
      final listing = await provider.listing('heimildarefni');
      expect(listing.totalCount, 42);
      expect(listing.titles, hasLength(40));
      expect((await provider.listing('heimildarefni', page: 1)).titles, hasLength(2));
    });

    test('the whole catalogue lists each programme once, by title', () async {
      final first = await provider.listing(replayAllBrowseId);
      final second = await provider.listing(replayAllBrowseId, page: 1);
      final titles = [...first.titles, ...second.titles];
      expect(first.titles, hasLength(provider.source.listingPageSize));
      expect(titles.length, first.totalCount);
      expect(titles.map((t) => t.ref).toSet(), hasLength(titles.length));
      final names = titles.map((t) => t.title.toLowerCase()).toList();
      expect(names, [...names]..sort());
      expect((await provider.listing(replayAllBrowseId, page: 9)).titles, isEmpty);
    });

    test('the whole catalogue is fetched once per category and then reused', () async {
      await provider.listing(replayAllBrowseId);
      final before = recorded.requests.length;
      await provider.listing(replayAllBrowseId, page: 1);
      expect(recorded.requests.length, before);
      expect(recorded.queriesWith('category:'), 14);
    });

    test('search returns one card per programme, in the order of the hits', () async {
      final titles = await provider.search('náttúra');
      expect(titles.map((t) => t.ref.nativeId), [
        '30712',
        '38792',
        '36708',
        '37117',
        '33853',
        '29111',
        '30780',
        '27959',
        '26307',
      ]);
      expect(titles.first.title, 'Krakkafréttir');
      expect(titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('an empty or unmatched search returns nothing', () async {
      expect(await provider.search('zzzz'), isEmpty);
      final before = recorded.requests.length;
      expect(await provider.search('   '), isEmpty);
      expect(recorded.requests.length, before);
    });
  });

  group('RuvProvider shows', () {
    test('a programme has one season holding all its episodes', () async {
      final seasons = await provider.children(_ref(vikinglottoProgram));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref.nativeId, '$vikinglottoProgram/_all');
      expect(seasons.single.kind, ReplayKind.season);
      expect(seasons.single.childCount, 4);
      expect(seasons.single.showRef, _ref(vikinglottoProgram));
    });

    test('the season number comes from the title of the sequel', () async {
      expect((await provider.children(_ref(seriesProgram))).single.seasonNumber, 2);
      expect((await provider.children(_ref(domesticProgram))).single.seasonNumber, 2);
      expect((await provider.children(_ref(vikinglottoProgram))).single.seasonNumber, 1);
    });

    test('episodes are numbered from their stated number in ascending order', () async {
      final season = (await provider.children(_ref(seriesProgram))).single;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      expect(episodes.first.title, 'Þáttur 1 af 13');
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonNumber, 2);
      expect(episodes.first.showTitle, 'Kappsmál II');
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.ref.nativeId, startsWith('$seriesProgram/'));
    });

    test('a catalogue that lists newest first still yields ascending numbers', () async {
      final episodes = await provider.children(ruvSeasonRef(vikinglottoProgram));
      expect(episodes.map((e) => e.episodeNumber), [39, 40, 41, 42]);
      expect(episodes.last.airDate, DateTime.utc(2026, 10, 21, 18, 52));
    });

    test('repeated stated numbers fall back to broadcast order', () async {
      final episodes = await provider.children(ruvSeasonRef(dailyProgram));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      final dates = episodes.map((e) => e.airDate!).toList();
      expect(dates, [...dates]..sort());
    });

    test('an episode without a title of its own takes the programme title', () async {
      final film = (await provider.children(ruvSeasonRef(filmProgram)));
      expect(film.single.title, 'Í takt við tímann');
    });

    test('title resolves a show, its season and an episode', () async {
      final show = await provider.title(_ref(seriesProgram));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Kappsmál II');
      final season = await provider.title(ruvSeasonRef(seriesProgram));
      expect(season!.seasonNumber, 2);
      final first = (await provider.children(season.ref)).first;
      final episode = await provider.title(first.ref);
      expect(episode!.ref, first.ref);
      expect(episode.episodeNumber, 1);
    });

    test('a film is a movie with no children', () async {
      final film = await provider.title(_ref(filmProgram));
      expect(film!.kind, ReplayKind.movie);
      expect(await provider.children(film.ref), isEmpty);
    });

    test('a series filed under films opens as a show with its episodes', () async {
      final show = await provider.title(_ref(filmCategorySeries));
      expect(show!.kind, ReplayKind.show);
      final season = (await provider.children(show.ref)).single;
      expect(await provider.children(season.ref), hasLength(4));
    });

    test('unknown programmes, episodes and foreign refs resolve to nothing', () async {
      expect(await provider.title(_ref(1)), isNull);
      expect(await provider.title(ReplayRef('ruv', '$seriesProgram/zzzzzz')), isNull);
      expect(await provider.title(ReplayRef('ruv', 'banana')), isNull);
      expect(await provider.title(ReplayRef('arte', '$seriesProgram')), isNull);
      expect(await provider.children(_ref(1)), isEmpty);
    });

    test('a file past its expiry date makes the episode expired', () async {
      final later = recorded.provider(clock: DateTime.utc(2027, 1, 9));
      final film = await later.title(_ref(filmProgram));
      expect(film!.availability, ReplayAvailability.expired);
      expect((await later.children(ruvSeasonRef(filmProgram))).single.availability, ReplayAvailability.expired);
      expect((await provider.title(_ref(filmProgram)))!.availability, ReplayAvailability.playable);
    });

    test('a file that never expires has no end date', () async {
      final episode = (await provider.children(ruvSeasonRef(seriesProgram))).first;
      expect(episode.availableUntil, isNull);
    });
  });

  group('RuvProvider playback', () {
    test('a worldwide episode plays its master with the playlist subtitles', () async {
      final playback = await provider.playback(ruvEpisodeRef(newsProgram, newsEpisode));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'ruv-vod.akamaized.net');
      expect(playback.streams.single.url.path, contains('/opid/'));
      expect(playback.subtitles, isEmpty);
    });

    test('an Iceland-only episode is geo-blocked abroad and says why', () async {
      final playback = await provider.playback(ruvEpisodeRef(domesticProgram, domesticEpisode));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('Iceland'));
    });

    test('an Iceland-only episode plays for a viewer the CDN serves', () async {
      recorded.inIceland = true;
      final playback = await provider.playback(ruvEpisodeRef(domesticProgram, domesticEpisode));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, contains('/lokad/'));
    });

    test('a film plays through its programme ref', () async {
      final playback = await provider.playback(_ref(filmProgram));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, contains('/opid/'));
    });

    test('a programme with several episodes is not played as a whole', () async {
      expect((await provider.playback(_ref(filmCategorySeries))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(ruvSeasonRef(seriesProgram))).availability, ReplayAvailability.unknown);
    });

    test('a missing episode or programme is reported as expired', () async {
      expect(
        (await provider.playback(ReplayRef('ruv', '$newsProgram/zzzzzz'))).availability,
        ReplayAvailability.expired,
      );
      expect((await provider.playback(ReplayRef('ruv', '999/zzzzzz'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref(1))).availability, ReplayAvailability.unknown);
    });

    test('an episode past file_expires is expired without touching the CDN', () async {
      recorded.editEpisode = (e) => e['file_expires'] = '2026-10-21';
      final playback = await provider.playback(ruvEpisodeRef(newsProgram, newsEpisode));
      expect(playback.availability, ReplayAvailability.expired);
      expect(recorded.requests.where((r) => r.method == 'GET'), isEmpty);
    });

    test('a missing file is upcoming before broadcast and unknown after', () async {
      recorded.editEpisode = (e) {
        e['file'] = null;
        e['firstrun'] = '2026-10-23T19:45:00';
      };
      expect(
        (await provider.playback(ruvEpisodeRef(newsProgram, newsEpisode))).availability,
        ReplayAvailability.upcoming,
      );
      recorded.editEpisode = (e) => e['file'] = '';
      expect(
        (await provider.playback(ruvEpisodeRef(newsProgram, newsEpisode))).availability,
        ReplayAvailability.unknown,
      );
    });

    test('an episode id that is not a plain token never reaches the query', () async {
      final playback = await provider.playback(ReplayRef('ruv', '$newsProgram/x"]}){id}}'));
      expect(playback.isPlayable, isFalse);
      expect(recorded.requests, isEmpty);
    });

    test('every request carries the identifiable user agent', () async {
      await provider.home();
      await provider.playback(ruvEpisodeRef(newsProgram, newsEpisode));
      expect(recorded.requests, isNotEmpty);
      for (final request in recorded.requests) {
        expect(request.headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
      }
    });

    test('the master of a CDN answer 404 is expired', () {
      final episode = fixture('episode_global')['data']['Program']['episodes'][0] as Map<String, dynamic>;
      final playback = ruvPlaybackFromProbe(episode, Uri.parse('https://ruv-vod.akamaized.net/opid/a/a.m3u8'), (
        status: 404,
        body: '',
      ));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('catalogue subtitles are added only when the playlist lacks them', () {
      final episode = fixture('episode_global')['data']['Program']['episodes'][0] as Map<String, dynamic>;
      final master = Uri.parse(episode['file'] as String);
      final plain = fixtureText(
        'master_global.m3u8',
      ).split('\n').where((l) => !l.contains('TYPE=SUBTITLES')).join('\n');

      final without = ruvPlaybackFromProbe(episode, master, (status: 200, body: plain));
      expect(without.subtitles.single.languageCode, 'is');
      expect(without.subtitles.single.url.host, 'muninn.nyr.ruv.is');

      final withTrack = ruvPlaybackFromProbe(episode, master, (status: 200, body: fixtureText('master_global.m3u8')));
      expect(withTrack.subtitles, isEmpty);
    });
  });

  group('RuvProvider availability', () {
    test('Iceland-only programmes are blocked abroad and worldwide ones are not', () async {
      final titles = _all(await provider.home()).toList();
      final before = recorded.requests.length;
      final verdicts = await provider.predictAvailability(titles, 'BE');
      expect(recorded.requests.length, before);
      expect(verdicts[_ref(domesticProgram)], ReplayAvailability.geoBlocked);
      expect(verdicts[_ref(newsProgram)], ReplayAvailability.playable);
      expect(verdicts[_ref(filmProgram)], ReplayAvailability.playable);
    });

    test('nothing is blocked in Iceland, whatever the case of the code', () async {
      final titles = _all(await provider.home()).toList();
      final verdicts = await provider.predictAvailability(titles, 'is');
      expect(verdicts.values.toSet(), {ReplayAvailability.playable});
    });

    test('programmes not seen in a list are asked for in one batch', () async {
      final refs = [_ref(domesticProgram), ruvSeasonRef(filmProgram), ruvEpisodeRef(newsProgram, newsEpisode), _ref(1)];
      final titles = [for (final r in refs) ReplayTitle(ref: r, kind: ReplayKind.show, title: r.nativeId)];
      final verdicts = await provider.predictAvailability(titles, 'FR');
      expect(recorded.queriesWith('episodes(limit:1){scope}'), 1);
      expect(verdicts, {
        refs[0]: ReplayAvailability.geoBlocked,
        refs[1]: ReplayAvailability.playable,
        refs[2]: ReplayAvailability.playable,
      });
    });

    test('a forecast is remembered, so asking again costs nothing', () async {
      final titles = [ReplayTitle(ref: _ref(domesticProgram), kind: ReplayKind.show, title: 'x')];
      await provider.predictAvailability(titles, 'BE');
      final before = recorded.requests.length;
      await provider.predictAvailability(titles, 'BE');
      expect(recorded.requests.length, before);
    });

    test('refs of another source are left out', () async {
      final foreign = ReplayTitle(ref: ReplayRef('arte', '1'), kind: ReplayKind.show, title: 'x');
      expect(await provider.predictAvailability([foreign], 'BE'), isEmpty);
    });
  });

  group('RuvProvider derivations', () {
    test('the season number is read from roman numerals and small numbers', () {
      expect(ruvSeasonNumber('Kappsmál II'), 2);
      expect(ruvSeasonNumber('Hvolpasveitin IX'), 9);
      expect(ruvSeasonNumber('Kennarinn I'), 1);
      expect(ruvSeasonNumber('Flækjur 3'), 3);
      expect(ruvSeasonNumber('Fleiri pabbahelgar'), 2);
    });

    test('years, radio stations and plain titles give no season number', () {
      expect(ruvSeasonNumber('Gettu betur 1999'), isNull);
      expect(ruvSeasonNumber('Útsvar 2017-2018'), isNull);
      expect(ruvSeasonNumber('Aðventugleði Rásar 2'), isNull);
      expect(ruvSeasonNumber('Kastljós'), isNull);
      expect(ruvSeasonNumber('Molang IIII'), isNull);
      expect(ruvSeasonNumber('X'), isNull);
    });

    test('an episode number is read from the title when none is stated', () {
      expect(ruvStatedEpisodeNumber({'number': 7, 'title': 'Þáttur 3 af 6'}), 7);
      expect(ruvStatedEpisodeNumber({'number': null, 'title': 'Þáttur 3 af 6'}), 3);
      expect(ruvStatedEpisodeNumber({'number': 0, 'title': '5. október 2026'}), isNull);
    });

    test('episodes without any number are ordered by broadcast date', () {
      final numbered = ruvNumberEpisodes([
        {'id': 'b', 'number': null, 'title': 'Seinni', 'firstrun': '2026-10-02T19:00:00'},
        {'id': 'a', 'number': null, 'title': 'Fyrri', 'firstrun': '2026-10-01T19:00:00'},
      ]);
      expect(numbered.map((e) => e.episode['id']), ['a', 'b']);
      expect(numbered.map((e) => e.number), [1, 2]);
    });

    test('times without an offset are read as UTC and 9999 never expires', () {
      expect(ruvDateTime('2026-10-18T21:00:00'), DateTime.utc(2026, 10, 18, 21));
      expect(ruvDateTime('2026-10-21T13:30:28.200000'), DateTime.utc(2026, 10, 21, 13, 30, 28, 200));
      expect(ruvDateTime(null), isNull);
      expect(ruvExpiry('9999-12-31'), isNull);
      expect(ruvExpiry('2027-01-08'), DateTime.utc(2027, 1, 8, 23, 59, 59));
    });

    test('refs split into programme and part', () {
      expect(ruvTarget(_ref(123)), (programId: 123, part: null));
      expect(ruvTarget(ReplayRef('ruv', '123/_all')), (programId: 123, part: '_all'));
      expect(ruvTarget(ReplayRef('ruv', '123/aor501')), (programId: 123, part: 'aor501'));
      expect(ruvTarget(ReplayRef('ruv', 'abc')), isNull);
      expect(ruvTarget(ReplayRef('arte', '123')), isNull);
    });
  });

  group('RÚV images', () {
    final original = fixture('panels')['data']['Featured']['panels'][0]['programs'][0]['image'] as String;

    Map<String, dynamic> recipe(String url) {
      final encoded = url.substring('https://myndir.ruv.is/'.length);
      return jsonDecode(utf8.decode(base64.decode(base64.normalize(encoded)))) as Map<String, dynamic>;
    }

    test('width and height are rewritten and the image stays the same', () {
      final resized = recipe(ruvImageUrl(original, width: 300, height: 450));
      final before = recipe(original);
      expect(resized['edits']['resize'], {'width': 300, 'height': 450});
      expect(resized['bucket'], before['bucket']);
      expect(resized['key'], before['key']);
      expect(resized['edits']['toFormat'], before['edits']['toFormat']);
    });

    test('a width alone resizes proportionally and huge sizes are capped', () {
      expect(recipe(ruvImageUrl(original, width: 640))['edits']['resize'], {'width': 640});
      expect(recipe(ruvImageUrl(original, width: 9000, height: 9000))['edits']['resize'], {
        'width': 1920,
        'height': 2160,
      });
    });

    test('no size, a foreign url or a broken recipe leaves the reference', () {
      expect(ruvImageUrl(original), original);
      expect(ruvImageUrl('https://example.com/a.jpg', width: 300), 'https://example.com/a.jpg');
      expect(ruvImageUrl('https://myndir.ruv.is/not-base64!', width: 300), 'https://myndir.ruv.is/not-base64!');
    });

    test('only its own image host is recognised', () {
      expect(provider.ownsImage(original), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(original, width: 320), isNot(original));
    });
  });
}
