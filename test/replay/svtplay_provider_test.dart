import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/svtplay/svtplay_api.dart';
import 'package:plezy/replay/providers/svtplay/svtplay_images.dart';
import 'package:plezy/replay/providers/svtplay/svtplay_numbering.dart';
import 'package:plezy/replay/providers/svtplay/svtplay_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/svtplay';
final _now = DateTime.utc(2026, 10, 22, 10);

String _text(String name) => File('$_fixtures/$name').readAsStringSync();

Map<String, dynamic> _json(String name) => jsonDecode(_text('$name.json')) as Map<String, dynamic>;

http.Response _reply(Object body, [int status = 200, Map<String, String> headers = const {}]) => http.Response.bytes(
  utf8.encode(body is String ? body : jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...headers},
);

const _graphqlError = {
  'errors': [
    {'message': 'Validation error'},
  ],
};

const _noPage = {
  'data': {'detailsPage': null},
};

/// Serves recorded SVT Play responses and records what was asked.
///
/// [details] replaces the recorded detail page of an id. [inSweden] makes the CDN serve Sweden-only manifests.
class _Svt {
  final bool inSweden;
  final Map<String, Map<String, dynamic>> details;
  final List<http.Request> requests = [];
  final List<Map<String, dynamic>> queries = [];

  _Svt({this.inSweden = false, this.details = const {}});

  static const _detailFixtures = {
    'KqvMbEz': 'details_series_multiseason',
    'eoVPJNz': 'details_tvshow_periods',
    'jE4Bm7D': 'details_single',
    'jBwJLnL': 'details_episode',
    'e7ovrxY': 'details_episode_show',
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final host = request.url.host;
    if (host == 'contento.svt.se') return _graphql(jsonDecode(request.body) as Map<String, dynamic>);
    if (host == 'api.svt.se') return _video(request.url.pathSegments.last);
    return _manifest(request.url);
  }

  http.Response _graphql(Map<String, dynamic> body) {
    queries.add(body);
    final query = body['query'] as String;
    final variables = body['variables'] as Map<String, dynamic>;
    if (query.contains('query Home')) return _reply(_text('home.json'));
    if (query.contains('query Categories')) return _reply(_text('categories.json'));
    if (query.contains('query CategoryListing')) return _reply(_text('category_listing.json'));
    if (query.contains('query Category(')) return _reply(_text('category_dokumentar.json'));
    if (query.contains('query AllTitles')) return _reply(_text('all_titles.json'));
    if (query.contains('query Search')) {
      final name = switch (variables['query']) {
        'natur' => 'search_natur',
        'rapport' => 'search_rapport',
        _ => 'search_empty',
      };
      return _reply(_text('$name.json'));
    }
    if (query.contains('query Details')) return _detailsPage(variables['id'] as String);
    return _reply(_graphqlError);
  }

  http.Response _detailsPage(String id) {
    final replaced = details[id];
    if (replaced != null) return _reply(replaced);
    final fixture = _detailFixtures[id];
    return fixture == null ? _reply(_noPage) : _reply(_text('$fixture.json'));
  }

  http.Response _video(String id) {
    switch (id) {
      case 'world':
        return _reply(_text('video_world_clear.json'));
      case 'variants':
        return _reply(_text('video_world_variants.json'));
      case 'sweden-empty':
        return _reply(_text('video_sweden_only_empty.json'));
      case 'sweden-refs':
        return _reply(_text('video_sweden_only_with_refs.json'));
      case 'drm':
        return _reply(_text('video_drm_flag.json'));
      case 'expired':
        return _reply(_withRights('validTo', '2020-01-01T00:00:00+01:00'));
      case 'upcoming':
        return _reply(_withRights('validFrom', '2030-01-01T00:00:00+01:00'));
      case 'live':
        return _reply({..._json('video_world_clear'), 'live': true});
      case 'busy':
        return http.Response('busy', 429, headers: {'retry-after': '30'});
      default:
        return _reply('{}', 404);
    }
  }

  Map<String, dynamic> _withRights(String key, String value) {
    final video = _json('video_world_clear');
    return {
      ...video,
      'rights': {...video['rights'] as Map<String, dynamic>, key: value},
    };
  }

