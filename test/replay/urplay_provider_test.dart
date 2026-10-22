import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/urplay/urplay_api.dart';
import 'package:plezy/replay/providers/urplay/urplay_availability.dart';
import 'package:plezy/replay/providers/urplay/urplay_catalog.dart';
import 'package:plezy/replay/providers/urplay/urplay_images.dart';
import 'package:plezy/replay/providers/urplay/urplay_mapper.dart';
import 'package:plezy/replay/providers/urplay/urplay_numbering.dart';
import 'package:plezy/replay/providers/urplay/urplay_playback.dart';
import 'package:plezy/replay/providers/urplay/urplay_provider.dart';
import 'package:plezy/replay/providers/urplay/urplay_refs.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/urplay';

String _text(String file) => File('$_fixtures/$file').readAsStringSync();

Map<String, dynamic> _json(String name) => jsonDecode(_text('$name.json')) as Map<String, dynamic>;

http.Response _reply(Object body, {int status = 200, String type = 'application/json', Map<String, String>? headers}) {
  final text = body is String ? body : jsonEncode(body);
  return http.Response.bytes(utf8.encode(text), status, headers: {'content-type': '$type; charset=utf-8', ...?headers});
}

const _hls = 'https://streaming20.ur.se/content/v2';

String _sourcesBody(String id) => jsonEncode({
  'externalId': int.parse(id),
  'sources': {'hls': '$_hls/x/$id/hls-avc.m3u8?token=t&u=u'},
});

/// A copy of the recorded episode list of a show, renamed so a second show can be served from one recording.
Map<String, dynamic> _renamed(String title) {
  final page = _json('season_episodes');
  for (final episode in (page['accessibleEpisodes'] as List).cast<Map<String, dynamic>>()) {
    episode['mainTitle'] = title;
  }
  return page;
}

/// Serves recorded UR responses by URL; anything unknown is an empty page or the server's 500 for a bad id.
http.Response _route(http.Request request) {
  final q = request.url.queryParameters;
  final path = request.url.path;
  if (request.url.host == 'urplay.se') {
    switch (path) {
      case '/api/v1/search':
        return _search(q);
      case '/api/v1/season_episodes':
        return _seasonEpisodes(q['seriesId']!);
      case '/api/v1/episode_info':
        final file = const {
          '245901': 'episode_info',
          '246483': 'episode_info_in_season',
          '242470': 'episode_info_older_season',
          '245516': 'episode_info_single',
        }[q['programId']];
        return file == null ? _reply({'message': 'Internal server error'}, status: 500) : _reply(_text('$file.json'));
    }
  }
  if (request.url.host == 'media-api.urplay.se') return _sources(path.split('/').last);
  if (request.url.host == 'streaming20.ur.se') return _playlist(path);
  return _reply({}, status: 404);
}

http.Response _search(Map<String, String> q) {
  final query = q['query'];
  final genre = q['main_genre'];
  if (query == 'zzzz') return _reply(_text('search_empty.json'));
  if (query == 'natur') return _reply(_text('search_query_natur.json'));
  if (query == 'Nyhetskoll - Så fungerar valskärmen') return _reply(_text('search_with_single.json'));
  if (query == 'Lässugen - syntolkat') return _reply(_text('search_series_lassugen.json'));
  if (query == 'Vildmarken med Simon Reeve' || query == 'Norden med Simon Reeve') {
    return _reply(_text('search_series.json'));
  }
  if (genre == 'Föreläsning' && q['product_type'] == 'program') {
    return _reply({'statusCode': 400, 'message': 'bad_request'}, status: 400);
  }
  if (genre == 'Foo') return _reply({'statusCode': 400, 'message': 'bad_request'}, status: 400);
  if (genre == 'Dedup') return _reply(_text('search_series_lassugen.json'));
  if (q['product_type'] == 'program') return _reply(_text('search_genre_paged.json'));
  if (q['product_type'] == 'series') return _reply(_text('search_series.json'));
  return _reply(_text('search_empty.json'));
}

