import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_api.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_images.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_mapper.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_numbering.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_playback.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_provider.dart';
import 'package:plezy/replay/providers/tvpvod/tvpvod_refs.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/tvpvod';

String _fixture(String name) => File('$_fixtures/$name.json').readAsStringSync();

Object? _decoded(String name) => jsonDecode(_fixture(name));

http.Response _json(String body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response(body, status, headers: {'content-type': 'application/json', ...headers});

/// Catalogue paths (under `/api/products/`) and the recorded response each one returns.
const _pages = {
  'sections/main': 'home',
  'sections/seriale': 'category_sections',
  'vods/316445': 'serial_ranczo',
  'vods/3452194': 'serial_foreign',
  'vods/344835': 'vod_film',
  'vods/381046': 'episode_ranczo_1',
  'vods/2451091': 'serial_frycek',
  'vods/273595': 'serial_barwy',
  'vods/serials/316445/seasons': 'seasons_ranczo',
  'vods/serials/316445/seasons/381045/episodes': 'episodes_ranczo_s1',
  'vods/serials/2451091/seasons': 'seasons_frycek',
  'vods/serials/2451091/seasons/2451092/episodes': 'episodes_frycek',
  'vods/serials/273595/seasons': 'seasons_barwy',
  'vods/serials/2028435/seasons/2028402/episodes': 'episodes_debate',
  '381046/videos/playlist': 'playlist_subtitles',
  '344835/videos/playlist': 'playlist_ok',
};

/// Playlist ids the site refuses, with the body it sends.
const _refusals = {
  '3452194': (403, '{"code":"GEOIP_FILTER_FAILED"}'),
  '3452019': (403, '{"code":"GEOIP_FILTER_FAILED"}'),
  '316445': (403, '{"code":"VIDEO_NOT_EXISTS"}'),
  '404404': (404, '{"code":"ITEM_NOT_EXISTS"}'),
  '402402': (403, '{"code":"PAYMENT_REQUIRED"}'),
};

/// Serves recorded responses like the live site: `platform=BROWSER` is mandatory, unknown ids are 404.
class _Site {
  final List<Uri> requests = [];
  late final TvpVodProvider provider = TvpVodProvider.withApi(
    TvpVodApi(MediaServerHttpClient(client: MockClient((r) async => _route(r)))),
  );

  http.Response _route(http.Request request) {
    requests.add(request.url);
    final query = request.url.queryParameters;
    if (query['platform'] != 'BROWSER') return _json('{"code":"PLATFORM_UNDEFINED"}', 400);
    final path = request.url.path.replaceFirst('/api/products/', '');

    final playlist = RegExp(r'^(\d+)/videos/playlist$').firstMatch(path);
    if (playlist != null && _refusals.containsKey(playlist.group(1))) {
      final (status, body) = _refusals[playlist.group(1)]!;
      return _json(body, status);
    }
    if (playlist?.group(1) == '429429') return _json('{}', 429, {'retry-after': '30'});
    if (path == 'vods') return _vods(request.url);
    if (path == 'vods/search/VOD_SERIAL') {
      return query['keyword'] == 'zzzz' ? _json('{"meta":{"totalCount":0},"items":[]}') : _json(_fixture('search'));
    }
    if (path == 'sections/filmy-fabularne') return _json('[]');
    final page = _pages[path];
    return page == null ? _json('{"code":"ITEM_NOT_EXISTS"}', 404) : _json(_fixture(page));
  }

  http.Response _vods(Uri url) {
    final first = url.queryParameters['firstResult'];
    return switch (first) {
      '0' => _json(_fixture('list_all')),
      '24' => _json(_fixture('list_all_page2')),
      _ => _json('{"meta":{"totalCount":6420},"items":[]}'),
    };
  }
}

ReplayRef _ref(String id) => ReplayRef('tvpvod', id);

ReplayTitle _title(String id, {ReplayKind kind = ReplayKind.show, ReplayRef? showRef}) =>
    ReplayTitle(ref: _ref(id), kind: kind, title: id, showRef: showRef);

Map<String, dynamic> _listItem(int index) =>
    ((_decoded('list_all')! as Map)['items'] as List)[index] as Map<String, dynamic>;

void main() {
  group('TvpVodProvider browsing', () {
    test('home keeps rows with series and films, and drops the rest', () async {
      final rails = await _Site().provider.home();
      expect(rails.map((r) => r.title), [
        'Polecane',
        'PREMIERY',
        'W PAKIECIE I Wcześniej niż w TV',
        'ZA DARMO | Hity wszech czasów',
      ]);
      final titles = [for (final r in rails) ...r.titles];
      expect(titles.every((t) => t.ref.source == 'tvpvod' && t.kind == ReplayKind.show), isTrue);
    });

    test('a category shows its curated rows, then its newest titles', () async {
      final rails = await _Site().provider.category('18');
      expect(rails.map((r) => r.title), ['Polecane', 'W PAKIECIE I Wcześniej niż w TV', 'Najnowsze']);
      expect(rails.last.moreBrowseId, 'cat:18:created');
      expect(rails.last.titles, isNotEmpty);
    });

    test('a category without curated rows falls back to two listings', () async {
      final site = _Site();
      final rails = await site.provider.category('136');
      expect(rails.map((r) => r.title), ['Najnowsze', 'Najnowsze produkcje']);
      final listings = site.requests.where((u) => u.path.endsWith('/products/vods'));
      expect(listings.map((u) => u.queryParametersAll['mainCategoryId[]']), [
        ['136'],
        ['136'],
      ]);
      expect(listings.map((u) => u.queryParameters['sort']), ['createdAt', 'year']);
    });

    test('the whole-catalogue listing pages through the site', () async {
      final site = _Site();
      final first = await site.provider.listing(replayAllBrowseId);
      expect(first.totalCount, 6420);
      expect(first.titles, hasLength(6));
      final second = await site.provider.listing(replayAllBrowseId, page: 1);
      expect(second.titles.first.title, 'Cuda wysokich gór');
      expect(site.requests.last.queryParameters['firstResult'], '24');
      expect(site.requests.last.queryParameters.containsKey('mainCategoryId[]'), isFalse);
    });

    test('a listing id carries its category and order', () async {
      final site = _Site();
      await site.provider.listing('cat:205:year');
      final query = site.requests.last.queryParameters;
      expect(site.requests.last.queryParametersAll['mainCategoryId[]'], ['205']);
      expect([query['sort'], query['order']], ['year', 'desc']);
    });

    test('search maps shows, and an empty or unmatched query finds nothing', () async {
      final site = _Site();
      final hits = await site.provider.search('debata');
      expect(hits, hasLength(5));
      expect(hits.first.title, 'Debata prezydencka przed I turą wyborów');
      expect(await site.provider.search('zzzz'), isEmpty);
      final before = site.requests.length;
      expect(await site.provider.search('  '), isEmpty);
      expect(site.requests, hasLength(before));
    });

    test('the menu lists the seven main categories', () async {
      final categories = await _Site().provider.categories();
      expect(categories.map((c) => c.id), ['18', '136', '163', '88', '205', '24', '202']);
    });
  });

  group('TvpVodProvider shows', () {
    test('a series lists its seasons with their parents', () async {
      final seasons = await _Site().provider.children(_ref('316445'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      expect(seasons.map((s) => s.ref.nativeId), ['316445/381045', '316445/381149', '316445/381066']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('316445')), isTrue);
      expect(seasons.first.showTitle, 'Ranczo');
    });

    test('a season lists its episodes with numbers and parents', () async {
      final episodes = await _Site().provider.children(_ref('316445/381045'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3]);
      final first = episodes.first;
      expect(first.kind, ReplayKind.episode);
      expect(first.title, 'Spadek');
      expect(first.seasonNumber, 1);
      expect(first.seasonRef, _ref('316445/381045'));
      expect(first.showRef, _ref('316445'));
      expect(first.showTitle, 'Ranczo');
      expect(first.durationSeconds, 2951);
    });

    test('a soap cut into blocks lists them oldest first', () async {
      final seasons = await _Site().provider.children(_ref('273595'));
      expect(seasons, hasLength(28));
      expect(seasons.map((s) => s.seasonNumber), [for (var n = 8; n <= 35; n++) n]);
      expect(seasons.first.title, '782–800');
    });

    test('the number printed in the title wins over the running index', () async {
      final episodes = await _Site().provider.children(_ref('2451091/2451092'));
      expect(episodes.map((e) => e.episodeNumber), [34, 35, 36, 38, 39]);
      expect(episodes.map((e) => e.title), ['Beatbox', 'Fryckorobic', 'Zegary', 'Gotowanie', 'Sampler']);
    });

    test('a season named "Odcinki" keeps its name and number', () async {
      final seasons = await _Site().provider.children(_ref('2451091'));
      expect(seasons.single.title, 'Odcinki');
      expect(seasons.single.seasonNumber, 1);
    });

    test('a single programme has no episode number', () async {
      final episodes = await _Site().provider.children(_ref('2028435/2028402'));
      expect(episodes.single.episodeNumber, isNull);
      expect(episodes.single.title, 'Końskie 2025. Debata przedwyborcza');
    });

    test('an episode page knows its show and season', () async {
      final episode = await _Site().provider.title(_ref('381046'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.showRef, _ref('316445'));
      expect(episode.seasonRef, _ref('316445/381045'));
      expect(episode.episodeNumber, 1);
    });

    test('a film page carries its credits and plain-text synopsis', () async {
      final film = await _Site().provider.title(_ref('344835'));
      expect(film!.kind, ReplayKind.movie);
      expect(film.directors, ['Grzegorz Braun']);
      expect(film.year, 2009);
      expect(film.summary, isNot(contains('<')));
      expect(film.contentRating, '12+');
    });

    test('a season is found by its ref, and a missing title is null', () async {
      final provider = _Site().provider;
      expect((await provider.title(_ref('316445/381149')))!.seasonNumber, 2);
      expect(await provider.title(_ref('999999')), isNull);
    });

    test('a film has no seasons', () async {
      expect(await _Site().provider.children(_ref('344835')), isEmpty);
    });
  });

  group('TvpVodProvider playback', () {
    test('an episode yields its HLS master, subtitles and credits marker', () async {
      final playback = await _Site().provider.playback(_ref('381046'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('/video.m3u8'));
      expect(playback.subtitles.single.languageCode, 'pl');
      expect(playback.subtitles.single.label, 'Polski (dla niesłyszących)');
      expect(playback.credits?.start, const Duration(seconds: 2861));
      expect(playback.credits?.end, const Duration(seconds: 2951));
    });

    test('a film plays without subtitles', () async {
      final playback = await _Site().provider.playback(_ref('344835'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.path, endsWith('/video-fmp4.m3u8'));
      expect(playback.subtitles, isEmpty);
    });

    test('a refused country is reported as geoblocked', () async {
      final playback = await _Site().provider.playback(_ref('3452194'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('a show id is not a video', () async {
      final playback = await _Site().provider.playback(_ref('316445'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, 'VIDEO_NOT_EXISTS');
    });

    test('a missing product is reported as expired, not as an error', () async {
      expect((await _Site().provider.playback(_ref('404404'))).availability, ReplayAvailability.expired);
    });

    test('a payment refusal asks for an account', () async {
      expect((await _Site().provider.playback(_ref('402402'))).availability, ReplayAvailability.loginRequired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _Site().provider.playback(_ref('429429'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a season ref is never played directly', () async {
      expect((await _Site().provider.playback(_ref('316445/381045'))).isPlayable, isFalse);
    });

    test('DASH is used only when no HLS is offered', () {
      final dash = TvpPlaylistReply(200, {
        'sources': {
          'DASH': [
            {'src': 'https://cdn.example/video.mpd'},
          ],
        },
      });
      expect(tvpParsePlayback(dash).streams.single.url.path, '/video.mpd');
      expect(tvpParsePlayback(const TvpPlaylistReply(200, {'sources': {}})).isPlayable, isFalse);
    });
  });

  group('TvpVodProvider availability forecast', () {
    test('a foreign production is predicted blocked outside Poland', () async {
      final site = _Site();
      final page = await site.provider.listing(replayAllBrowseId, page: 1);
      final verdicts = await site.provider.predictAvailability(page.titles, 'BE');
      expect(verdicts, {_ref('3452194'): ReplayAvailability.geoBlocked});
    });

    test('a Polish production is not predicted blocked', () async {
      final verdicts = await _Site().provider.predictAvailability([_title('316445')], 'BE');
      expect(verdicts, isEmpty);
    });

    test('a viewer in Poland is never asked about anything', () async {
      final site = _Site();
      expect(await site.provider.predictAvailability([_title('3452194')], 'PL'), isEmpty);
      expect(site.requests, isEmpty);
    });

    test('an episode follows the production country of its show', () async {
      final episode = _title('555', kind: ReplayKind.episode, showRef: _ref('3452194'));
      final verdicts = await _Site().provider.predictAvailability([episode], 'DE');
      expect(verdicts, {_ref('555'): ReplayAvailability.geoBlocked});
    });

    test('a refusal seen while playing is remembered', () async {
      final provider = _Site().provider;
      await provider.playback(_ref('3452019'));
      final verdicts = await provider.predictAvailability([_title('3452019', kind: ReplayKind.movie)], 'BE');
      expect(verdicts, {_ref('3452019'): ReplayAvailability.geoBlocked});
    });

    test('a title the site cannot describe is left out', () async {
      expect(await _Site().provider.predictAvailability([_title('777777')], 'BE'), isEmpty);
    });
  });

  group('TvpVodProvider mapping', () {
    final now = DateTime.utc(2026, 10, 22);

    test('a paid film asks for an account and a free one plays', () {
      expect(tvpTitleFromItem(_listItem(0), now: now)!.availability, ReplayAvailability.loginRequired);
      expect(tvpTitleFromItem(_listItem(1), now: now)!.availability, ReplayAvailability.playable);
    });

    test('a finished licence is expired and a future one is upcoming', () {
      expect(tvpTitleFromItem(_listItem(1), now: DateTime.utc(2027))!.availability, ReplayAvailability.expired);
      expect(tvpTitleFromItem(_listItem(1), now: DateTime.utc(2026, 10, 1))!.availability, ReplayAvailability.upcoming);
    });

    test('an open-ended licence has no end date', () {
      expect(tvpTitleFromItem(_listItem(4), now: now)!.availableUntil, isNull);
      expect(tvpTitleFromItem(_listItem(1), now: now)!.availableUntil, DateTime.utc(2026, 11, 17, 22, 55));
    });

    test('live channels, banners and collections are not titles', () {
      for (final type in ['LIVE', 'BANNER', 'SECTION']) {
        expect(tvpTitleFromItem({'type': type, 'id': 1, 'title': 'x'}), isNull, reason: type);
      }
    });

    test('episode labels come from the title, then from the running index', () {
      expect(tvpEpisodeLabel('odc. 1 – Spadek', 1), (number: 1, title: 'Spadek'));
      expect(tvpEpisodeLabel('odcinek 39 – Sampler', 44), (number: 39, title: 'Sampler'));
      expect(tvpEpisodeLabel('Odcinek 5: Pilot', null), (number: 5, title: 'Pilot'));
      expect(tvpEpisodeLabel('odc. 3426', 3426), (number: 3426, title: 'odc. 3426'));
      expect(tvpEpisodeLabel('Wieczór wyborczy', 2), (number: 2, title: 'Wieczór wyborczy'));
      expect(tvpEpisodeLabel('Debata', -1).number, isNull);
    });

    test('season refs split into show and season ids', () {
      expect(tvpSeasonParts(_ref('316445/381045')), (serialId: '316445', seasonId: '381045'));
      expect(tvpSeasonParts(_ref('316445')), isNull);
      expect(tvpSeasonParts(_ref('316445/')), isNull);
    });
  });

  group('TVP VOD images', () {
    test('artwork references are absolute and keep the size slots', () async {
      final show = (await _Site().provider.search('debata')).first;
      expect(show.posterUrl, startsWith('https://s.tvp.pl/images/'));
      expect(show.posterUrl, contains('{width:'));
    });

    test('the show backdrop comes from the large artwork', () async {
      final show = await _Site().provider.title(_ref('316445'));
      expect(show!.backdropUrl, contains('{width:1920}'));
      expect(show.logoUrl, contains('{width:315}'));
    });

    test('both sides given fill both slots', () {
      const template =
          'https://s.tvp.pl/images/a/b/c/uid_x_width_{width:315}_play_0_pos_0_gs_0_height_{height:177}.png';
      expect(tvpImageUrl(template, width: 640, height: 360), contains('width_640_play_0_pos_0_gs_0_height_360.png'));
    });

    test('one side given keeps the proportions of the template', () {
      const wide = 'https://s.tvp.pl/images/a/uid_width_{width:315}_play_0_height_{height:177}.png';
      const tall = 'https://s.tvp.pl/images/a/uid_width_{width:560}_play_0_height_{height:746}.jpg';
      expect(tvpImageUrl(wide, width: 630), contains('width_630_play_0_height_354.png'));
      expect(tvpImageUrl(tall, height: 373), contains('width_280_play_0_height_373.jpg'));
    });

    test('no size keeps the default and a huge size is capped', () {
      const template = 'https://s.tvp.pl/images/a/uid_width_{width:315}_play_0_height_{height:177}.png';
      expect(tvpImageUrl(template), contains('width_315_play_0_height_177'));
      expect(tvpImageUrl(template, width: 5000, height: 5000), contains('width_1920_play_0_height_1920'));
    });

    test('a fixed-size address is returned unchanged and ownership is by host', () {
      const fixed = 'https://s.tvp.pl/images/a/uid_width_315_height_177.png';
      expect(tvpImageUrl(fixed, width: 640), fixed);
      final provider = _Site().provider;
      expect(provider.ownsImage(fixed), isTrue);
      expect(provider.ownsImage('https://example.com/a.png'), isFalse);
    });
  });
}