  http.Response _manifest(Uri url) {
    if (url.path.contains('/d0/se/') && !inSweden) {
      return http.Response('<html>Access Denied</html>', 403, headers: {'content-type': 'text/html'});
    }
    return http.Response(
      _text('master_hls_cmaf_avc.m3u8'),
      200,
      headers: {'content-type': 'application/vnd.apple.mpegurl'},
    );
  }

  Iterable<http.Request> get manifestRequests => requests.where((r) => r.url.host.endsWith('akamaized.net'));
}

SvtPlayProvider _provider(_Svt server) {
  final client = MediaServerHttpClient(client: MockClient(server.handle));
  return SvtPlayProvider.withApi(SvtPlayApi(client, now: () => _now), clock: () => _now);
}

// Titles of the recorded catalogue that are licensed worldwide.
const _worldwide = ['Kw265Gb', 'jmyoArD', 'KnbzZaz', '8or9gBG', '8YqA2YE'];

ReplayRef _ref(String id) => ReplayRef('svtplay', id);

Map<String, dynamic> _detailsWith(String fixture, void Function(Map<String, dynamic> item) edit) {
  final page = _json(fixture);
  edit(((page['data'] as Map)['detailsPage'] as Map)['item'] as Map<String, dynamic>);
  return page;
}

List<Map<String, dynamic>> _seasonsOf(Map<String, dynamic> item) => (item['seasons'] as List).cast();

List<Map<String, dynamic>> _episodesOf(Map<String, dynamic> season) => (season['episodes'] as List).cast();