http.Response _seasonEpisodes(String id) {
  switch (id) {
    case '245905':
      return _reply(_text('season_episodes.json'));
    case '242934':
      return _reply(_renamed('Norden med Simon Reeve'));
    case '246484':
      return _reply(_text('season_episodes_audio_described.json'));
    case '242465':
      return _reply(_text('season_episodes_audio_described_s4.json'));
    case '777':
      final page = _renamed('Vildmarken med Simon Reeve');
      final aired = (page['accessibleEpisodes'] as List).cast<Map<String, dynamic>>();
      final next = Map<String, dynamic>.of(aired.last)
        ..['id'] = 778
        ..['episodeNumber'] = 4
        ..['accessiblePlatforms'] = {
          'urplay': {'startTime': '2099-01-01T00:00:00.000Z', 'endTime': '2099-12-31T00:00:00.000Z'},
        };
      page['upcomingEpisodes'] = [next];
      return _reply(page);
    default:
      return _reply({'message': 'Internal server error'}, status: 500);
  }
}

http.Response _sources(String id) {
  switch (id) {
    case '245894':
      return _reply(_text('sources_ok.json'));
    case '245901' || '245903':
      return _reply((_json('sources_sweden_only_403')['body']), status: 403);
    case '111':
      return _reply({'statusCode': 400, 'message': 'missing_product_id_in_path'}, status: 400);
    case '222':
      return _reply({'message': 'slow down'}, status: 429, headers: {'retry-after': '30'});
    case '444':
      return _reply({'statusCode': 403, 'message': 'parental_lock'}, status: 403);
    case '555':
      return _reply({'externalId': 555, 'sources': <String, dynamic>{}});
    default:
      return _reply(_sourcesBody(id));
  }
}

http.Response _playlist(String path) {
  if (path.contains('/245894/') || path.contains('245894-')) {
    return _reply(_text('master_hls_with_english.m3u8'), type: 'application/vnd.apple.mpegurl');
  }
  if (path.contains('/333/')) {
    return _reply(
      '#EXTM3U\n#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://key"\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360\nv.m3u8\n',
      type: 'application/vnd.apple.mpegurl',
    );
  }
  if (path.contains('/666/')) return _reply('gone', status: 404, type: 'text/plain');
  return _reply(_text('master_hls_avc.m3u8'), type: 'application/vnd.apple.mpegurl');
}

UrPlayProvider _provider({List<http.Request>? log, Future<void> Function(http.Request)? before}) {
  final client = MediaServerHttpClient(
    client: MockClient((request) async {
      log?.add(request);
      await before?.call(request);
      return _route(request);
    }),
  );
  return UrPlayProvider.withApi(UrPlayApi(client));
}

ReplayRef _ref(String id) => ReplayRef('urplay', id);

