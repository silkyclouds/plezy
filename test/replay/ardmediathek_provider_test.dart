import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_api.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_images.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_numbering.dart';
import 'package:plezy/replay/providers/ardmediathek/ardmediathek_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/ardmediathek';

const _watzmann = 'Y3JpZDovL2JyLmRlL2Jyb2FkY2FzdFNlcmllcy9lMzk1OGEyNi0wYjZiLTRiZmMtOTE3Mi01NDA3YjFhYjQwNGY';
const _yang = 'Y3JpZDovL3N3ci5kZS9zZGIvc3RJZC8xOTIx';
const _tagesschau = 'Y3JpZDovL2Rhc2Vyc3RlLmRlL3RhZ2Vzc2NoYXU';
const _single = 'Y3JpZDovL25kci5kZS81MDQzIGM4ZDUyNDkxLTk5ODUtNGJjZi05ZjlhLTc4MWM0MmE4ZDM1Mw';

const _episodeItem = 'Y3JpZDovL2JyLmRlL2Jyb2FkY2FzdC9GMjAyNFdPMDAxMDcyQTA';
const _filmItem = 'Y3JpZDovL2Rhc2Vyc3RlLmRlL2Zlcm5zZWhmaWxtZSBpbSBlcnN0ZW4vMjAyMy0xMS0wNF8xNC0wMC1NRVo';
const _geoItem = 'Y3JpZDovL3N3ci5kZS9hZXgvbzIzNTU0NDA';
const _newsItem = 'Y3JpZDovL3RhZ2Vzc2NoYXUuZGUvNGJkN2JjNDAtMjg2YS00M2FmLWE3M2ItZTBmM2QyMmJiMGE4LVNFTkRVTkdTVklERU8';
const _kikaItem = 'Y3JpZDovL2tpa2EuZGUvcHVibGlrYXRpb24vY29udGVudC04ODE1Ml8xNzkxMTM4NjAwMDAw';
const _fskItem = 'Y3JpZDovL2FydGUudHYvcHVibGljYXRpb24vMDczMDEwLTAwMC1B';

const _items = {
  _episodeItem: 'item_series_episode',
  _filmItem: 'item_film',
  _geoItem: 'item_geoblocked',
  _newsItem: 'item_tagesschau',
  _kikaItem: 'item_kika',
  _fskItem: 'item_fsk16_blocked_by_time',
};

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// A recorded gateway. [edit] changes a decoded fixture before it is served; [cdn] answers stream probes by host.
class _Gateway {
  final List<Uri> requests = [];
  final Map<String, void Function(Map<String, dynamic>)> edits = {};
  final Map<String, int> cdn = {'swr-adaptive.ard-mcdn.de': 403};
  int? status;
  Map<String, String> statusHeaders = const {};

  http.Response handle(http.Request request) {
    requests.add(request.url);
    final path = request.url.path.replaceFirst('/page-gateway', '');
    if (!request.url.host.startsWith('api.')) return _stream(request.url);
    if (status != null) return http.Response('', status!, headers: statusHeaders);
    final name = _fixtureFor(path, request.url.queryParameters);
    if (name == null) return http.Response('{}', 404);
    final body = _json(name);
    edits[name]?.call(body);
    return _jsonResponse(body);
  }

  http.Response _stream(Uri url) =>
      http.Response.bytes(utf8.encode('#EXTM3U'), cdn[url.host] ?? 206, headers: {'content-type': 'text/plain'});

  String? _fixtureFor(String path, Map<String, String> query) {
    final item = RegExp(r'^/pages/ard/item/(.+)$').firstMatch(path)?.group(1);
    if (item != null) return _items[item];
    final group = RegExp(r'^/pages/ard/grouping/(.+)$').firstMatch(path)?.group(1);
    if (group != null) return _groupings[group];
    final asset = RegExp(r'^/widgets/ard/asset/(.+)$').firstMatch(path)?.group(1);
    if (asset != null) {
      final watzmannSeason3 = asset == _watzmann && query['seasonNumber'] == '3';
      return watzmannSeason3 ? 'season_widget' : _assets[asset];
    }
    if (path.startsWith('/widgets/ard/search/')) {
      final empty = query['searchString'] == 'zzzz';
      return empty ? 'widget_empty' : (path.endsWith('/vod') ? 'search_vod' : 'search_grouping');
    }
    return switch (path) {
      '/pages/ard/home' || '/pages/kika/home' => 'home',
      '/pages/ard/editorial/filme' => 'category_filme',
      _ => path.startsWith('/widgets/ard/editorials/') ? 'widget_watzmann_all' : null,
    };
  }

