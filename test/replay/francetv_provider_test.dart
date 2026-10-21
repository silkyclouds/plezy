import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/francetv/francetv_api.dart';
import 'package:plezy/replay/providers/francetv/francetv_images.dart';
import 'package:plezy/replay/providers/francetv/francetv_numbering.dart';
import 'package:plezy/replay/providers/francetv/francetv_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/francetv';
const _showPath = 'france-2_dix-pour-cent';
const _seasonPath = 'france-2_dix-pour-cent_saison-1';
const _flatPath = 'france-3_un-si-grand-soleil';
const _geoBlockedId = 'cb4c5ebc-6227-45d9-834b-152beef3eae1';

final _now = DateTime.utc(2026, 10, 21, 12);

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

http.Response _status(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// Season page of the first recorded season, built from the show page row so ids and numbers stay real.
Map<String, dynamic> _seasonPage() {
  final row = (_json('show')['collections'] as List).first as Map<String, dynamic>;
  return {
    'item': row['item'],
    'collections': [
      {'type': 'playlist_video', 'label': 'Les émissions', 'items': row['items']},
    ],
  };
}

/// A programme page that lists its episodes in one flat row, as a daily series does.
Map<String, dynamic> _flatPage(List<Map<String, dynamic>> episodes) {
  final page = _json('season');
  (page['item'] as Map<String, dynamic>)['label'] = 'Un si grand soleil';
  (page['collections'] as List).first['items'] = episodes;
  return page;
}

List<Map<String, dynamic>> _flatEpisodes() {
  final items = (_json('season')['collections'] as List).first['items'] as List;
  return [for (final item in items) Map<String, dynamic>.from(item as Map)];
}

Map<String, dynamic> _episode(Map<String, dynamic> base, String streamId, {Object? season, Object? episode}) => {
  ...base,
  'id': streamId.hashCode.abs(),
  'si_id': streamId,
  'season': season,
  'episode': episode,
  'episode_title': null,
};

class _Backend {
  final List<Uri> requests = [];
  Map<String, dynamic> flatPage = _flatPage(_flatEpisodes());

  http.Response handle(http.Request request) {
    requests.add(request.url);
    final path = request.url.path;
    return switch (request.url.host) {
      'k7.ftven.fr' => _stream(path.split('/').last),
      'hdfauth.ftven.fr' => _ok(_json('token_response')),
      'api-front.yatta.francetv.fr' =>
        path.endsWith('/8284344') ? _ok(_json('api_front_content')) : http.Response('{}', 404),
      _ => _catalogue(path, request.url.queryParameters),
    };
  }

  http.Response _stream(String id) {
    if (id.startsWith('blocked')) return _status(422, _json('stream_geoblocked_2009'));
    return switch (id) {
      'ok-hls' => _ok(_json('stream_ok_web_hls')),
      'ok-dash' => _ok(_json('stream_ok_countrycode_be')),
      'ok-france' => _ok(_json('stream_ok_france_zone')),
      _geoBlockedId => _status(422, _json('stream_geoblocked_2009')),
      'gone' => _status(422, _json('stream_unavailable_2003')),
      'refused' => _status(422, _json('stream_unavailable_2013')),
      'protected' => _ok(_withDrm(_json('stream_ok_web_hls'))),
      'limited' => http.Response('slow down', 429, headers: {'retry-after': '30'}),
      _ => http.Response('{}', 404),
    };
  }

  http.Response _catalogue(String path, Map<String, String> query) {
    if (path == '/generic/homepage') return _ok(_json('home'));
    if (path == '/apps/categories/series-et-fictions') return _ok(_json('subcategory'));
    if (path == '/apps/categories/films') return _ok(_json('category'));
    if (path == '/apps/categories/sport') return http.Response('slow down', 429, headers: {'retry-after': '12'});
    if (path.endsWith('/programs')) return _ok(query['page'] == '0' ? _json('programs_list_page0') : {'items': []});
    if (path == '/apps/search') return _ok(_searchPage(query['term'] ?? ''));
    if (path == '/apps/program/meta/$_showPath') return _ok(_json('program_meta_series'));
    if (path == '/apps/program/$_showPath') return _ok(_json('show'));
    if (path == '/apps/program/$_seasonPath') return _ok(_seasonPage());
    if (path == '/apps/program/$_flatPath') return _ok(flatPage);
    return http.Response('{}', 404);
  }
}

Map<String, dynamic> _withDrm(Map<String, dynamic> body) {
  (body['video'] as Map<String, dynamic>)['drm'] = true;
  return body;
}

/// The recorded search page plus a programme and a video appended after the loosely ranked results.
Map<String, dynamic> _searchPage(String term) {
  if (term == 'zzzz') return {'label': term, 'collections': []};
  final page = _json('search');
  final programme = (_json('show')['item'] as Map<String, dynamic>);
  (page['collections'] as List)
    ..add({
      'type': 'playlist_program',
      'label': 'Programmes',
      'items': [programme],
    })
    ..add({
      'type': 'playlist_video',
      'label': 'Vidéos',
      'items': [_flatEpisodes().first],
    });
  return page;
}

({FranceTvProvider provider, _Backend backend}) _build({String countryCode = 'BE', DateTime? now}) {
  final backend = _Backend();
  final client = MediaServerHttpClient(client: MockClient((r) async => backend.handle(r)));
  final api = FranceTvApi(client, countryCode: countryCode, requestGap: Duration.zero);
  final provider = FranceTvProvider.withApi(api, clock: () => now ?? _now, batchDelay: Duration.zero);
  return (provider: provider, backend: backend);
}

/// A provider whose flat programme page lists [episodes].
({FranceTvProvider provider, _Backend backend}) _buildFlat(List<Map<String, dynamic>> episodes) {
  final built = _build();
  built.backend.flatPage = _flatPage(episodes);
  return built;
}

ReplayRef _ref(String nativeId) => ReplayRef('francetv', nativeId);

void main() {
  group('FranceTvProvider browsing', () {
    test('the source is partial and French', () {
      final source = _build().provider.source;
      expect(source.id, 'francetv');
      expect(source.name, 'France.tv');
      expect(source.language, 'fr');
      expect(source.support, ReplayPlaybackSupport.partial);
    });

    test('there are nine categories', () async {
      final categories = await _build().provider.categories();
      expect(categories, hasLength(9));
      expect(categories.first.id, 'series-et-fictions');
    });

    test('home keeps hero programmes and drops personalised rows', () async {
      final rails = await _build().provider.home();
      expect(rails, hasLength(1));
      expect(rails.single.title, 'Notre sélection');
      expect(rails.single.titles.every((t) => t.kind == ReplayKind.show && t.ref.source == 'francetv'), isTrue);
    });

    test('a category drops collections and lists each programme once', () async {
      final rails = await _build().provider.category('series-et-fictions');
      final all = rails.expand((r) => r.titles).toList();
      expect(all, isNotEmpty);
      expect(all.every((t) => t.kind == ReplayKind.show), isTrue);
      expect(all.map((t) => t.ref).toSet(), hasLength(all.length));
      final programmes = rails.firstWhere((r) => r.title == 'Tous les programmes');
      expect(programmes.moreBrowseId, 'series-et-fictions');
    });

    test('a category keeps movies, shows and drops the live row', () async {
      final rails = await _build().provider.category('films');
      expect(rails.map((r) => r.title), ['Notre sélection']);
      final titles = rails.single.titles;
      expect(titles.map((t) => t.kind), [ReplayKind.movie, ReplayKind.show]);
      expect(titles.first.title, 'Harceleurs');
      expect(titles.first.durationSeconds, 5378);
      expect(titles.first.contentRating, 'TP');
      expect(await _build().provider.category('not-a-category'), isEmpty);
    });

    test('a browse call that hits the rate limit throws with the delay', () async {
      await expectLater(
        _build().provider.category('sport'),
        throwsA(
          isA<FranceTvRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 12)),
        ),
      );
    });

    test('listing one category pages by twenty and reports the end', () async {
      final provider = _build().provider;
      final page = await provider.listing('series-et-fictions');
      expect(page.titles.length, 3);
      expect(page.totalCount, 3);
      expect((await provider.listing('series-et-fictions', page: 1)).titles, isEmpty);
    });

    test('listing the whole catalogue walks the categories in order', () async {
      final provider = _build().provider;
      final first = await provider.listing(replayAllBrowseId);
      expect(first.titles, isNotEmpty);
      expect(first.totalCount, greaterThan(20));
      final last = await provider.listing(replayAllBrowseId, page: 1);
      expect(last.totalCount, 9 * 3);
      expect(last.titles, isNotEmpty);
    });
  });

  group('FranceTvProvider search', () {
    test('an exact programme name is ranked first', () async {
      final titles = await _build().provider.search('dix pour cent');
      expect(titles.first.title.toLowerCase(), 'dix pour cent');
      expect(titles.first.ref, _ref('show/$_showPath'));
    });

    test('collections and events are left out, videos are kept', () async {
      final titles = await _build().provider.search('dix pour cent');
      expect(titles.map((t) => t.kind), containsAll([ReplayKind.show, ReplayKind.episode]));
      expect(titles.map((t) => t.title), isNot(contains('Tour de France')));
      expect(titles.map((t) => t.title), isNot(contains('Okoo pour les petits')));
    });

    test('an empty query or no result gives nothing', () async {
      final provider = _build().provider;
      expect(await provider.search('   '), isEmpty);
      expect(await provider.search('zzzz'), isEmpty);
    });
  });

  group('FranceTvProvider shows', () {
    test('a show lists its seasons in order with episode counts', () async {
      final seasons = await _build().provider.children(_ref('show/$_showPath'));
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.map((s) => s.title), ['Saison 1', 'Saison 2']);
      expect(seasons.map((s) => s.childCount), [6, 6]);
      expect(seasons.first.ref, _ref('season/$_showPath/$_seasonPath'));
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('show/$_showPath')), isTrue);
    });

    test('a season lists its episodes with numbers and parents', () async {
      final provider = _build().provider;
      final season = (await provider.children(_ref('show/$_showPath'))).first;
      final episodes = await provider.children(season.ref);
      expect(episodes, hasLength(1));
      final episode = episodes.single;
      expect(episode.kind, ReplayKind.episode);
      expect(episode.title, 'Cécile');
      expect([episode.seasonNumber, episode.episodeNumber], [1, 1]);
      expect(episode.seasonRef, season.ref);
      expect(episode.showRef, _ref('show/$_showPath'));
      expect(episode.showTitle, 'Dix pour Cent');
      expect(episode.summary, isNot(contains('<')));
      expect(episode.durationSeconds, 3297);
    });

    test('a show without season rows has one synthetic season', () async {
      final provider = _build().provider;
      final seasons = await provider.children(_ref('show/$_flatPath'));
      expect(seasons, hasLength(1));
      expect(seasons.single.ref, _ref('season/$_flatPath/_all'));
      expect(seasons.single.title, 'Un si grand soleil');
      expect(seasons.single.childCount, 2);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [2014, 2015]);
      expect(episodes.map((e) => e.seasonNumber), [1, 1]);
      expect(episodes.first.showTitle, 'Un si grand soleil');
    });

    test('episodes that name several seasons are split into seasons', () async {
      final base = _flatEpisodes().first;
      final built = _buildFlat([
        _episode(base, 'a1', season: 1, episode: 2),
        _episode(base, 'a2', season: 1, episode: 1),
        _episode(base, 'b1', season: 2, episode: 1),
      ]);
      final seasons = await built.provider.children(_ref('show/$_flatPath'));
      expect(seasons.map((s) => (s.seasonNumber, s.childCount)), [(1, 2), (2, 1)]);
      final first = await built.provider.children(seasons.first.ref);
      expect(first.map((e) => e.episodeNumber), [1, 2]);
      expect(first.every((e) => e.seasonNumber == 1 && e.seasonRef == seasons.first.ref), isTrue);
    });

    test('episodes with no numbers are listed newest first', () async {
      final base = _flatEpisodes().first;
      final built = _buildFlat([
        {..._episode(base, 'old'), 'broadcast_begin_date': 1000000},
        {..._episode(base, 'new'), 'broadcast_begin_date': 2000000},
      ]);
      final episodes = await built.provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes.map((e) => e.ref.nativeId.split('/')[1]), ['new', 'old']);
      expect(episodes.every((e) => e.episodeNumber == null), isTrue);
    });

    test('a show resolves from its light metadata', () async {
      final show = await _build().provider.title(_ref('show/$_showPath'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Dix pour Cent');
      expect(show.directors, ['Antoine Garceau', 'Marc Fitoussi']);
      expect(show.cast.first, 'Camille Cottin');
      expect(show.genres, ['Séries & fictions']);
    });

    test('a season resolves through its show, a missing one is null', () async {
      final provider = _build().provider;
      final season = await provider.title(_ref('season/$_showPath/$_seasonPath'));
      expect(season!.seasonNumber, 1);
      expect(await provider.title(_ref('season/$_showPath/unknown')), isNull);
      expect(await provider.title(_ref('show/not-found')), isNull);
    });

    test('a video resolves from the content record when not seen in a list', () async {
      final video = await _build().provider.title(_ref('video/39acb0bf-8af8-43ef-bf40-1215e91693da/8284344'));
      expect(video!.title, 'Shaun le film');
      expect(video.kind, ReplayKind.episode);
      expect(video.showTitle, 'Shaun le mouton');
      expect(video.showRef, _ref('show/france-3_shaun-le-mouton'));
      expect(video.year, 2015);
      expect(video.availableUntil, DateTime.utc(2026, 11, 16, 18, 51, 31));
    });

    test('refs of other sources or odd shapes resolve to nothing', () async {
      final provider = _build().provider;
      expect(await provider.title(ReplayRef('arte', 'show/x')), isNull);
      expect(await provider.children(_ref('show/../etc')), isEmpty);
      expect(await provider.children(_ref('video/abc')), isEmpty);
    });
  });

  group('FranceTvProvider availability in lists', () {
    test('episodes past their end date are expired', () async {
      final provider = _build(now: DateTime.utc(2026, 10, 22)).provider;
      final episodes = await provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes.map((e) => e.availability), everyElement(ReplayAvailability.expired));
    });

    test('episodes before their start date are upcoming', () async {
      final provider = _build(now: DateTime.utc(2026, 9, 1)).provider;
      final episodes = await provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes.map((e) => e.availability), everyElement(ReplayAvailability.upcoming));
    });

    test('a geoblocked sample marks the whole season as blocked', () async {
      final base = _flatEpisodes().first;
      final built = _buildFlat([for (var i = 0; i < 5; i++) _episode(base, 'blocked-$i', episode: i + 1)]);
      final episodes = await built.provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes, hasLength(5));
      expect(episodes.map((e) => e.availability), everyElement(ReplayAvailability.geoBlocked));
      expect(built.backend.requests.where((u) => u.host == 'k7.ftven.fr'), hasLength(3));
    });

    test('a playable sample leaves the others playable', () async {
      final base = _flatEpisodes().first;
      final built = _buildFlat([
        _episode(base, 'ok-hls', episode: 1),
        _episode(base, 'blocked-1', episode: 2),
        _episode(base, 'blocked-2', episode: 3),
        _episode(base, 'blocked-3', episode: 4),
      ]);
      final episodes = await built.provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes.map((e) => e.availability), [
        ReplayAvailability.playable,
        ReplayAvailability.geoBlocked,
        ReplayAvailability.geoBlocked,
        ReplayAvailability.playable,
      ]);
    });

    test('a verdict learned at playback is reused without asking again', () async {
      final built = _build();
      await built.provider.playback(_ref('video/$_geoBlockedId'));
      final episodes = await built.provider.children(_ref('season/$_showPath/$_seasonPath'));
      expect(episodes.single.availability, ReplayAvailability.geoBlocked);
      expect(built.backend.requests.where((u) => u.host == 'k7.ftven.fr'), hasLength(1));
    });

    test('a season of a geoblocked show is flagged from one real answer', () async {
      final episodes = await _build().provider.children(_ref('season/$_showPath/$_seasonPath'));
      expect(episodes.single.availability, ReplayAvailability.geoBlocked);
    });
  });

  group('FranceTvProvider playback', () {
    test('a clear stream is signed and carries captions', () async {
      final playback = await _build().provider.playback(_ref('video/ok-hls'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'cloudreplay.ftven.fr');
      expect(playback.streams.single.url.path, endsWith('.mpd'));
      expect(playback.subtitles.single.languageCode, 'fr');
      expect(playback.subtitles.single.label, contains('sourds'));
      expect(playback.subtitles.single.url.host, 'assets.webservices.francetelevisions.fr');
    });

    test('closing credits become a skip marker', () async {
      final playback = await _build(countryCode: 'FR').provider.playback(_ref('video/ok-france'));
      expect(playback.isPlayable, isTrue);
      expect(playback.credits!.start, const Duration(milliseconds: 3251857));
      expect(playback.credits!.end, const Duration(seconds: 3297));
    });

    test('the manifest address is passed to the token service', () async {
      final built = _build();
      await built.provider.playback(_ref('video/ok-dash'));
      final token = built.backend.requests.firstWhere((u) => u.host == 'hdfauth.ftven.fr');
      expect(token.queryParameters['format'], 'json');
      expect(token.queryParameters['url'], endsWith('_monde_TA.ism/manifest.mpd'));
    });

    test('the viewer country is always sent with the stream request', () async {
      final built = _build();
      await built.provider.playback(_ref('video/ok-hls'));
      final k7 = built.backend.requests.firstWhere((u) => u.host == 'k7.ftven.fr');
      expect(k7.queryParameters['country_code'], 'BE');
      expect(k7.queryParameters['domain'], 'www.france.tv');
    });

    test('another country is sent as given, in upper case', () async {
      final built = _build(countryCode: 'fr');
      await built.provider.playback(_ref('video/ok-hls'));
      expect(built.backend.requests.firstWhere((u) => u.host == 'k7.ftven.fr').queryParameters['country_code'], 'FR');
    });

    test('a malformed country code is rejected at construction', () {
      final client = MediaServerHttpClient(client: MockClient((r) async => http.Response('{}', 404)));
      expect(() => FranceTvProvider(client, countryCode: 'BEL'), throwsArgumentError);
      expect(() => FranceTvProvider(client, countryCode: ''), throwsArgumentError);
    });

    test('a geoblocked video says so in the broadcaster words', () async {
      final playback = await _build().provider.playback(_ref('video/$_geoBlockedId'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('Belgique'));
    });

    test('an expired video is reported as expired', () async {
      final playback = await _build().provider.playback(_ref('video/gone'));
      expect(playback.availability, ReplayAvailability.expired);
      expect(playback.message, contains('plus disponible'));
    });

    test('an unlisted refusal code is unknown with its message', () async {
      final playback = await _build().provider.playback(_ref('video/refused'));
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.message, contains('impossible'));
    });

    test('a protected stream is refused before any token is fetched', () async {
      final built = _build();
      final playback = await built.provider.playback(_ref('video/protected'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(built.backend.requests.where((u) => u.host == 'hdfauth.ftven.fr'), isEmpty);
    });

    test('an unknown video is reported as expired, not as an error', () async {
      expect((await _build().provider.playback(_ref('video/nothing'))).availability, ReplayAvailability.expired);
    });

    test('rate limiting is reported without throwing', () async {
      final playback = await _build().provider.playback(_ref('video/limited'));
      expect(playback.isPlayable, isFalse);
      expect(playback.message, contains('30'));
    });

    test('a show is never played directly', () async {
      expect((await _build().provider.playback(_ref('show/$_showPath'))).isPlayable, isFalse);
    });
  });

  group('FranceTv artwork', () {
    test('shows get a portrait poster and a landscape backdrop', () async {
      final show = (await _build().provider.home()).first.titles.first;
      expect(show.posterUrl, contains('/800x1066/'));
      expect(show.backdropUrl, contains('/800x450/'));
      expect(show.posterUrl!.split('|'), hasLength(3));
    });

    test('episodes use the landscape picture for both', () async {
      final episode = (await _build().provider.children(_ref('season/$_showPath/$_seasonPath'))).single;
      expect(episode.posterUrl, episode.backdropUrl);
    });

    test('the closest listed width that covers the box is chosen', () async {
      final provider = _build().provider;
      final reference = (await provider.home()).first.titles.first.backdropUrl!;
      expect(provider.imageUrl(reference, width: 300), contains('/400x0/'));
      expect(provider.imageUrl(reference, width: 800), contains('/800x450/'));
      expect(provider.imageUrl(reference, width: 900), contains('/1024x576/'));
      expect(provider.imageUrl(reference, width: 5000), contains('/2500x1406/'));
      expect(provider.imageUrl(reference), contains('/800x450/'));
    });

    test('only this provider claims its pictures', () async {
      final provider = _build().provider;
      final reference = (await provider.home()).first.titles.first.posterUrl!;
      expect(provider.ownsImage(reference), isTrue);
      expect(provider.ownsImage('https://api-cdn.arte.tv/img/v2/image/abc/__SIZE__'), isFalse);
      expect(franceTvImageReference(const [], const ['logo']), isNull);
      expect(franceTvImageReference(null, const ['logo']), isNull);
    });
  });

  group('FranceTv numbering', () {
    test('structured fields win over the text', () {
      final numbers = franceTvNumbers({
        'season': 8,
        'episode': 2038,
        'episode_title': 'S1 E1 - x',
        'title': 'Épisode 5',
      });
      expect(numbers, (season: 8, episode: 2038));
    });

    test('the S and E prefix of the episode title is read', () {
      expect(franceTvNumbers({'episode_title': 'S3 E12 - Une fin', 'title': 'Une fin'}), (season: 3, episode: 12));
    });

    test('an episode word in the title gives the episode number', () {
      expect(franceTvNumbers({'title': 'Épisode 7'}).episode, 7);
      expect(franceTvNumbers({'title': 'Julien : 3ème épisode'}).episode, 3);
      expect(franceTvNumbers({'title': 'Le retour - Ep. 12'}).episode, 12);
      expect(franceTvNumbers({'title': 'Saison 2, épisode 4'}), (season: 2, episode: 4));
    });

    test('a date in the title is not an episode number', () {
      final numbers = franceTvNumbers({'title': 'Épisode du lundi 21 septembre 2026'});
      expect(numbers, (season: null, episode: null));
    });

    test('zero and absent numbers stay unknown', () {
      expect(franceTvNumbers({'season': 1, 'episode': 0, 'title': 'Partie 1'}), (season: 1, episode: null));
      expect(franceTvNumbers(const {}), (season: null, episode: null));
    });

    test('numbers read from the title reach the listed episode', () async {
      final base = _flatEpisodes().first;
      final built = _buildFlat([
        {..._episode(base, 'x2'), 'title': 'La suite - épisode 2'},
        {..._episode(base, 'x1'), 'title': 'Le début - épisode 1'},
      ]);
      final episodes = await built.provider.children(_ref('season/$_flatPath/_all'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2]);
    });
  });

  test('a native id with slashes survives a ref round trip', () {
    final ref = ReplayRef.tryParse('francetv:season/$_showPath/$_seasonPath');
    expect(ref, _ref('season/$_showPath/$_seasonPath'));
    expect(ReplayRef.tryParse(ref.toString()), ref);
  });
}