void main() {
  group('UrPlayProvider browsing', () {
    test('categories are the genres the catalogue filters on', () async {
      final categories = await _provider().categories();
      expect(categories.map((c) => c.id), contains('Dokumentärserie'));
      expect(categories.map((c) => c.id).toSet(), hasLength(categories.length));
    });

    test('home rows hold cards and link to their listing', () async {
      final rails = await _provider().home();
      expect(rails.map((r) => r.id), containsAll(['newest-programs', 'newest-series']));
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.id);
        expect(rail.moreBrowseId, isNotNull, reason: rail.id);
        expect(rail.titles.every((t) => t.ref.source == 'urplay'), isTrue);
      }
    });

    test('a category drops the row UR rejects with a 400', () async {
      final rails = await _provider().category('Föreläsning');
      expect(rails.map((r) => r.id), ['series:Föreläsning']);
      expect(rails.single.titles.every((t) => t.kind == ReplayKind.show), isTrue);
    });

    test('a listing counts one more page while UR reports a next one', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);

      final more = await provider.listing('program:Reseprogram', page: 1);
      expect(log.single.url.queryParameters['start'], '24');
      expect(more.totalCount, 72);
      expect(more.titles.every((t) => t.isPlayable), isTrue);

      final last = await provider.listing(replayAllBrowseId);
      expect(last.totalCount, 2);
      expect(last.titles.map((t) => t.title), ['Vildmarken med Simon Reeve', 'Norden med Simon Reeve']);
    });

    test('a genre UR does not know lists nothing instead of failing', () async {
      final page = await _provider().listing('series:Foo');
      expect(page.titles, isEmpty);
      expect(page.totalCount, 0);
    });

    test('a show listed under several seasons appears once', () async {
      final page = await _provider().listing('series:Dedup');
      expect(page.titles.map((t) => t.ref), [_ref('show/246484')]);
    });

    test('search puts shows before programmes and keeps standalone films', () async {
      final titles = await _provider().search('Nyhetskoll - Så fungerar valskärmen');
      final kinds = titles.map((t) => t.kind).toList();
      expect(kinds.take(2), [ReplayKind.show, ReplayKind.show]);
      final film = titles.firstWhere((t) => t.ref == _ref('245516'));
      expect(film.kind, ReplayKind.movie);
      expect(film.showTitle, isNull);
      final episode = titles.firstWhere((t) => t.ref == _ref('246695'));
      expect(episode.kind, ReplayKind.episode);
      expect(episode.showTitle, 'Nyhetskoll teckenspråk');
    });

    test('search results carry the show title and episode number', () async {
      final titles = await _provider().search('natur');
      final yukon = titles.firstWhere((t) => t.ref == _ref('245901'));
      expect(yukon.showTitle, 'Vildmarken med Simon Reeve');
      expect(yukon.episodeNumber, 3);
      expect(yukon.durationSeconds, 3517);
      expect(yukon.genres, ['Reseprogram']);
    });

    test('an empty query returns nothing without asking', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
      expect(log, hasLength(1));
    });

    test('requests identify the app', () async {
      final log = <http.Request>[];
      await _provider(log: log).search('natur');
      expect(log.first.headers['User-Agent'], startsWith('Plezy-Replay'));
    });
  });

  group('UrPlayProvider shows', () {
    test('a show lists its seasons from series sharing a title', () async {
      final seasons = await _provider().children(_ref('show/246484'));
      expect(seasons.map((s) => s.seasonNumber), [4, 5]);
      expect(seasons.map((s) => s.title), ['Säsong 4', 'Säsong 5']);
      expect(seasons.map((s) => s.childCount), [3, 4]);
      expect(seasons.map((s) => s.ref.nativeId), ['season/246484/242465', 'season/246484/246484']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show/246484')), isTrue);
    });

    test('the season number is read from the description prefix', () async {
      final seasons = await _provider().children(_ref('show/245905'));
      expect(seasons.single.seasonNumber, 2);
      expect(seasons.single.summary, isNot(startsWith('Säsong')));
    });

    test('a show without a season label gets one synthetic season', () async {
      final seasons = await _provider().children(_ref('show/242934'));
      expect(seasons, hasLength(1));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.title, 'Säsong 1');
      expect(seasons.single.showTitle, 'Norden med Simon Reeve');
    });

    test('a season lists its episodes in order with their parents', () async {
      final provider = _provider();
      final season = (await provider.children(_ref('show/245905'))).single;
      final episodes = await provider.children(season.ref);
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonNumber, 2);
      expect(episodes.first.seasonRef, season.ref);
      expect(episodes.first.showRef, _ref('show/245905'));
      expect(episodes.first.showTitle, 'Vildmarken med Simon Reeve');
    });

    test('upcoming episodes follow the available ones, marked upcoming', () async {
      final episodes = await _provider().children(_ref('season/777/777'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      expect(episodes.map((e) => e.availability), [
        ReplayAvailability.playable,
        ReplayAvailability.playable,
        ReplayAvailability.playable,
        ReplayAvailability.upcoming,
      ]);
    });

    test('a series the search does not return still joins its show', () async {
      final seasons = await _provider().children(_ref('show/777'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.first.ref, _ref('season/777/777'));
      expect(seasons.first.childCount, 3);
    });

    test('an unknown series has no title and no children', () async {
      final provider = _provider();
      expect(await provider.title(_ref('show/999')), isNull);
      expect(await provider.children(_ref('show/999')), isEmpty);
      expect(await provider.children(_ref('season/999/999')), isEmpty);
    });

    test('a show title counts its seasons', () async {
      final show = await _provider().title(_ref('show/246484'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Lässugen - syntolkat');
      expect(show.childCount, 2);
      expect(show.posterUrl, endsWith('/246484/images/1_sql.jpg'));
      expect(show.backdropUrl, endsWith('/246484/images/1_hd.jpg'));
    });

    test('a season title knows its show and number', () async {
      final season = await _provider().title(_ref('season/246484/242465'));
      expect(season!.seasonNumber, 4);
      expect(season.showRef, _ref('show/246484'));
      expect(season.showTitle, 'Lässugen - syntolkat');
    });

    test('an episode page knows its show, season and numbers', () async {
      final episode = await _provider().title(_ref('246483'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('show/246484'));
      expect(episode.seasonRef, _ref('season/246484/246484'));
      expect(episode.seasonNumber, 5);
      expect(episode.episodeNumber, 2);
      expect(episode.showTitle, 'Lässugen - syntolkat');
      expect(episode.year, 2026);
      expect(episode.cast, ['Samuel Rhedin']);
    });

    test('an episode of an older season points at the newest season show', () async {
      final episode = await _provider().title(_ref('242470'));
      expect(episode!.showRef, _ref('show/246484'));
      expect(episode.seasonRef, _ref('season/246484/242465'));
      expect(episode.seasonNumber, 4);
      expect(episode.episodeNumber, 2);
    });

    test('a standalone programme is a movie without a show', () async {
      final film = await _provider().title(_ref('245516'));
      expect(film!.kind, ReplayKind.movie);
      expect(film.showRef, isNull);
      expect(film.episodeNumber, isNull);
    });

    test('an unknown programme has no title', () async {
      expect(await _provider().title(_ref('424242')), isNull);
      expect(await _provider().title(_ref('not-an-id')), isNull);
    });
  });

  group('UrPlayProvider playback', () {
    test('a clear programme yields its HLS master', () async {
      final playback = await _provider().playback(_ref('245894'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'streaming20.ur.se');
      expect(playback.streams.single.url.path, endsWith('/hls-avc.m3u8'));
      expect(playback.credits, isNull);
    });

    test('every subtitle language of the master is named in the label', () async {
      final label = (await _provider().playback(_ref('245894'))).streams.single.label;
      expect(label, contains('Litauiska'));
      expect(label, contains('Svenska'));
      expect(label, contains('Engelska'));
    });

    test('a programme kept to Sweden is reported as geoblocked', () async {
      final playback = await _provider().playback(_ref('245901'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('Sweden'));
    });

    test('an unknown programme is reported as expired', () async {
      expect((await _provider().playback(_ref('111'))).availability, ReplayAvailability.expired);
    });

    test('an encrypted master is reported as DRM protected', () async {
      final playback = await _provider().playback(_ref('333'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
    });

    test('a master that cannot be read still plays', () async {
      final playback = await _provider().playback(_ref('666'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.label, 'UR Play');
    });

    test('another refusal comes back as unknown with its reason', () async {
      final playback = await _provider().playback(_ref('444'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, 'parental_lock');
    });

    test('an answer without a stream is unknown', () async {
      expect((await _provider().playback(_ref('555'))).availability, ReplayAvailability.unknown);
    });

    test('rate limiting is reported without throwing, then paused', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      final first = await provider.playback(_ref('222'));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));

      final second = await provider.playback(_ref('245894'));
      expect(second.availability, ReplayAvailability.unknown);
      expect(log, hasLength(1));
    });

    test('a show or a season is never played directly', () async {
      final provider = _provider();
      expect((await provider.playback(_ref('show/245905'))).isPlayable, isFalse);
      expect((await provider.playback(_ref('season/245905/245905'))).isPlayable, isFalse);
    });

    test('stream tokens are never reused between calls', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      await provider.playback(_ref('245894'));
      await provider.playback(_ref('245894'));
      expect(log.where((r) => r.url.host == 'media-api.urplay.se'), hasLength(2));
    });
  });

  group('UrMaster', () {
    test('audio-only masters are told apart from video ones', () {
      const audio = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="mp4a.40.2"\naudio.m3u8\n';
      expect(UrMaster.parse(audio).hasVideo, isFalse);
      expect(UrMaster.parse(_text('master_hls_avc.m3u8')).hasVideo, isTrue);
    });

    test('subtitle names come from the master in its order', () {
      final master = UrMaster.parse(_text('master_hls_with_english.m3u8'));
      expect(master.subtitleNames, ['Litauiska', 'Svenska', 'Engelska']);
      expect(master.encrypted, isFalse);
    });

    test('a key with method NONE is not encryption', () {
      expect(UrMaster.parse('#EXTM3U\n#EXT-X-KEY:METHOD=NONE\n').encrypted, isFalse);
      expect(UrMaster.parse('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="k"\n').encrypted, isTrue);
    });
  });

  group('UrPlayProvider availability forecast', () {
    List<ReplayTitle> titles() => [
      ReplayTitle(ref: _ref('245901'), kind: ReplayKind.episode, title: 'a'),
      ReplayTitle(ref: _ref('245894'), kind: ReplayKind.episode, title: 'b'),
      ReplayTitle(ref: _ref('show/245905'), kind: ReplayKind.show, title: 'c'),
    ];

    test('Sweden-only titles are geoblocked outside Sweden', () async {
      final verdicts = await _provider().predictAvailability(titles(), 'BE');
      expect(verdicts[_ref('245901')], ReplayAvailability.geoBlocked);
      expect(verdicts[_ref('245894')], ReplayAvailability.playable);
      expect(verdicts[_ref('show/245905')], ReplayAvailability.geoBlocked);
    });

    test('a title the probe could not judge is left out', () async {
      final asked = [
        ReplayTitle(ref: _ref('245894'), kind: ReplayKind.episode, title: 'ok'),
        ReplayTitle(ref: _ref('222'), kind: ReplayKind.episode, title: 'rate limited'),
      ];
      final verdicts = await _provider().predictAvailability(asked, 'BE');
      expect(verdicts.keys, [_ref('245894')]);
    });

    test('viewers in Sweden are not asked anything', () async {
      final log = <http.Request>[];
      expect(await _provider(log: log).predictAvailability(titles(), 'se'), isEmpty);
      expect(log, isEmpty);
    });

    test('an answer is kept, so a second call asks nothing new', () async {
      final log = <http.Request>[];
      final provider = _provider(log: log);
      await provider.predictAvailability(titles().take(2).toList(), 'BE');
      final before = log.length;
      final again = await provider.predictAvailability(titles().take(2).toList(), 'BE');
      expect(again, hasLength(2));
      expect(log, hasLength(before));
    });

    test('answers that arrive in time are returned, late ones are not waited for', () async {
      final client = MediaServerHttpClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/245901')) await Future<void>.delayed(const Duration(milliseconds: 300));
          return _route(request);
        }),
      );
      final api = UrPlayApi(client);
      final probe = UrAvailabilityProbe(api, UrCatalog(api), budget: const Duration(milliseconds: 60));

      final verdicts = await UrPlayProvider.withApi(api, probe: probe).predictAvailability(titles(), 'BE');

      expect(verdicts[_ref('245894')], ReplayAvailability.playable);
      expect(verdicts.containsKey(_ref('245901')), isFalse);
    });
  });

  group('UR catalogue mapping', () {
    final item = _json('season_episodes')['accessibleEpisodes'][2] as Map<String, dynamic>;

    test('a window in the past is expired and one ahead is upcoming', () {
      Map<String, dynamic> windowed(String start, String end) => {
        ...item,
        'accessiblePlatforms': {
          'urplay': {'startTime': start, 'endTime': end},
        },
      };
      final now = DateTime.utc(2026, 10, 22);
      expect(
        urTitleFromItem(windowed('2020-01-01T00:00:00Z', '2021-01-01T00:00:00Z'), now: now)!.availability,
        ReplayAvailability.expired,
      );
      expect(
        urTitleFromItem(windowed('2030-01-01T00:00:00Z', '2031-01-01T00:00:00Z'), now: now)!.availability,
        ReplayAvailability.upcoming,
      );
      expect(
        urTitleFromItem(windowed('2026-01-01T00:00:00Z', '2027-01-01T00:00:00Z'), now: now)!.availability,
        ReplayAvailability.playable,
      );
    });

    test('the end of the window is the expiry date', () {
      final title = urTitleFromItem(item)!;
      expect(title.availableUntil, DateTime.utc(2099, 7, 31, 21, 59));
    });

    test('unknown product types and items without a title are skipped', () {
      expect(urTitleFromItem({...item, 'productType': 'playlist'}), isNull);
      expect(urTitleFromItem({...item, 'title': ' '}), isNull);
    });

    test('non-breaking spaces in titles become plain spaces', () {
      expect(urTitleFromItem({...item, 'title': 'Olof Wretling läser'})!.title, 'Olof Wretling läser');
    });
  });

  group('UR numbering', () {
    test('seasons are read from a description prefix', () {
      expect(urSeasonFromDescription('Säsong 5. Den 7-årige Monty'), 5);
      expect(urSeasonFromDescription('Den 7-årige Monty'), isNull);
      expect(urStripSeasonPrefix('Säsong 10. Vad säger vetenskapen?'), 'Vad säger vetenskapen?');
    });

    test('labels give the season and the episode', () {
      expect(urNumbersFromLabels(['Säsong 4', 'Avsnitt 2', '15 min']), (season: 4, episode: 2));
      expect(urNumbersFromLabels(['Nyheter', '3 min']), (season: null, episode: null));
      expect(urNumbersFromLabels(null), (season: null, episode: null));
    });

    test('titles that differ only by case or spacing are one show', () {
      expect(urTitleKey('Lässugen  '), urTitleKey('lässugen'));
      expect(urTitleKey('Lässugen'), isNot(urTitleKey('Lässugen - syntolkat')));
    });
  });

  group('UR refs', () {
    test('each level of the tree parses back to itself', () {
      expect(UrTarget.parse(urplayShowRef('5')), isA<UrShow>());
      final season = UrTarget.parse(urplaySeasonRef('5', '4')) as UrSeason;
      expect((season.showId, season.seriesId), ('5', '4'));
      expect((UrTarget.parse(urplayProgramRef('9')) as UrProgram).programId, '9');
      expect(ReplayRef.tryParse(urplaySeasonRef('5', '4').toString()), urplaySeasonRef('5', '4'));
    });

    test('foreign sources and malformed ids are rejected', () {
      expect(UrTarget.parse(const ReplayRef('arte', '123')), isNull);
      expect(UrTarget.parse(_ref('show/')), isNull);
      expect(UrTarget.parse(_ref('season/1')), isNull);
      expect(UrTarget.parse(_ref('abc')), isNull);
    });
  });

  group('UR images', () {
    const wide = 'https://assets.ur.se/id/245901/images/1_hd.jpg';
    const square = 'https://assets.ur.se/id/245901/images/1_sql.jpg';

    test('a box gets the smallest 16:9 size that covers it', () {
      expect(urImageUrl(wide, width: 300), endsWith('/1.jpg'));
      expect(urImageUrl(wide, width: 500), endsWith('/1_l.jpg'));
      expect(urImageUrl(wide, width: 9000), endsWith('/1_hd.jpg'));
      expect(urImageUrl(wide, height: 270), endsWith('/1_ml.jpg'));
      expect(urImageUrl(wide), endsWith('/1_l.jpg'));
    });

    test('a square reference stays square', () {
      expect(urImageUrl(square, width: 60), endsWith('/1_sq.jpg'));
      expect(urImageUrl(square, width: 300), endsWith('/1_sql.jpg'));
    });

    test('references come from the catalogue ladder or are built from the id', () {
      final images = {'1280x720': wide, '360x360': square};
      expect(urBackdropReference('245901', images), wide);
      expect(urPosterReference('245901', images), square);
      expect(urBackdropReference('7', null), 'https://assets.ur.se/id/7/images/1_hd.jpg');
      expect(urPosterReference('7', {'360x360': 'https://elsewhere.example/x.jpg'}), endsWith('/7/images/1_sql.jpg'));
    });

    test('the provider only claims its own pictures', () {
      final provider = _provider();
      expect(provider.ownsImage(wide), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl('https://example.com/a.jpg', width: 100), 'https://example.com/a.jpg');
    });
  });
}