  static const _groupings = {
    _watzmann: 'show_grouping_with_seasons',
    _yang: 'show_grouping_season_series',
    _tagesschau: 'show_grouping_infinite_series_tagesschau',
    _single: 'show_grouping_single',
  };
  static const _assets = {
    _watzmann: 'widget_watzmann_all',
    _yang: 'widget_house_of_yang',
    _tagesschau: 'widget_tagesschau',
    _single: 'widget_single',
  };
}

http.Response _jsonResponse(Map<String, dynamic> body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});

ArdMediathekProvider _provider(_Gateway gateway, {DateTime? now}) {
  final client = MediaServerHttpClient(client: MockClient((r) async => gateway.handle(r)));
  final api = ArdMediathekApi(client, minSpacing: Duration.zero);
  return ArdMediathekProvider.withApi(api, clock: () => now ?? DateTime.utc(2026, 10, 22, 8));
}

ReplayRef _ref(String nativeId) => ReplayRef('ardmediathek', nativeId);

ReplayRef _item(String id) => _ref('item/$id');

Map<String, dynamic> _firstWidget(Map<String, dynamic> page) => (page['widgets'] as List).first as Map<String, dynamic>;

void main() {
  group('ARD Mediathek browsing', () {
    test('home keeps rows with programmes and drops navigation', () async {
      final rails = await _provider(_Gateway()).home();
      expect(rails.map((r) => r.title), [
        'Die besten Videos aus der ARD Mediathek',
        'Unsere Top-Serien',
        'Film-Empfehlungen',
      ]);
      expect(rails.every((r) => r.titles.every((t) => t.ref.source == 'ardmediathek')), isTrue);
    });

    test('a row with more cards than shown offers a listing path', () async {
      final rails = await _provider(_Gateway()).home();
      final series = rails.firstWhere((r) => r.title == 'Unsere Top-Serien');
      expect(series.moreBrowseId, startsWith('ard/editorials/'));
      expect(series.moreBrowseId, isNot(contains('?')));
    });

    test('shows and videos get the matching kinds, numbers and parents', () async {
      final rails = await _provider(_Gateway()).home();
      final stage = rails.first.titles;
      expect(stage.map((t) => t.kind), [ReplayKind.show, ReplayKind.show, ReplayKind.episode]);
      final video = stage.last;
      expect(video.title, 'Hikikomori · Ein Leben in Isolation');
      expect(video.subtitle, 'Reportage');
      expect(video.showTitle, 'Y-Kollektiv');
      expect(video.seasonRef!.nativeId, endsWith('/all'));
      final series = rails[1].titles.first;
      expect(series.title, 'House of Yang');
      expect(series.subtitle, startsWith('Sechsteilige'));
      expect(series.childCount, 1);
    });

    test('films in a category are movies or episodes of their series', () async {
      final rails = await _provider(_Gateway()).category('rubrik/filme');
      final titles = [for (final r in rails) ...r.titles];
      final byTitle = {for (final t in titles) t.title: t};
      expect(byTitle['Sommer auf Asphalt']!.kind, ReplayKind.movie);
      expect(byTitle['Sommer auf Asphalt']!.showRef, isNull);
      expect(byTitle['Unter Feinden (2)']!.kind, ReplayKind.episode);
      expect(byTitle['Unter Feinden (2)']!.showTitle, 'Tatort');
      expect(byTitle['Unter Feinden (2)']!.contentRating, 'FSK 12');
    });

    test('a channel category loads that channel landing page', () async {
      final gateway = _Gateway();
      await _provider(gateway).category('kanal/kika');
      expect(gateway.requests.single.path, '/page-gateway/pages/kika/home');
    });

    test('categories offer the themes and the channels, not ARTE', () async {
      final categories = await _provider(_Gateway()).categories();
      expect(categories.map((c) => c.id), containsAll(['rubrik/filme', 'kanal/daserste', 'kanal/3sat']));
      expect(categories.any((c) => c.id.contains('arte') || c.title == 'ARTE'), isFalse);
    });

    test('the whole catalogue is the show search for one letter', () async {
      final gateway = _Gateway();
      final page = await _provider(gateway).listing(replayAllBrowseId, page: 2);
      expect(page.totalCount, 47);
      expect(page.titles.every((t) => t.kind == ReplayKind.show), isTrue);
      final query = gateway.requests.single.queryParameters;
      expect(query['searchString'], 'a');
      expect(query['pageNumber'], '2');
      expect(query['pageSize'], '48');
    });

    test('a row listing fetches the row by the path the page gave', () async {
      final gateway = _Gateway();
      final provider = _provider(gateway);
      final row = (await provider.home()).firstWhere((r) => r.moreBrowseId != null);
      final page = await provider.listing(row.moreBrowseId!, page: 1);
      expect(page.titles, isNotEmpty);
      final request = gateway.requests.last;
      expect(request.path, startsWith('/page-gateway/widgets/ard/editorials/'));
      expect(request.path, contains('%3A'));
      expect(request.queryParameters['pageNumber'], '1');
    });

    test('search lists shows first and drops accessibility copies', () async {
      final titles = await _provider(_Gateway()).search('tatort');
      expect(titles.take(5).every((t) => t.kind == ReplayKind.show), isTrue);
      final videos = titles.skip(5).toList();
      expect(videos.map((t) => t.title), ['Wer hat Recht?', 'Schweigen']);
    });

    test('a blank or unmatched search returns nothing', () async {
      final provider = _provider(_Gateway());
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });

    test('ARTE cards are left to the ARTE provider', () async {
      final gateway = _Gateway();
      gateway.edits['home'] = (page) {
        final teaser = (_firstWidget(page)['teasers'] as List).first as Map<String, dynamic>;
        teaser['publicationService'] = {'partner': 'arte', 'name': 'ARTE'};
      };
      final titles = [for (final r in await _provider(gateway).home()) ...r.titles];
      expect(titles.map((t) => t.title), isNot(contains('Motsi & Oti · Meet the Mabuses')));
      expect(titles.map((t) => t.title), contains('Der Fall Josephine R. · Eine Familie am Abgrund'));
    });
  });

  group('ARD Mediathek shows', () {
    test('a series lists one season per available number', () async {
      final seasons = await _provider(_Gateway()).children(_ref('show/$_watzmann'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2, 3, 4, 5, 6, 7]);
      expect(seasons.first.title, 'Staffel 1');
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show/$_watzmann')), isTrue);
      expect(seasons[2].ref, _ref('show/$_watzmann/3'));
    });

    test('a season lists numbered episodes in order without the label', () async {
      final provider = _provider(_Gateway());
      final episodes = await provider.children(_ref('show/$_watzmann/3'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5]);
      expect(episodes.first.title, 'Martha Hari');
      expect(episodes.first.seasonNumber, 3);
      expect(episodes.first.seasonRef, _ref('show/$_watzmann/3'));
      expect(episodes.first.showTitle, 'Watzmann ermittelt');
      expect(episodes.first.durationSeconds, 2908);
    });

    test('the season request asks for one season and no other versions', () async {
      final gateway = _Gateway();
      await _provider(gateway).children(_ref('show/$_watzmann/3'));
      final query = gateway.requests.last.queryParameters;
      expect(query['seasoned'], 'true');
      expect(query['seasonNumber'], '3');
      expect(query['withAudiodescription'], 'false');
    });

    test('extras and accessibility copies are dropped from a season', () async {
      final episodes = await _provider(_Gateway()).children(_ref('show/$_yang/1'));
      expect(episodes.map((e) => e.title), ['Jessie', 'Es ist schon mal passiert', 'Die Blume an der Wand']);
      expect(episodes.map((e) => e.kind).toSet(), {ReplayKind.episode});
    });

    test('a daily programme gets one season holding its newest editions', () async {
      final provider = _provider(_Gateway());
      final seasons = await provider.children(_ref('show/$_tagesschau'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('show/$_tagesschau/all'));
      expect(seasons.single.seasonNumber, 1);
      final editions = await provider.children(seasons.single.ref);
      expect(editions.first.title, 'tagesschau 00:05 Uhr, 22.10.2026');
      expect(editions.every((e) => e.episodeNumber == null && e.seasonNumber == 1), isTrue);
    });

    test('a film grouping has one season with the film alone', () async {
      final provider = _provider(_Gateway());
      final seasons = await provider.children(_ref('show/$_single'));
      expect(seasons.single.ref.nativeId, endsWith('/all'));
      final videos = await provider.children(seasons.single.ref);
      expect(videos.map((v) => v.title), ['Sommer auf Asphalt']);
    });

    test('an episode page knows its show, season and synopsis', () async {
      final episode = (await _provider(_Gateway()).title(_item(_episodeItem)))!;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Martha Hari');
      expect(episode.seasonNumber, 3);
      expect(episode.episodeNumber, 1);
      expect(episode.showRef, _ref('show/$_watzmann'));
      expect(episode.seasonRef, _ref('show/$_watzmann/3'));
      expect(episode.summary, startsWith('An der Ache'));
      expect(episode.availableUntil, DateTime.utc(2027, 7, 30, 20));
    });

    test('a show page and a season are found by their refs', () async {
      final provider = _provider(_Gateway());
      final show = (await provider.title(_ref('show/$_yang')))!;
      expect(show.kind, ReplayKind.show);
      expect(show.title, 'House of Yang');
      expect(show.posterUrl, contains('urn:ard:image:b67cd4f62463018a'));
      final season = (await provider.title(_ref('show/$_yang/1')))!;
      expect(season.title, 'Staffel 1');
      expect(await provider.title(_ref('show/$_yang/9')), isNull);
    });

    test('unknown refs and missing pages give nothing', () async {
      final provider = _provider(_Gateway());
      expect(await provider.title(_item('missing')), isNull);
      expect(await provider.title(const ReplayRef('arte', 'item/x')), isNull);
      expect(await provider.children(_item(_episodeItem)), isEmpty);
    });
  });

  group('ARD Mediathek numbering', () {
    test('the S/E label gives both numbers and the running number goes', () {
      final parsed = ardEpisodeTitle('Folge 29: Martha Hari (S03/E01)');
      expect((parsed.title, parsed.season, parsed.episode), ('Martha Hari', 3, 1));
    });

    test('a label without brackets or a running number is understood', () {
      expect(ardEpisodeTitle('Das Ende S2/E10').episode, 10);
      expect(ardEpisodeTitle('Das Ende S2/E10').title, 'Das Ende');
      expect(ardEpisodeTitle('Folge 4012: Der Streit').episode, 4012);
      expect(ardEpisodeTitle('Folge 4012: Der Streit').title, 'Folge 4012: Der Streit');
    });

    test('a plain title has no numbers', () {
      final parsed = ardEpisodeTitle('tagesschau 20:00 Uhr, 21.10.2026');
      expect((parsed.season, parsed.episode), (null, null));
    });

    test('a tagline splits off at the first bar only', () {
      expect(ardSplitTitle('Show | Tagline | more').subtitle, 'Tagline | more');
      expect(ardSplitTitle('Alone').subtitle, isNull);
    });
  });

  group('ARD Mediathek playback', () {
    test('a film plays the HLS master with the audio-described track', () async {
      final playback = await _provider(_Gateway()).playback(_item(_filmItem));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['DE', 'AD']);
      expect(playback.streams.first.url.host, 'universal-vod.daserste.de');
      expect(playback.streams.first.url.path, endsWith('.m3u8'));
      expect(playback.subtitles.single.languageCode, 'de');
      expect(playback.subtitles.single.url.path, endsWith('.vtt'));
    });

    test('a video without an HLS master falls back to its tallest MP4', () async {
      final gateway = _Gateway();
      gateway.edits['item_tagesschau'] = (page) {
        final media = _media(page);
        media.removeWhere((m) => m['mimeType'] == 'application/vnd.apple.mpegurl');
      };
      final playback = await _provider(gateway).playback(_item(_newsItem));
      expect(playback.streams.single.url.path, endsWith('webxxl.h264.mp4'));
    });

    test('a video open to every country plays without asking the CDN', () async {
      final gateway = _Gateway();
      await _provider(gateway).playback(_item(_episodeItem));
      expect(gateway.requests.where((u) => !u.host.startsWith('api.')), isEmpty);
    });

    test('a flagged video the CDN refuses is reported as geoblocked', () async {
      final playback = await _provider(_Gateway()).playback(_item(_geoItem));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
    });

    test('a flagged video the CDN accepts still plays', () async {
      final gateway = _Gateway()..cdn['swr-adaptive.ard-mcdn.de'] = 206;
      final playback = await _provider(gateway).playback(_item(_geoItem));
      expect(playback.isPlayable, isTrue);
    });

    test('an evening-only video is reported as time restricted', () async {
      final playback = await _provider(_Gateway()).playback(_item(_fskItem));
      expect(playback.availability, ReplayAvailability.timeSlotRestricted);
    });

    test('login-only, ended and unpublished videos say why', () async {
      final gateway = _Gateway();
      final provider = _provider(gateway);
      gateway.edits['item_kika'] = (page) => _firstWidget(page)['blockedByLoginOnly'] = true;
      expect((await provider.playback(_item(_kikaItem))).availability, ReplayAvailability.loginRequired);

      gateway.edits['item_kika'] = (page) => _firstWidget(page)['availableTo'] = '2026-10-01T00:00:00Z';
      expect((await provider.playback(_item(_kikaItem))).availability, ReplayAvailability.expired);

      gateway.edits['item_kika'] = (page) {
        _firstWidget(page)['mediaCollection'] = null;
        _firstWidget(page)['broadcastedOn'] = '2026-12-01T00:00:00Z';
      };
      expect((await provider.playback(_item(_kikaItem))).availability, ReplayAvailability.upcoming);
    });

    test('a video the gateway no longer knows is reported as ended', () async {
      final playback = await _provider(_Gateway()).playback(_item('gone'));
      expect(playback.availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final gateway = _Gateway()
        ..status = 429
        ..statusHeaders = {'retry-after': '30'};
      final provider = _provider(gateway);
      final playback = await provider.playback(_item(_filmItem));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
      final again = await provider.playback(_item(_filmItem));
      expect(again.message, contains('Rate limited'));
      expect(gateway.requests, hasLength(1));
    });

    test('a show is never played directly', () async {
      expect((await _provider(_Gateway()).playback(_ref('show/$_yang'))).isPlayable, isFalse);
    });

    test('the client is identified and sends no credentials', () async {
      final seen = <Map<String, String>>[];
      final client = MediaServerHttpClient(
        client: MockClient((r) async {
          seen.add(r.headers);
          return _jsonResponse(_json('home'));
        }),
      );
      await ArdMediathekProvider.withApi(ArdMediathekApi(client, minSpacing: Duration.zero)).home();
      expect(seen.single['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
      expect(seen.single.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });
  });

  group('ARD Mediathek availability forecast', () {
    ReplayTitle card(String id) => ReplayTitle(ref: _item(id), kind: ReplayKind.episode, title: id);

    Future<Map<ReplayRef, ReplayAvailability>> forecast(_Gateway gateway, String country, [List<String>? ids]) {
      final asked = [
        for (final id in ids ?? [_geoItem, _episodeItem, _fskItem]) card(id),
      ];
      return _provider(gateway).predictAvailability(asked, country);
    }

    test('a viewer in Belgium sees flagged and evening-only videos blocked', () async {
      final verdicts = await forecast(_Gateway(), 'BE');
      expect(verdicts[_item(_geoItem)], ReplayAvailability.geoBlocked);
      expect(verdicts[_item(_episodeItem)], ReplayAvailability.playable);
      expect(verdicts[_item(_fskItem)], ReplayAvailability.timeSlotRestricted);
    });

    test('a viewer in Germany or Austria can watch a DACH video', () async {
      expect((await forecast(_Gateway(), 'DE'))[_item(_geoItem)], ReplayAvailability.playable);
      expect((await forecast(_Gateway(), 'at'))[_item(_geoItem)], ReplayAvailability.playable);
    });

    test('a video licensed for Germany only is blocked in Austria', () async {
      final gateway = _Gateway();
      gateway.edits['item_geoblocked'] = (page) {
        final media = _media(page);
        for (final m in media) {
          m['url'] = (m['url'] as String).replaceFirst('/geo/de-at-ch/', '/geo/de/');
        }
      };
      expect((await forecast(gateway, 'AT'))[_item(_geoItem)], ReplayAvailability.geoBlocked);
      expect((await forecast(gateway, 'DE'))[_item(_geoItem)], ReplayAvailability.playable);
    });

    test('a flagged video the CDN lets through is not greyed out', () async {
      final gateway = _Gateway()..cdn['swr-adaptive.ard-mcdn.de'] = 206;
      expect((await forecast(gateway, 'BE'))[_item(_geoItem)], ReplayAvailability.playable);
    });

    test('a flagged video hosted by ARTE is not blocked', () async {
      final gateway = _Gateway();
      gateway.edits['item_geoblocked'] = (page) {
        for (final m in _media(page)) {
          m['url'] = 'https://manifest-arte.akamaized.net/x/master.m3u8';
        }
      };
      expect((await forecast(gateway, 'BE'))[_item(_geoItem)], ReplayAvailability.playable);
    });

    test('shows, seasons and unreadable pages are not judged', () async {
      final provider = _provider(_Gateway());
      final verdicts = await provider.predictAvailability([
        ReplayTitle(ref: _ref('show/$_yang'), kind: ReplayKind.show, title: 'show'),
        ReplayTitle(ref: _ref('show/$_yang/1'), kind: ReplayKind.season, title: 'season'),
        card('missing'),
      ], 'BE');
      expect(verdicts, isEmpty);
    });

    test('answers are remembered between lists', () async {
      final gateway = _Gateway();
      final provider = _provider(gateway);
      await provider.predictAvailability([card(_geoItem)], 'BE');
      await provider.predictAvailability([card(_geoItem)], 'BE');
      expect(gateway.requests.where((u) => u.path.endsWith(_geoItem)), hasLength(1));
      expect(gateway.requests.where((u) => u.host == 'swr-adaptive.ard-mcdn.de'), hasLength(1));
    });
  });

  group('ARD Mediathek images', () {
    test('the width placeholder is filled with a size the resizer keeps', () {
      const template = 'https://api.ardmediathek.de/image-service/images/urn:ard:image:abc?w={width}&ch=1';
      expect(ardImageUrl(template, width: 300), endsWith('w=320&ch=1'));
      expect(ardImageUrl(template, width: 500), endsWith('w=640&ch=1'));
      expect(ardImageUrl(template, width: 5000), endsWith('w=1280&ch=1'));
      expect(ardImageUrl(template), endsWith('w=640&ch=1'));
    });

    test('shows carry portrait and landscape art, episodes landscape only', () async {
      final provider = _provider(_Gateway());
      final rails = await provider.home();
      final show = rails[1].titles.first;
      expect(show.posterUrl, contains('urn:ard:image:b67cd4f62463018a'));
      expect(show.backdropUrl, contains('urn:ard:image:e5fea83e129315b0'));
      expect(provider.ownsImage(show.posterUrl!), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      final episode = (await provider.children(_ref('show/$_watzmann/3'))).first;
      expect(episode.posterUrl, isNull);
      expect(provider.imageUrl(episode.backdropUrl!, width: 640), isNot(contains('{width}')));
    });
  });

  test('a native id with slashes survives a ref round trip', () {
    final ref = ReplayRef.tryParse('ardmediathek:show/abc/3');
    expect(ref, _ref('show/abc/3'));
    expect(ReplayRef.tryParse(ref.toString()), ref);
  });
}

List<Map<String, dynamic>> _media(Map<String, dynamic> page) {
  final collection = (_firstWidget(page)['mediaCollection'] as Map)['embedded'] as Map<String, dynamic>;
  final stream = (collection['streams'] as List).first as Map<String, dynamic>;
  return (stream['media'] as List).cast<Map<String, dynamic>>();
}
