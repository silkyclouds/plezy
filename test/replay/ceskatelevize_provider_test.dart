import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_api.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_availability.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_images.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_numbering.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_provider.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_queries.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_refs.dart';
import 'package:plezy/replay/providers/ceskatelevize/ceskatelevize_text.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/ceskatelevize';
const _json = {'content-type': 'application/json'};

String _fixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

http.Response _ok(String body) => http.Response.bytes(utf8.encode(body), 200, headers: _json);

http.Response _status(int code, String name, {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(_fixture(name)), code, headers: {..._json, ...headers});

const _vypravej = '10195164142';
const _film = '15618803795';
const _magazine = '10215161238';
const _bigShow = '1000000001';
const _seasonOne = 'season:648cc0fba37aa3214d0e5b62';

/// Serves recorded answers, picking the file from what the query asks for. Anything else is an empty answer.
class _Server {
  final List<String> queries = [];
  final List<http.Request> playlistRequests = [];

  http.Response handle(http.Request request) {
    if (request.method == 'GET') return _playlist(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    queries.add(query);
    final variables = body['variables'] as Map<String, dynamic>? ?? const {};
    return _graphql(query, variables);
  }

  http.Response _graphql(String q, Map<String, dynamic> variables) {
    if (q.contains('CategoryMenu')) return _ok(_fixture('menu'));
    if (q.contains('homepage')) return _ok(_fixture('home'));
    if (q.contains('categoryBlocks')) return _ok(_fixture('category_blocks'));
    if (q.contains('programmeFind')) {
      return _ok(_fixture(q.contains('categoryId:"3947"') ? 'category_films' : 'category_programmes'));
    }
    if (q.contains('searchShows')) {
      return _ok(_fixture(variables['search'] == 'sam a kate' ? 'search_film_shows' : 'search_shows'));
    }
    if (q.contains('searchEpisodes')) return _ok(_searchEpisodes(variables['search'] as String));
    if (q.contains('legacyIdec:"208522161400001"')) return _ok(_fixture('episode_meta'));
    if (q.contains('legacyIdec')) return _ok(_notFound);
    if (q.contains('legacySidpOrIdp')) return _programme(q);
    return _ok('{"data":{}}');
  }

  /// The recorded episode hits, plus the film itself as an episode when the search is for the film.
  String _searchEpisodes(String keyword) {
    final recorded = _fixture(keyword == 'sam a kate' ? 'search_film_episodes' : 'search_episodes');
    if (keyword != 'sam a kate') return recorded;
    final data = jsonDecode(recorded) as Map<String, dynamic>;
    final items = (data['data']['searchEpisodes']['items'] as List).cast<Map<String, dynamic>>();
    items.add({
      'id': '$_film$_filmId',
      'idec': _filmId,
      'sidp': _film,
      'title': 'Sam a Kate',
      'showTitle': 'Sam a Kate',
    });
    return jsonEncode(data);
  }

  http.Response _programme(String q) {
    final sidp = RegExp(r'legacySidpOrIdp:"(\w+)"').firstMatch(q)!.group(1)!;
    final isHeader = q.contains('flatGenres');
    if (sidp == '99999999999') return _ok(_notFound);
    if (q.contains('c0:episodes')) return _ok(_fixture('season_counts'));
    if (!isHeader && !q.contains('totalCount') && q.contains('items{id}')) return _ok(_fixture('film_episode'));
    return switch (sidp) {
      _vypravej => _ok(isHeader ? _fixture('show') : _vypravejEpisodes(q)),
      _film => _ok(_fixture('show_film')),
      _magazine => _ok(_fixture(isHeader ? 'show_magazine' : 'magazine_episodes')),
      _bigShow => _ok(isHeader ? _bigHeader : _bigPage(q)),
      _ => _ok('{"data":{}}'),
    };
  }

  String _vypravejEpisodes(String q) => q.contains(_seasonOne)
      ? _fixture('season_episodes')
      : '{"data":{"programme":{"episodes":{"totalCount":0,"items":[]}}}}';

  http.Response _playlist(http.Request request) {
    playlistRequests.add(request);
    final idec = request.url.pathSegments.last;
    return switch (idec) {
      '226563231000018' || _filmId => _status(200, 'playlist_hls'),
      '225381493710001' => _status(403, 'playlist_geoblocked_be'),
      '286320921360001' => _status(403, 'playlist_drm_unsupported'),
      '213381477310005' => _status(403, 'playlist_missing_licence'),
      '111' => http.Response.bytes(utf8.encode(_embargo), 403, headers: _json),
      '222' => http.Response('{"error":{"type":"OTHER"},"message":{"status":{"name":"OTHER"}}}', 404, headers: _json),
      '429' => http.Response('{}', 429, headers: {..._json, 'retry-after': '30'}),
      _ => http.Response('{}', 404, headers: _json),
    };
  }
}

const _filmId = '22338148974';

const _notFound = '{"data":null,"errors":[{"message":"missing","extensions":{"code":"NOT_FOUND"}}]}';

const _embargo =
    '{"error":{"type":"ResourceLicenceError"},"message":{"status":{"name":"EMBARGO"},'
    '"labels":{"textShort":"Pořad bude dostupný později"}}}';

const _bigHeader =
    '{"data":{"programme":{"sidp":"$_bigShow","title":"Big","showType":"magazine","seasons":[],'
    '"playableEpisodeCount":1000}}}';

/// A show of 1000 episodes, dated one per day: episode `n` aired `n` days after the epoch of this test.
String _bigPage(String q) {
  final newest = q.contains('orderBy:newest');
  final offset = int.parse(RegExp(r'offset:(\d+)').firstMatch(q)!.group(1)!);
  final limit = int.parse(RegExp(r'limit:(\d+)').firstMatch(q)!.group(1)!);
  final items = [
    for (var i = offset; i < offset + limit && i < 1000; i++)
      {
        'id': '${200000000000000 + (newest ? 999 - i : i)}',
        'title': 'Díl ${newest ? 999 - i : i}',
        'date': {'datetime': DateTime.utc(2020).add(Duration(days: newest ? 999 - i : i)).toIso8601String()},
      },
  ];
  return jsonEncode({
    'data': {
      'programme': {
        'episodes': {'totalCount': 1000, 'items': items},
      },
    },
  });
}

final _now = DateTime.utc(2026, 10, 22, 12);

({CeskaTelevizeProvider provider, _Server server}) _setup() {
  final server = _Server();
  final client = MediaServerHttpClient(client: MockClient((r) async => server.handle(r)));
  return (provider: CeskaTelevizeProvider.withApi(CeskaTelevizeApi(client), clock: () => _now), server: server);
}

CeskaTelevizeProvider _provider() => _setup().provider;

ReplayRef _ref(String id) => ReplayRef('ceskatelevize', id);

void main() {
  group('CeskaTelevizeProvider browsing', () {
    test('home drops disabled rows and maps cards to shows', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.id), [
        'nejsledovanejsi',
        'ty-nejlepsi-zahranicni-serialy',
        'filmove-tipy',
        'nove-dokumenty',
        'podcasty',
        'vdavky-a-snatky',
      ]);
      final first = rails.first.titles.first;
      expect(first.ref.source, 'ceskatelevize');
      expect(first.ref.nativeId, startsWith('show-'));
      expect(first.kind, ReplayKind.show);
      expect(first.title, isNot(contains(' ')));
    });

    test('categories come from the menu and use the last category id', () async {
      final categories = await _provider().categories();
      expect(categories, hasLength(14));
      expect(categories.first.id, '3976');
      expect(categories.first.title, 'Seriály');
      expect(categories.map((c) => c.id), contains('4124'));
    });

    test('a category page makes one rail per block with a see-all id', () async {
      final rails = await _provider().category('3976');
      expect(rails, hasLength(13));
      expect(rails.first.id, 'cat:3976:popular_previous_seven_days');
      expect(rails.first.moreBrowseId, rails.first.id);
      expect(rails.any((r) => r.id == 'cat:3976:catchup_broadcast'), isTrue);
      expect(rails.last.title, 'Studentské');
      expect(rails.last.moreBrowseId, isNull);
    });

    test('a listing page asks the server for its own slice', () async {
      final setup = _setup();
      final page = await setup.provider.listing('cat:3983:catchup_broadcast', page: 2);
      expect(page.totalCount, 68);
      expect(page.titles, hasLength(5));
      expect(setup.server.queries.single, allOf(contains('categoryId:"3983"'), contains('offset:200')));
      expect(setup.server.queries.single, contains('orderBy:catchup_broadcast'));
    });

    test('the whole catalogue is the broadcaster all-programmes category', () async {
      final setup = _setup();
      await setup.provider.listing(replayAllBrowseId);
      expect(setup.server.queries.single, contains('categoryId:"0"'));
      expect((await setup.provider.listing('not a category')).titles, isEmpty);
    });

    test('a film card is a movie with its length and year', () async {
      final page = await _provider().listing('3947');
      final film = page.titles.firstWhere((t) => t.title == 'Dým bramborové natě');
      expect(film.kind, ReplayKind.movie);
      expect(film.ref, _ref('film-18784'));
      expect(film.durationSeconds, 95 * 60);
      expect(film.year, 1976);
      expect(page.titles.first.kind, ReplayKind.show);
    });

    test('search returns shows then episodes and ignores short keywords', () async {
      final provider = _provider();
      final hits = await provider.search('příroda');
      expect(hits.take(5).every((t) => t.kind == ReplayKind.show), isTrue);
      final episode = hits.firstWhere((t) => t.kind == ReplayKind.episode);
      expect(episode.ref, _ref('ep-39933633156'));
      expect(episode.showRef, _ref('show-1096893252'));
      expect(episode.showTitle, 'Banánové rybičky');
      expect(await provider.search('př'), isEmpty);
    });

    test('a film found as a show is not repeated as its own episode', () async {
      final hits = await _provider().search('sam a kate');
      expect(hits.where((t) => t.title == 'Sam a Kate'), hasLength(1));
      expect(hits.first.kind, ReplayKind.movie);
    });
  });

  group('CeskaTelevizeProvider shows', () {
    test('a series lists its seasons numbered from the Roman numerals', () async {
      final seasons = await _provider().children(_ref('show-$_vypravej'));
      expect(seasons.map((s) => s.title), [
        'I. řada',
        'II. řada',
        'III. řada',
        'IV. řada',
        'V. řada',
        'Osudy',
        'Filmy o seriálu',
      ]);
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5, 6, 7]);
      expect(seasons.map((s) => s.childCount), [26, 16, 26, 16, 22, 9, 8]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show-$_vypravej')), isTrue);
      expect(seasons.first.ref, _ref('show-$_vypravej/$_seasonOne'));
    });

    test('a season lists its episodes with counters, dates and parents', () async {
      final provider = _provider();
      final season = (await provider.children(_ref('show-$_vypravej'))).first;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      final first = episodes.first;
      expect(first.ref, _ref('ep-208522161400001'));
      expect(first.title, 'Od začátku');
      expect(first.seasonNumber, 1);
      expect(first.seasonRef, season.ref);
      expect(first.showRef, _ref('show-$_vypravej'));
      expect(first.showTitle, 'Vyprávěj');
      expect(first.durationSeconds, 3125);
      expect(first.airDate, DateTime.utc(2026, 1, 9, 9, 35));
      expect(first.backdropUrl, contains('rs:fit:480:270'));
    });

    test('a show without seasons has one synthetic season of dated episodes', () async {
      final provider = _provider();
      final seasons = await provider.children(_ref('show-$_magazine'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('show-$_magazine/_all'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.childCount, 5523);

      final episodes = await provider.children(seasons.single.ref);
      expect(episodes, hasLength(3));
      expect(episodes.first.episodeNumber, isNull);
      expect(episodes.first.seasonNumber, 1);
      expect(episodes.first.seasonRef, seasons.single.ref);
      expect(episodes.first.airDate, DateTime.utc(2017, 1, 1, 11, 40, 20));
    });

    test('a very long list keeps the newest 400 episodes in air order', () async {
      final setup = _setup();
      final episodes = await setup.provider.children(_ref('show-$_bigShow/_all'));
      expect(episodes, hasLength(400));
      expect(episodes.first.title, 'Díl 600');
      expect(episodes.last.title, 'Díl 999');
      expect(episodes.first.airDate!.isBefore(episodes.last.airDate!), isTrue);
      expect(setup.server.queries.where((q) => q.contains('orderBy:newest')), hasLength(8));
    });

    test('a film is a movie as a card and a one-episode show as a page', () async {
      final provider = _provider();
      final card = await provider.title(_ref('film-$_film'));
      expect(card!.kind, ReplayKind.movie);
      expect(card.availableUntil, DateTime.utc(2026, 11, 1, 21, 59, 59));
      expect(card.year, 2022);
      expect(card.durationSeconds, 105 * 60);

      final page = await provider.title(_ref('show-$_film'));
      expect(page!.kind, ReplayKind.show);
      expect(page.ref, _ref('show-$_film'));
      expect(await provider.children(_ref('film-$_film')), isEmpty);
    });

    test('a show header carries genres, credits and artwork', () async {
      final show = await _provider().title(_ref('show-$_vypravej'));
      expect(show!.genres, containsAll(['Komedie', 'Historický', 'Drama']));
      expect(show.genres, isNot(contains('Seriál')));
      expect(show.directors, ['Biser A. Arichtev']);
      expect(show.childCount, 7);
      expect(show.logoUrl, contains('rs:fit:600:280'));
      expect(show.backdropUrl, contains('rs:fit:480:270'));
      expect(show.posterUrl, contains('rs:fit:300/'));
    });

    test('a single episode page has its length and no parents', () async {
      final episode = await _provider().title(_ref('ep-208522161400001'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.durationSeconds, 3125);
      expect(episode.showRef, isNull);
      expect(await _provider().title(_ref('ep-1')), isNull);
    });

    test('unknown programmes and malformed ids give nothing', () async {
      final provider = _provider();
      expect(await provider.title(_ref('show-99999999999')), isNull);
      expect(await provider.children(_ref('show-99999999999')), isEmpty);
      expect(await provider.title(_ref('something-else')), isNull);
      expect(await provider.children(_ref('something-else')), isEmpty);
    });
  });

  group('CeskaTelevizeProvider playback', () {
    test('a playable episode yields HLS, audio description and captions', () async {
      final playback = await _provider().playback(_ref('ep-226563231000018'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams, hasLength(2));
      expect(playback.streams.first.url.host, 'ivys-nw-cdn.o2tv.cz');
      expect(playback.streams.first.label, 'Czech');
      expect(playback.streams.last.label, 'Czech (audio description)');
      expect(playback.subtitles.single.url.path, endsWith('.vtt'));
      expect(playback.subtitles.single.languageCode, 'cs');
      expect(playback.subtitles.single.label, 'Czech (captions)');
    });

    test('the playlist is asked for clear HLS with the plain user agent', () async {
      final setup = _setup();
      await setup.provider.playback(_ref('ep-226563231000018'));
      final request = setup.server.playlistRequests.single;
      expect(request.url.queryParameters, containsPair('canPlayDrm', 'false'));
      expect(request.url.queryParameters, containsPair('streamType', 'hls'));
      expect(request.headers['User-Agent'], startsWith('Plezy-Replay'));
    });

    test('a film is resolved to its episode before the playlist call', () async {
      final setup = _setup();
      final playback = await setup.provider.playback(_ref('film-$_film'));
      expect(playback.isPlayable, isTrue);
      expect(setup.server.playlistRequests.single.url.pathSegments.last, _filmId);
    });

    test('geoblocked, protected and unlicensed titles say why', () async {
      final provider = _provider();
      final geo = await provider.playback(_ref('ep-225381493710001'));
      expect(geo.availability, ReplayAvailability.geoBlocked);
      expect(geo.message, 'ČT nemá práva pro vaše území');
      expect((await provider.playback(_ref('ep-286320921360001'))).availability, ReplayAvailability.drmProtected);
      final licence = await provider.playback(_ref('ep-213381477310005'));
      expect(licence.availability, ReplayAvailability.expired);
      expect(licence.message, 'ČT nemá práva pro internet');
    });

    test('an embargoed title is upcoming', () async {
      final playback = await _provider().playback(_ref('ep-111'));
      expect(playback.availability, ReplayAvailability.upcoming);
      expect(playback.streams, isEmpty);
    });

    test('a missing episode is reported as expired, not as an error', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('ep-222'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('ep-333'))).availability, ReplayAvailability.expired);
    });

    test('a show or season is never played directly', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('show-$_vypravej'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('show-$_vypravej/$_seasonOne'))).availability, ReplayAvailability.unknown);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _provider().playback(_ref('ep-429'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });
  });

  group('CeskaTelevize numbering and text', () {
    test('an episode counter is split off the title', () {
      expect(ceskatelevizeEpisodeName('1/26 Od začátku'), (name: 'Od začátku', number: 1));
      expect(ceskatelevizeEpisodeName('Díl bez čísla'), (name: 'Díl bez čísla', number: null));
      expect(ceskatelevizeEpisodeName('12/10 Datum'), (name: '12/10 Datum', number: null));
      expect(ceskatelevizeEpisodeName('3/10'), (name: '3/10', number: 3));
    });

    test('seasons are numbered from numerals and extras continue', () {
      final numbers = ceskatelevizeSeasonNumbers([
        (id: 'season:a', title: 'II. řada'),
        (id: 'season:b', title: '4. série'),
        (id: 'season:c', title: 'Osudy'),
        (id: 'group:d', title: 'Filmy o seriálu'),
        (id: 'season:e', title: 'Řada IX'),
      ]);
      expect(numbers, [2, 4, 10, 11, 9]);
    });

    test('a credits line becomes directors and cast', () {
      final credits = ceskatelevizeCredits(
        'Režie: J. Novák. Scénář: P. Svoboda. Hrají: A. Černá, B. Bílý a C. Zelený.',
      );
      expect(credits.directors, ['J. Novák']);
      expect(credits.cast, ['A. Černá', 'B. Bílý', 'C. Zelený']);
      expect(ceskatelevizeCredits(null).directors, isEmpty);
    });

    test('an availability label becomes the end of that day', () {
      final now = DateTime.utc(2026, 10, 22, 12);
      expect(ceskatelevizeAvailableUntil('Dostupné do 24. 10.', now), DateTime.utc(2026, 10, 24, 21, 59, 59));
      expect(ceskatelevizeAvailableUntil('Dostupné do 1. 11.', now), DateTime.utc(2026, 11, 1, 21, 59, 59));
      expect(ceskatelevizeAvailableUntil('Dostupné do 3. 1.', now), DateTime.utc(2027, 1, 3, 21, 59, 59));
      expect(ceskatelevizeAvailableUntil('bez data', now), isNull);
      expect(ceskatelevizeDurationSeconds('1 h 35 min'), 5700);
      expect(ceskatelevizeDurationSeconds('88 min'), 5280);
    });

    test('a native id round trips through a ref, colons included', () {
      final ref = ReplayRef.tryParse('ceskatelevize:show-1/$_seasonOne');
      expect(ref, _ref('show-1/$_seasonOne'));
      final id = parseCeskaTelevizeId(ref!.nativeId) as CeskaTelevizeSeasonId;
      expect((id.sidp, id.seasonId, id.isWholeShow), ('1', _seasonOne, false));
      expect(parseCeskaTelevizeId('show-1/x"y'), isNull);
    });
  });

  group('CeskaTelevize images', () {
    test('queries ask for the card sizes the signed URLs carry', () {
      final query = ceskatelevizeProgrammesQuery('3976', limit: 20, offset: 0);
      expect(query, contains('card(width:$ceskatelevizeCardWidth height:$ceskatelevizeCardHeight)'));
      expect(query, contains('cardPortrait(width:$ceskatelevizePortraitWidth)'));
      expect(ceskatelevizeShowQuery('1'), contains('logo(width:600 height:280)'));
    });

    test('a signed image URL is owned and handed through unchanged', () async {
      final provider = _provider();
      const url = 'https://ctfs.ceskatelevize.cz/img/sig/rs:fit:480:270/sh:0.5/plain/s3/a.jpg';
      expect(provider.ownsImage(url), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(url, width: 100, height: 50), url);
      final show = (await provider.listing('3983')).titles.first;
      expect(show.backdropUrl, contains('rs:fit:480:270'));
      expect(show.posterUrl, contains('rs:fit:300/'));
      expect(provider.ownsImage(show.backdropUrl!), isTrue);
    });

    test('a hostile id cannot leave its quotes in a document', () {
      final query = ceskatelevizeShowQuery('1"){id}}#');
      expect(query, contains(r'"1\"){id}}#"'));
      expect(() => ceskatelevizeProgrammesQuery('1', limit: 1, offset: 0, orderBy: 'x){'), throwsArgumentError);
    });
  });
}
