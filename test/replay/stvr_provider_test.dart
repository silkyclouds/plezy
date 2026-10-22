import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/stvr/stvr_api.dart';
import 'package:plezy/replay/providers/stvr/stvr_cards.dart';
import 'package:plezy/replay/providers/stvr/stvr_numbering.dart';
import 'package:plezy/replay/providers/stvr/stvr_provider.dart';
import 'package:plezy/replay/providers/stvr/stvr_time.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/stvr';

String _fixture(String name) => File('$_fixtures/$name').readAsStringSync();

const _emptyPage = '{"paging":{"page":"1","size":"100","results":"0"},"program":[]}';
const _json = {'content-type': 'application/json; charset=UTF-8'};
const _html = {'content-type': 'text/html; charset=utf-8'};

final _requests = <Uri>[];
final _userAgents = <String?>[];

http.Response _ok(String body, {Map<String, String> headers = const {}}) => http.Response(body, 200, headers: headers);

http.Response _archive(Map<String, String> q) {
  final fixture = switch ((q['s'], q['q'], q['d'])) {
    ('24085', _, _) => 'season_xii.json',
    ('23883', _, _) => 'season_xi.json',
    ('21414', _, _) => 'episodes_parts_21414.json',
    ('7993', _, _) => 'episodes_series_7993.json',
    (_, 'Detektívi zo severu', _) => 'search_q_detektivi.json',
    (_, 'poirot', _) => 'search_programmes_q.json',
    (_, _, '2026-10-22') => 'day_2026_10_22.json',
    (null, null, null) => 'latest_programmes.json',
    _ => null,
  };
  return _ok(fixture == null ? _emptyPage : _fixture(fixture), headers: _json);
}

http.Response _siteSearch(String? query) => query == 'poirot'
    ? _ok(_fixture('search_lite.json'), headers: _json)
    : _ok('{"total":"0","blocks":{}}', headers: _json);

http.Response _stream(String id) => switch (id) {
  '624605' => _ok(_fixture('stream_json.json'), headers: _json),
  '625879' => _ok(_fixture('stream_json_geolock.json'), headers: _json),
  '111' => _ok(_fixture('stream_json_no_source.json'), headers: _json),
  '429' => http.Response('{}', 429, headers: {'retry-after': '30'}),
  _ => http.Response('{"IP":"0.0.0.0"}', 404, headers: _json),
};

http.Response _cdn(Uri url) {
  final blocked = url.host == 'n10.stv.livebox.sk';
  if (url.path.endsWith('playlist.m3u8')) return _ok(_fixture(blocked ? 'master_geolock.m3u8' : 'master.m3u8'));
  if (url.path.endsWith('chunklist-v1-a1.m3u8')) {
    return _ok(_fixture(blocked ? 'media_playlist_geolock_head.m3u8' : 'media_playlist_ok_head.m3u8'));
  }
  return http.Response('', 404);
}

http.Response _route(http.Request request) {
  _requests.add(request.url);
  _userAgents.add(request.headers['user-agent']);
  final url = request.url;
  if (url.host.endsWith('livebox.sk')) return _cdn(url);
  return switch (url.path) {
    '/json/tv/archiv' => _archive(url.queryParameters),
    '/json/search/lite' => _siteSearch(url.queryParameters['q']),
    '/json/archive5f.json' => _stream(url.queryParameters['id']!),
    '/televizia/archiv/serialy' => _ok(_fixture('category_serialy.html'), headers: _html),
    _ when url.path.startsWith('/televizia/archiv/') => _ok('<html></html>', headers: _html),
    _ => http.Response('{}', 404),
  };
}

StvrProvider _provider({DateTime? now}) {
  final client = MediaServerHttpClient(client: MockClient((r) async => _route(r)));
  return StvrProvider.withApi(StvrApi(client), now: () => now ?? DateTime.utc(2026, 10, 22, 8));
}

ReplayRef _ref(String id) => ReplayRef('stvr', id);