void main() {
  group('SVT Play browsing', () {
    test('home keeps catalogue rows and drops live, personal and clip rows', () async {
      final rails = await _provider(_Svt()).home();
      final ids = rails.map((r) => r.id).toList();
      expect(ids, ['recommended_start', 'popular_start', 'list_1204', 'latest_start', 'lastchance_start']);
      expect(rails.every((r) => r.titles.isNotEmpty), isTrue);
      expect(rails.expand((r) => r.titles).every((t) => t.ref.source == 'svtplay'), isTrue);
    });

    test('home maps programmes to shows, films and episodes of a show', () async {
      final titles = (await _provider(_Svt()).home()).expand((r) => r.titles).toList();
      expect(titles.where((t) => t.kind == ReplayKind.show), isNotEmpty);
      expect(titles.where((t) => t.kind == ReplayKind.movie), isNotEmpty);
      final episode = titles.firstWhere((t) => t.ref == _ref('jBwJLnL'));
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showTitle, 'Politikbyrån');
      expect(episode.showRef, _ref('e7ovrxY'));
      expect(episode.episodeNumber, 9);
      expect(episode.durationSeconds, 1695);
    });

    test('an episode that is not on air yet stays out of the home rows', () async {
      final before = DateTime.utc(2026, 10, 21, 8);
      final client = MediaServerHttpClient(client: MockClient(_Svt().handle));
      final provider = SvtPlayProvider.withApi(SvtPlayApi(client, now: () => before), clock: () => before);
      final titles = (await provider.home()).expand((r) => r.titles);
      expect(titles.where((t) => t.ref == _ref('jBwJLnL')), isEmpty);
    });

    test('categories are the main ones only', () async {
      final categories = await _provider(_Svt()).categories();
      expect(categories, hasLength(24));
      expect(categories.first.id, 'serier');
      expect(categories.first.title, 'Serier');
    });

    test('a category page shows the discovery tab, not the upcoming one', () async {
      final rails = await _provider(_Svt()).category('dokumentar');
      expect(rails.map((r) => r.id), ['recommended-dokumentar', 'list_1015', 'popular-dokumentar', 'list_1057']);
    });

    test('the whole catalogue is listed once per title and paged', () async {
      final provider = _provider(_Svt());
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 18);
      expect(first.titles.map((t) => t.ref).toSet(), hasLength(18));
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('a category listing asks the broadcaster for the page offset', () async {
      final server = _Svt();
      final page = await _provider(server).listing('dokumentar', page: 2);
      expect(page.totalCount, 1179);
      expect(page.titles, isNotEmpty);
      expect(server.queries.single['variables'], {'id': 'dokumentar', 'limit': 24, 'offset': 48});
    });

    test('search returns programmes without markup, clips or category hits', () async {
      final provider = _provider(_Svt());
      final hits = await provider.search('natur');
      expect(hits, hasLength(9));
      expect(hits.any((t) => t.title.contains('<')), isFalse);
      expect(hits.first.title, 'Naturfotografen - blixtsnabba busar');
      final news = await provider.search('rapport');
      expect(news, hasLength(6));
      expect(news.map((t) => t.ref).toSet(), hasLength(6));
    });

    test('an empty result and a blank query both return nothing', () async {
      final server = _Svt();
      final provider = _provider(server);
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('   '), isEmpty);
      expect(server.queries, hasLength(1));
    });

    test('requests name the app and do not narrow the catalogue by country', () async {
      final server = _Svt();
      await _provider(server).home();
      expect(server.requests.single.headers['User-Agent'], startsWith('Plezy-Replay'));
      expect(server.requests.single.body, isNot(contains('userIsAbroad')));
    });

    test('a query the server rejects is reported with its message', () async {
      final client = MediaServerHttpClient(client: MockClient((_) async => _reply(_graphqlError)));
      await expectLater(
        SvtPlayApi(client).query('{ x }'),
        throwsA(isA<SvtPlayQueryException>().having((e) => e.message, 'message', 'Validation error')),
      );
    });

    test('rate limiting says when to retry', () async {
      final client = MediaServerHttpClient(
        client: MockClient((_) async => http.Response('busy', 429, headers: {'retry-after': '12'})),
      );
      await expectLater(
        SvtPlayApi(client).query('{ x }'),
        throwsA(
          isA<SvtPlayRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 12)),
        ),
      );
    });
  });

  group('SVT Play seasons and episodes', () {
    test('a series lists its numbered seasons oldest first', () async {
      final seasons = await _provider(_Svt()).children(_ref('KqvMbEz'));
      expect(seasons.map((s) => s.seasonNumber), [for (var n = 1; n <= 10; n++) n]);
      expect(seasons.first.title, 'Säsong 1');
      expect(seasons.first.ref, _ref('KqvMbEz/KqvMbEz-sasong-1-1'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('KqvMbEz')), isTrue);
      expect(seasons.every((s) => s.childCount == 3 && s.showTitle == 'Fixa rummet'), isTrue);
    });

    test('a season lists its episodes in order with numbers and parents', () async {
      final provider = _provider(_Svt());
      final season = (await provider.children(_ref('KqvMbEz'))).last;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [4, 5, 6]);
      expect(episodes.last.title, 'Restaurang');
      expect(episodes.last.ref, _ref('KZxp2gP'));
      expect(episodes.last.seasonNumber, 10);
      expect(episodes.last.seasonRef, season.ref);
      expect(episodes.last.showTitle, 'Fixa rummet');
      expect(episodes.last.durationSeconds, 1720);
      expect(episodes.last.posterUrl, startsWith('https://www.svtstatic.se/image/custom/'));
    });

    test('production periods of a news show become seasons without future episodes', () async {
      final provider = _provider(_Svt());
      final seasons = await provider.children(_ref('eoVPJNz'));
      expect(seasons.map((s) => s.seasonNumber), [3, 4, 5]);
      expect(seasons.last.title.trim(), startsWith('Huvudsändningar'));
      expect(seasons.map((s) => s.childCount), [3, 3, 3]);
      final main = await provider.children(seasons.last.ref);
      expect(main.map((e) => e.episodeNumber), [250, 251, 252]);
      expect(main.map((e) => e.ref.nativeId), isNot(contains('8myy5y1')));
    });

    test('episodes that share a number are numbered by broadcast time', () async {
      final provider = _provider(_Svt());
      final updates = (await provider.children(_ref('eoVPJNz'))).first;
      final episodes = await provider.children(updates.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.map((e) => e.title), ['Idag 08:30', 'Idag 09:00', 'Idag 09:30']);
    });

    test('a season is dropped when none of its episodes can be played yet', () async {
      final page = _detailsWith('details_tvshow_periods', (item) {
        for (final episode in _episodesOf(_seasonsOf(item).first)) {
          episode['validFrom'] = '2027-01-01T00:00:00+01:00';
        }
      });
      final seasons = await _provider(_Svt(details: {'eoVPJNz': page})).children(_ref('eoVPJNz'));
      expect(seasons.map((s) => s.seasonNumber), [3, 4]);
    });

    test('seasons without numbers take them from their names', () async {
      final page = _detailsWith('details_series_multiseason', (item) {
        for (final season in _seasonsOf(item)) {
          season['number'] = 0;
        }
      });
      final seasons = await _provider(_Svt(details: {'KqvMbEz': page})).children(_ref('KqvMbEz'));
      expect(seasons.map((s) => s.seasonNumber), [for (var n = 1; n <= 10; n++) n]);
    });

    test('unnamed unnumbered seasons are counted from the oldest', () async {
      final page = _detailsWith('details_series_multiseason', (item) {
        for (final season in _seasonsOf(item)) {
          season['number'] = null;
          season['name'] = 'Avsnitt';
        }
      });
      final seasons = await _provider(_Svt(details: {'KqvMbEz': page})).children(_ref('KqvMbEz'));
      expect(seasons.map((s) => s.seasonNumber), [for (var n = 1; n <= 10; n++) n]);
      expect(seasons.first.ref.nativeId, endsWith('sasong-1-1'));
    });

    test('episode numbers come from the position label or the title prefix', () async {
      final page = _detailsWith('details_series_multiseason', (item) {
        final episodes = _episodesOf(_seasonsOf(item).first);
        episodes[0]
          ..['number'] = null
          ..['positionInSeason'] = 'Svenska - Avsnitt 7'
          ..['nameRaw'] = ''
          ..['name'] = 'Restaurang';
        episodes[1]
          ..['number'] = 0
          ..['positionInSeason'] = ''
          ..['nameRaw'] = ''
          ..['name'] = '5. Månlabb';
        episodes[2]
          ..['number'] = 4
          ..['name'] = '4. Spelvärld'
          ..['nameRaw'] = 'Spelvärld';
      });
      final provider = _provider(_Svt(details: {'KqvMbEz': page}));
      final season = (await provider.children(_ref('KqvMbEz'))).last;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [4, 5, 7]);
      expect(episodes.map((e) => e.title), ['Spelvärld', 'Månlabb', 'Restaurang']);
    });

    test('a film has no children and plays as a movie', () async {
      final provider = _provider(_Svt());
      expect(await provider.children(_ref('jE4Bm7D')), isEmpty);
      final film = (await provider.title(_ref('jE4Bm7D')))!;
      expect(film.kind, ReplayKind.movie);
      expect(film.isPlayable, isTrue);
      expect(film.title, 'Linje 18');
      expect(film.durationSeconds, 590);
      expect(film.year, 2023);
      expect(film.genres, contains('Kortfilmer'));
      expect(film.genres, isNot(contains('Tydligare tal')));
    });

    test('a show page carries its summary, artwork and logo', () async {
      final show = (await _provider(_Svt()).title(_ref('KqvMbEz')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.summary, startsWith('Fixa rummet är ett riktigt byggprogram'));
      expect(show.posterUrl, contains('/50926412/'));
      expect(show.backdropUrl, contains('/50926396/'));
      expect(show.logoUrl, contains('/50900352/'));
    });

    test('an episode page finds its show, season and numbers', () async {
      final episode = (await _provider(_Svt()).title(_ref('jBwJLnL')))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('e7ovrxY'));
      expect(episode.showTitle, 'Politikbyrån');
      expect(episode.seasonNumber, 8);
      expect(episode.seasonRef, _ref('e7ovrxY/e7ovrxY-host-2026-8'));
      expect(episode.episodeNumber, 9);
      expect(episode.summary, contains('Centerpartiet'));
    });

    test('a season page is found by its ref, and an unknown title is null', () async {
      final provider = _provider(_Svt());
      final season = (await provider.title(_ref('KqvMbEz/KqvMbEz-sasong-3-3')))!;
      expect(season.kind, ReplayKind.season);
      expect(season.seasonNumber, 3);
      expect(await provider.title(_ref('nothing')), isNull);
      expect(await provider.children(_ref('nothing')), isEmpty);
    });
  });

  group('SVT Play playback', () {
    test('a worldwide episode yields its HLS master', () async {
      final playback = await _provider(_Svt()).playback(_ref('world'));
      expect(playback.isPlayable, isTrue);
      final standard = playback.streams.first;
      expect(standard.label, 'Standard');
      expect(standard.url.host, 'svt-vod-3f.akamaized.net');
      expect(standard.url.path, endsWith('/hls-cmaf-avc.m3u8'));
      expect(standard.headers, isEmpty);
      expect(playback.subtitles, isEmpty);
    });

    test('audio described and sign language versions are offered', () async {
      final playback = await _provider(_Svt()).playback(_ref('variants'));
      expect(playback.streams.map((s) => s.label), ['Standard', 'AD', 'Sign language']);
      expect(playback.streams.every((s) => s.url.path.endsWith('.m3u8')), isTrue);
    });

    test('a Sweden-only title with no streams is geoblocked', () async {
      final playback = await _provider(_Svt()).playback(_ref('sweden-empty'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('a Sweden-only title is geoblocked when the CDN refuses the manifest', () async {
      final server = _Svt();
      final playback = await _provider(server).playback(_ref('sweden-refs'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.message, contains('Sweden'));
      expect(server.manifestRequests, hasLength(1));
    });

    test('a Sweden-only title plays for a viewer the CDN accepts', () async {
      final playback = await _provider(_Svt(inSweden: true)).playback(_ref('sweden-refs'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, contains('/d0/se/'));
    });

    test('a worldwide title does not touch the CDN before playing', () async {
      final server = _Svt();
      await _provider(server).playback(_ref('world'));
      expect(server.manifestRequests, isEmpty);
    });

    test('a copy-protected title is reported and never fetched', () async {
      final server = _Svt(inSweden: true);
      final playback = await _provider(server).playback(_ref('drm'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(server.manifestRequests, isEmpty);
    });

    test('expired, upcoming and missing titles say why', () async {
      final provider = _provider(_Svt());
      expect((await provider.playback(_ref('expired'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_ref('upcoming'))).availability, ReplayAvailability.upcoming);
      expect((await provider.playback(_ref('gone'))).availability, ReplayAvailability.expired);
    });

    test('live streams, seasons and rate limiting are not played', () async {
      final provider = _provider(_Svt());
      expect((await provider.playback(_ref('live'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('KqvMbEz/KqvMbEz-sasong-1-1'))).isPlayable, isFalse);
      final busy = await provider.playback(_ref('busy'));
      expect(busy.availability, ReplayAvailability.unknown);
      expect(busy.message, contains('30'));
    });
  });

  group('SVT Play availability forecast', () {
    test('a viewer outside Sweden gets Sweden-only titles greyed out', () async {
      final provider = _provider(_Svt());
      final titles = (await provider.listing(replayAllBrowseId)).titles;
      final verdicts = await provider.predictAvailability(titles, 'BE');

      expect(verdicts[_ref('jnG14JK')], ReplayAvailability.geoBlocked);
      expect(verdicts[_ref('KzVB9XL')], ReplayAvailability.geoBlocked);
      for (final id in _worldwide) {
        expect(verdicts[_ref(id)], isNull, reason: id);
      }
      expect(verdicts, hasLength(13));
      expect(verdicts.values.where((v) => v == ReplayAvailability.geoBlocked), hasLength(10));
    });

    test('copy-protected titles are reported for every country', () async {
      final provider = _provider(_Svt());
      final titles = (await provider.listing(replayAllBrowseId)).titles;
      final abroad = await provider.predictAvailability(titles, 'BE');
      final home = await provider.predictAvailability(titles, 'SE');

      for (final id in ['8WvrBbQ', 'Kv14zWR', '8z7vDQ6']) {
        expect(abroad[_ref(id)], ReplayAvailability.drmProtected, reason: id);
        expect(home[_ref(id)], ReplayAvailability.drmProtected, reason: id);
      }
      expect(titles.firstWhere((t) => t.ref == _ref('8WvrBbQ')).availability, ReplayAvailability.drmProtected);
    });

    test('a viewer in Sweden is told nothing about Sweden-only titles', () async {
      final provider = _provider(_Svt());
      final titles = (await provider.listing(replayAllBrowseId)).titles;
      final verdicts = await provider.predictAvailability(titles, 'se');
      expect(verdicts.values.toSet(), {ReplayAvailability.drmProtected});
    });

    test('worldwide titles and titles never seen get no verdict', () async {
      final provider = _provider(_Svt());
      final titles = (await provider.listing(replayAllBrowseId)).titles;
      final worldwide = titles.where((t) => _worldwide.contains(t.ref.nativeId)).toList();
      expect(worldwide, hasLength(5));
      expect(await provider.predictAvailability(worldwide, 'BE'), isEmpty);

      final stranger = ReplayTitle(ref: _ref('unseen'), kind: ReplayKind.movie, title: 'Unseen');
      expect(await _provider(_Svt()).predictAvailability([stranger], 'BE'), isEmpty);
    });

    test('seasons and episodes of a Sweden-only show inherit its restriction', () async {
      final page = _detailsWith('details_series_multiseason', (item) {
        (item['restrictions'] as Map)['onlyAvailableInSweden'] = true;
        for (final season in _seasonsOf(item)) {
          for (final episode in _episodesOf(season)) {
            (episode['restrictions'] as Map)['onlyAvailableInSweden'] = true;
          }
        }
      });
      final provider = _provider(_Svt(details: {'KqvMbEz': page}));
      final seasons = await provider.children(_ref('KqvMbEz'));
      final episodes = await provider.children(seasons.last.ref);

      final verdicts = await provider.predictAvailability([...seasons, ...episodes], 'DE');
      expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
      expect(verdicts.keys, containsAll([seasons.first.ref, episodes.first.ref]));
    });
  });

  group('SVT Play numbering and images', () {
    test('an episode number is read from the first source that has one', () {
      expect(svtEpisodeNumber({'number': 12}), 12);
      expect(svtEpisodeNumber({'number': 0, 'positionInSeason': 'Svenska - Avsnitt 3'}), 3);
      expect(svtEpisodeNumber({'name': '7. Fisk'}), 7);
      expect(svtEpisodeNumber({'name': 'Fisk'}), isNull);
      expect(svtEpisodeTitle({'nameRaw': '', 'name': '7. Fisk'}), 'Fisk');
      expect(svtEpisodeTitle({'nameRaw': 'Fisk', 'name': '7. Fisk'}), 'Fisk');
      expect(svtEpisodeTitle({'name': 'Tor 31 dec'}), 'Tor 31 dec');
    });

    test('seasons given newest first are numbered from the oldest', () {
      final unnamed = <Map<String, dynamic>>[
        {'name': 'B'},
        {'name': 'A'},
      ];
      expect(svtSeasonNumbers(unnamed), [2, 1]);
      expect(
        svtSeasonNumbers([
          {'name': 'Säsong 4'},
          {'name': 'Säsong 3'},
        ]),
        [4, 3],
      );
    });

    test('artwork references are full URLs whose width can be changed', () {
      final reference = svtPlayImageReference({'id': '50926396', 'changed': 1703009750})!;
      expect(reference, 'https://www.svtstatic.se/image/custom/640/50926396/1703009750');
      expect(svtPlayImageUrl(reference, width: 300), endsWith('/custom/320/50926396/1703009750'));
      expect(svtPlayImageUrl(reference, width: 1000), contains('/custom/1280/'));
      expect(svtPlayImageUrl(reference, width: 5000), contains('/custom/1920/'));
      expect(svtPlayImageUrl(reference), reference);
      expect(svtPlayImageReference(null), isNull);
      expect(isSvtPlayImage(reference), isTrue);
      expect(isSvtPlayImage('https://example.com/a.jpg'), isFalse);
    });
  });
}