void main() {
  setUp(() {
    _requests.clear();
    _userAgents.clear();
  });

  group('StvrProvider browsing', () {
    test('the source is Slovak and partly playable', () {
      final source = _provider().source;
      expect(source.id, 'stvr');
      expect(source.language, 'sk');
      expect(source.support, ReplayPlaybackSupport.partial);
    });

    test('categories are the archive sections of the site', () async {
      final categories = await _provider().categories();
      expect(categories.map((c) => c.id), containsAll(['serialy', 'filmy', 'dokument', 'spravodajstvo']));
    });

    test('home leads with the latest recordings and keeps non-empty rows', () async {
      final rails = await _provider().home();
      expect(rails.first.id, 'latest');
      expect(rails.first.moreBrowseId, replayAllBrowseId);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.episode && t.ref.source == 'stvr'), isTrue);
      expect(rails.map((r) => r.id), ['latest', 'serialy']);
      expect(rails.last.titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('a section page maps its cards to shows with pictures', () async {
      final rails = await _provider().category('serialy');
      final shows = rails.single.titles;
      expect(shows, hasLength(5));
      expect(shows.first.title, 'Kenguria pláž');
      expect(shows.first.ref, _ref('23211'));
      expect(shows.first.backdropUrl, startsWith('https://www.stvr.sk/media/'));
    });

    test('an unknown section is empty and never reaches the network', () async {
      final provider = _provider();
      expect(await provider.category('../etc'), isEmpty);
      expect((await provider.listing('nope')).titles, isEmpty);
      expect(_requests, isEmpty);
    });

    test('a section listing reports the size the page states', () async {
      final page = await _provider().listing('serialy', page: 1);
      expect(page.totalCount, 52);
      expect(page.titles, hasLength(5));
      expect(_requests.single.queryParameters['page'], '2');
    });

    test('the whole catalogue lists the newest recordings first', () async {
      final page = await _provider().listing(replayAllBrowseId);
      expect(page.totalCount, 95521);
      expect(page.titles.first.airDate, DateTime.utc(2026, 10, 22, 4, 30));
    });

    test('requests carry the identifiable user agent', () async {
      await _provider().listing(replayAllBrowseId);
      expect(_userAgents.single, 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
    });
  });

  group('StvrProvider shows and seasons', () {
    test('a numbered series drops its numeral from the show name', () async {
      final show = await _provider().title(_ref('24085'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Detektívi zo severu');
    });

    test('series sharing a base name become seasons in numeral order', () async {
      final seasons = await _provider().children(_ref('24085'));
      expect(seasons.map((s) => s.title), ['Séria 11', 'Séria 12']);
      expect(seasons.map((s) => s.seasonNumber), [11, 12]);
      expect(seasons.map((s) => s.ref.nativeId), ['24085/23883', '24085/24085']);
      expect(seasons.every((s) => s.showTitle == 'Detektívi zo severu'), isTrue);
      expect(seasons.last.childCount, 3);
    });

    test('a different show with a similar name is not a season', () async {
      final seasons = await _provider().children(_ref('24085'));
      expect(seasons.map((s) => s.ref.nativeId), isNot(contains('24085/24087')));
    });

    test('a numbered series with no siblings keeps one season', () async {
      final seasons = await _provider().children(_ref('21414'));
      expect(seasons, hasLength(1));
      expect(seasons.single.seasonNumber, 16);
      expect(seasons.single.ref.nativeId, '21414/21414');
    });

    test('a show without a numeral has one synthetic season', () async {
      final seasons = await _provider().children(_ref('7993'));
      expect(seasons, hasLength(1));
      expect(seasons.single.title, 'Necelebrity');
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.childCount, 3);
    });

    test('an unknown show has no title and no seasons', () async {
      final provider = _provider();
      expect(await provider.title(_ref('999999')), isNull);
      expect(await provider.children(_ref('999999')), isEmpty);
    });

    test('a season title can be opened by its ref', () async {
      final season = await _provider().title(_ref('24085/23883'));
      expect(season!.kind, ReplayKind.season);
      expect(season.seasonNumber, 11);
    });
  });

  group('StvrProvider episodes', () {
    test('episodes come oldest first, numbered from the first airing', () async {
      final episodes = await _provider().children(_ref('7993/7993'));
      expect(episodes.map((e) => e.title), ['Mária Čemanová', 'Branislav Kováčik', 'Tatiana Jánošová']);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.first.ref, _ref('79093-20151027'));
      expect(episodes.first.showRef, _ref('7993'));
      expect(episodes.first.seasonRef, _ref('7993/7993'));
      expect(episodes.first.showTitle, 'Necelebrity');
    });

    test('episodes carry the season number from the show name', () async {
      final episodes = await _provider().children(_ref('24085/24085'));
      expect(episodes.map((e) => e.seasonNumber).toSet(), {12});
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.first.title, 'Sugardaddy');
    });

    test('repeated part numbers fall back to the air order', () async {
      final episodes = await _provider().children(_ref('21414/21414'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5]);
      expect(episodes.first.title, 'Oddelené svety - 2. časť');
    });

    test('an episode keeps its air time in UTC and its licence end', () async {
      final episode = (await _provider().children(_ref('24085/24085'))).first;
      expect(episode.airDate, DateTime.utc(2026, 10, 19, 14, 50));
      expect(episode.availableUntil, DateTime.utc(2026, 10, 26, 22, 59, 59));
      expect(episode.availability, ReplayAvailability.playable);
    });

    test('a recording past its licence end is expired', () async {
      final provider = _provider(now: DateTime.utc(2026, 10, 24));
      final episodes = await provider.children(_ref('23883/23883'));
      expect(episodes.map((e) => e.availability), everyElement(ReplayAvailability.expired));
    });

    test('a recording without a subtitle is named after its show', () async {
      final episode = (await _provider().listing(replayAllBrowseId)).titles.first;
      expect(episode.title, 'Paddington a jeho dobrodružstvá');
      expect(episode.seasonNumber, 2);
      expect(episode.episodeNumber, isNull);
    });

    test('an episode ref is looked up through the list of its day', () async {
      final provider = _provider();
      final episode = await provider.title(_ref('625876-20261022'));
      expect(episode!.showRef, _ref('16609'));
      expect(episode.showTitle, 'Môj zvierací miláčik');
      expect(_requests.single.queryParameters['d'], '2026-10-22');
      expect(await provider.title(_ref('1-20261022')), isNull);
    });

    test('a ref that is neither show, season nor episode is empty', () async {
      final provider = _provider();
      expect(await provider.title(_ref('abc')), isNull);
      expect(await provider.children(_ref('625876-20261022')), isEmpty);
    });
  });

  group('StvrProvider search', () {
    test('shows come before recordings and the same show appears once', () async {
      final results = await _provider().search('poirot');
      final shows = results.where((t) => t.kind == ReplayKind.show).toList();
      expect(shows.first.title, 'Agatha Christie : Poirot');
      expect(shows.first.ref, _ref('8438'));
      expect(shows.map((s) => s.title).toSet(), hasLength(shows.length));
      expect(results.indexOf(shows.last), lessThan(results.indexWhere((t) => t.kind == ReplayKind.episode)));
      expect(results.where((t) => t.kind == ReplayKind.episode), hasLength(3));
    });

    test('an empty or unmatched query returns nothing', () async {
      final provider = _provider();
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('a short query skips the site search', () async {
      await _provider().search('ab');
      expect(_requests.where((u) => u.path == '/json/search/lite'), isEmpty);
    });
  });

  group('StvrProvider playback', () {
    test('a clear recording yields its HLS master after a media check', () async {
      final playback = await _provider().playback(_ref('624605-20261018'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('/00183958.smil/playlist.m3u8'));
      expect(_requests.last.path, endsWith('chunklist-v1-a1.m3u8'));
    });

    test('a geolock slate in the media playlist means geo blocked', () async {
      final playback = await _provider().playback(_ref('625879-20261022'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, isNotEmpty);
    });

    test('a recording the server no longer knows is expired', () async {
      final playback = await _provider().playback(_ref('999-20261022'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('a stream description without a source is unknown', () async {
      final playback = await _provider().playback(_ref('111-20261022'));
      expect(playback.availability, ReplayAvailability.unknown);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _provider().playback(_ref('429-20261022'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a show or season is never played directly', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('7993'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('7993/7993'))).isPlayable, isFalse);
      expect(_requests, isEmpty);
    });

    test('there is no per-title predictor', () {
      expect(_provider(), isNot(isA<ReplayAvailabilityPredictor>()));
    });
  });

  group('StvrProvider artwork', () {
    test('thumbnails are kept as the server gave them', () {
      final provider = _provider();
      const thumb = 'https://www.stvr.sk/media/a501/image/file/13/1596/a.jpg';
      expect(provider.imageUrl(thumb, width: 1000, height: 560), thumb);
      expect(provider.imageUrl('http://www.stvr.sk/media/a.jpg'), 'https://www.stvr.sk/media/a.jpg');
      expect(provider.imageUrl('/media/a.jpg'), 'https://www.stvr.sk/media/a.jpg');
    });

    test('only stvr.sk media paths are owned', () {
      final provider = _provider();
      expect(provider.ownsImage('https://www.stvr.sk/media/a501/image/file/2/1/a.jpg'), isTrue);
      expect(provider.ownsImage('https://example.com/media/a.jpg'), isFalse);
    });

    test('the site placeholder is not used as a picture', () async {
      final shows = (await _provider().search('poirot')).where((t) => t.ref == _ref('8438'));
      expect(shows.single.posterUrl, isNull);
    });
  });

  group('STVR names and numbers', () {
    test('Roman numerals and series words become the season number', () {
      expect(stvrParseShowName('Astrid a Raphaëlle VI').season, 6);
      expect(stvrParseShowName('Astrid a Raphaëlle VI').base, 'Astrid a Raphaëlle');
      expect(stvrParseShowName('Doktor z hôr - Nové osudy XVI').base, 'Doktor z hôr - Nové osudy');
      expect(stvrParseShowName('Lassie 3. séria').season, 3);
      expect(stvrParseShowName('Môj zvierací miláčik I').season, 1);
    });

    test('names that only look like numerals keep their text', () {
      expect(stvrParseShowName('Vitamín C').season, isNull);
      expect(stvrParseShowName('Kolonáda').season, isNull);
      expect(stvrParseShowName('Správy IIII').season, isNull);
      expect(stvrParseShowName('XII').season, isNull);
    });

    test('double and trailing spaces in a name are collapsed', () {
      expect(stvrParseShowName(' Dámsky  klub  IV ').base, 'Dámsky klub');
    });

    test('a part number is read from the subtitle', () {
      expect(stvrStatedEpisodeNumber('Kto sme - 2. časť'), 2);
      expect(stvrStatedEpisodeNumber('Epizóda 12'), 12);
      expect(stvrStatedEpisodeNumber('Teória všetkého'), isNull);
    });

    test('numbers stated once each are used as they are', () {
      expect(stvrEpisodeNumbers(['A - 3. časť', 'B - 4. časť'], total: 2), [3, 4]);
    });

    test('unstated numbers count from the first airing of the series', () {
      expect(stvrEpisodeNumbers(['a', 'b', 'c'], total: 3), [1, 2, 3]);
      expect(stvrEpisodeNumbers(['b', 'c'], total: 10), [9, 10]);
    });

    test('a partly stated run is numbered by position', () {
      expect(stvrEpisodeNumbers(['A - 1. časť', 'B'], total: 2), [1, 2]);
    });
  });

  group('STVR time and cards', () {
    test('summer and winter local times convert to UTC', () {
      expect(stvrParseLocalTime('2026-10-22 06:30:00'), DateTime.utc(2026, 10, 22, 4, 30));
      expect(stvrParseLocalTime('2026-12-01 12:00:00'), DateTime.utc(2026, 12, 1, 11));
      expect(stvrParseLocalTime('2026-03-29 12:00:00'), DateTime.utc(2026, 3, 29, 10));
      expect(stvrParseLocalTime('2026-03-28 12:00:00'), DateTime.utc(2026, 3, 28, 11));
      expect(stvrParseLocalTime('2026-10-25 12:00:00'), DateTime.utc(2026, 10, 25, 11));
    });

    test('an empty or malformed time is null', () {
      expect(stvrParseLocalTime(''), isNull);
      expect(stvrParseLocalTime(null), isNull);
      expect(stvrParseLocalTime('soon'), isNull);
    });

    test('cards without a picture are skipped and entities decoded', () {
      const html = '''
<div data-rows-all="7">
<div class=" tv-archiv__item" data-list-item data-series-id="1">
<a href="/televizia/archiv/1/2" data-item-name="&quot;Dobrý&quot; deň"><picture><img src="https://www.stvr.sk/media/a.jpg" /></picture></a>
</div>
<div class=" tv-archiv__item" data-list-item data-series-id="3">
<a href="/televizia/archiv/3/4" data-item-name="Bez obrázka"></a>
</div>
</div>''';
      final page = stvrParseCards(html);
      expect(page.total, 7);
      expect(page.shows.map((s) => s.title), ['"Dobrý" deň']);
    });
  });
}
