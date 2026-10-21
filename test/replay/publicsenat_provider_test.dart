import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/dailymotion/dailymotion_resolver.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_api.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_catalog.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_provider.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _fixtures = 'test/replay/fixtures/publicsenat';

String _fixture(String name) => File('$_fixtures/$name').readAsStringSync();

http.Response _html(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'text/html; charset=utf-8'});

http.Response _json(String body) =>
    http.Response.bytes(utf8.encode(body), 200, headers: {'content-type': 'application/json'});

/// One minimal episode card, enough for the parser; used where a fixture would need hundreds of them.
String _card(String slug, int n, DateTime date) {
  final id = 'k${n.toString().padLeft(18, '0')}';
  final day = date.toIso8601String().substring(0, 10);
  return '<article class="group"><picture thumb="https://www.dailymotion.com/thumbnail/video/$id">'
      '<span> 26mn </span></picture><p><span>Theme</span> | Le <time datetime="$day">d</time></p>'
      '<a href="https://www.publicsenat.fr/emission/$slug/episode-$n-e$n" title="Episode $n">Episode $n</a></article>';
}

/// A video every four days going back from the end of June, so a long programme crosses a season boundary.
DateTime _longDate(int index) => DateTime.utc(2026, 6, 28).subtract(Duration(days: index * 4));

String _longShowPage() =>
    '''
<html><head><title>Long show</title></head><body>
<script>ajaxObject = {"url":"x","nonce":"n","action":"replays"};</script>
<section data-module="Program" data-term-id="9" data-limit="12" data-paged="1" data-total="50">
<div data-program-grid>${[for (var i = 0; i < 12; i++) _card('long', i, _longDate(i))].join()}</div>
</section></body></html>''';

class _Site {
  final requests = <http.Request>[];
  int ajaxCalls = 0;

  http.Response handle(http.Request request) {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'POST') return _ajax(request);
    return switch (path) {
      '/emissions' => _html(_fixture('programmes.html')),
      '/replay' => _html(_fixture('replay.html')),
      '/emission/1000-pays-pour-demain' => _html(_fixture('show_numbered.html')),
      '/emission/documentaire' => _html(_fixture('show_unnumbered.html')),
      '/emission/a-vrai-dire' => _html(_fixture('show_single.html')),
      '/emission/cap-sur-lelysee' => _html(_fixture('show_without_episodes.html')),
      '/emission/long' => _html(_longShowPage()),
      '/emission/limited' => http.Response('slow down', 429, headers: {'retry-after': '30'}),
      _ => http.Response('not found', 404),
    };
  }

  http.Response _ajax(http.Request request) {
    ajaxCalls++;
    final form = request.bodyFields;
    final page = int.parse(form['paged']!);
    if (form['termID'] == '9') {
      final cards = [for (var i = 0; i < 12; i++) _card('long', (page - 1) * 12 + i, _longDate((page - 1) * 12 + i))];
      return _json(
        jsonEncode({
          'success': true,
          'data': {'template': cards.join()},
        }),
      );
    }
    return switch ((form['termID'], page)) {
      ('1338', 2) => _json(_fixture('more_numbered.json')),
      ('237', 2) => _json(_fixture('more_unnumbered.json')),
      _ => _json(_fixture('more_empty.json')),
    };
  }
}

ReplayProvider _provider(_Site site, {DailymotionResolver? resolver}) {
  final client = MediaServerHttpClient(client: MockClient((r) async => site.handle(r)));
  return PublicSenatProvider.withApi(PublicSenatApi(client, minInterval: Duration.zero), resolver: resolver);
}

ReplayRef _ref(String id) => ReplayRef('publicsenat', id);

void main() {
  group('PublicSenatProvider browsing', () {
    test('the source is described as French and browse-only without a resolver', () {
      final source = _provider(_Site()).source;
      expect(source.id, 'publicsenat');
      expect(source.name, 'Public Sénat');
      expect(source.language, 'fr');
      expect(source.support, ReplayPlaybackSupport.browseOnly);
    });

    test('home has the newest videos and the programmes', () async {
      final rails = await _provider(_Site()).home();
      expect(rails.map((r) => r.id), ['replays', 'programmes']);
      expect(rails.first.titles, hasLength(5));
      expect(rails.first.moreBrowseId, 'replays');
      expect(rails.last.titles, hasLength(8));
      expect(rails.last.moreBrowseId, isNull);
    });

    test('programmes are shows with absolute posters and decoded names', () async {
      final shows = (await _provider(_Site()).home()).last.titles;
      expect(shows.every((t) => t.kind == ReplayKind.show && t.ref.source == 'publicsenat'), isTrue);
      expect(shows.map((t) => t.title), containsAll(['100% Sénat', "Cap sur l'Élysée", 'À vrai dire']));
      expect(shows.every((t) => t.posterUrl!.startsWith('https://www.publicsenat.fr/app/uploads/')), isTrue);
    });

    test('the logo variant of a cover is not listed twice', () async {
      final shows = (await _provider(_Site()).home()).last.titles;
      expect(shows.where((t) => t.ref.nativeId == 'documentaire'), hasLength(1));
    });

    test('newest videos carry show, theme, duration and date', () async {
      final latest = (await _provider(_Site()).home()).first.titles;
      final first = latest.first;
      expect(first.kind, ReplayKind.episode);
      expect(first.title, "Mouvements sociaux : d'où vient la colère ?");
      expect(first.showTitle, 'Sens Public');
      expect(first.showRef, _ref('sens-public'));
      expect(first.durationSeconds, 42 * 60);
      expect(first.airDate, DateTime.utc(2026, 10, 20));
      expect(first.seasonNumber, 2026);
      expect(first.availability, ReplayAvailability.playable);
    });

    test('categories open the three sections', () async {
      final provider = _provider(_Site());
      expect((await provider.categories()).map((c) => c.id), ['replays', 'programmes', 'documentaires']);
      expect((await provider.category('programmes')).single.titles, hasLength(8));
      expect((await provider.category('documentaires')).single.titles, hasLength(18));
      expect(await provider.category('nope'), isEmpty);
    });

    test('the whole-catalogue listing pages through programmes', () async {
      final provider = _provider(_Site());
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 8);
      expect(first.titles, hasLength(8));
      expect((await provider.listing(replayAllBrowseId, page: 1)).titles, isEmpty);
    });

    test('the documentary listing pages through loaded episodes', () async {
      final provider = _provider(_Site());
      final first = await provider.listing('documentaires');
      expect(first.totalCount, 18);
      expect(first.titles, hasLength(12));
      expect((await provider.listing('documentaires', page: 1)).titles, hasLength(6));
    });

    test('search matches programmes and recent videos without accents', () async {
      final provider = _provider(_Site());
      final senat = await provider.search('senat');
      expect(senat.first.kind, ReplayKind.show);
      expect(senat.first.title, '100% Sénat');
      final episodes = await provider.search('mouvements sociaux');
      expect(episodes.map((t) => t.kind), [ReplayKind.episode]);
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
    });
  });

  group('PublicSenatProvider shows', () {
    test('a numbered programme splits into broadcast seasons', () async {
      final seasons = await _provider(_Site()).children(_ref('1000-pays-pour-demain'));
      expect(seasons.map((s) => s.seasonNumber), [2023, 2024, 2025]);
      expect(seasons.map((s) => s.title), ['Saison 2023-2024', 'Saison 2024-2025', 'Saison 2025-2026']);
      expect(seasons.map((s) => s.childCount), [6, 5, 5]);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _ref('1000-pays-pour-demain')), isTrue);
    });

    test('episodes are numbered by place in the season, oldest first', () async {
      final provider = _provider(_Site());
      final episodes = await provider.children(_ref('1000-pays-pour-demain/s2023'));
      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4, 5, 6]);
      expect(episodes.first.title, 'En Loire-Atlantique avec Ronan Dantec');
      expect(episodes.first.airDate, DateTime.utc(2024, 2, 9));
      expect(episodes.first.seasonNumber, 2023);
      expect(episodes.first.seasonRef, _ref('1000-pays-pour-demain/s2023'));
      expect(episodes.first.showTitle, '1000 pays pour demain');
      expect(episodes.first.ref.nativeId, '1000-pays-pour-demain/k2Wai0SKsnbI3yzVm9m');
    });

    test('a September episode starts the next season, not the previous one', () async {
      final episodes = await _provider(_Site()).children(_ref('1000-pays-pour-demain/s2025'));
      expect(episodes.first.airDate, DateTime.utc(2025, 9, 12));
      expect(episodes.first.episodeNumber, 1);
      expect(episodes.last.airDate, DateTime.utc(2026, 6, 19));
    });

    test('later pages come from the load-more call with the page nonce', () async {
      final site = _Site();
      await _provider(site).children(_ref('1000-pays-pour-demain'));
      final post = site.requests.singleWhere((r) => r.method == 'POST');
      expect(post.url.path, '/wp/wp-admin/admin-ajax.php');
      expect(post.bodyFields, {
        'action': 'replays',
        'security': 'fixturenonce',
        'termID': '1338',
        'limit': '12',
        'paged': '2',
        'order': 'desc',
        'total': '16',
      });
    });

    test('every request identifies the app', () async {
      final site = _Site();
      await _provider(site).children(_ref('1000-pays-pour-demain'));
      expect(site.requests, isNotEmpty);
      for (final request in site.requests) {
        expect(request.headers['User-Agent'], 'Plezy-Replay (+https://github.com/silkyclouds/plezy)');
      }
    });

    test('a programme of standalone documentaries has seasons without numbers', () async {
      final provider = _provider(_Site());
      final seasons = await provider.children(_ref('documentaire'));
      expect(seasons.map((s) => s.seasonNumber), [2024, 2026]);
      expect(seasons.map((s) => s.childCount), [1, 17]);
      final episodes = await provider.children(seasons.last.ref);
      expect(episodes, hasLength(17));
      expect(episodes.every((e) => e.episodeNumber == null), isTrue);
      expect(episodes.first.title, "Dans l'ombre de Berlusconi");
      expect(episodes.first.durationSeconds, 72 * 60);
      expect(episodes.first.genres, ['Société']);
    });

    test('a programme with one video has one season with episode one', () async {
      final provider = _provider(_Site());
      final seasons = await provider.children(_ref('a-vrai-dire'));
      expect(seasons.single.seasonNumber, 2026);
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.single.episodeNumber, 1);
      expect(episodes.single.durationSeconds, 29 * 60);
      expect(episodes.single.genres, ['International']);
    });

    test('a programme page without its own episodes has no children', () async {
      final provider = _provider(_Site());
      expect(await provider.children(_ref('cap-sur-lelysee')), isEmpty);
      final show = await provider.title(_ref('cap-sur-lelysee'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, "Cap sur l'Élysée");
    });

    test('an unknown programme has no title and no children', () async {
      final provider = _provider(_Site());
      expect(await provider.title(_ref('nope')), isNull);
      expect(await provider.children(_ref('nope')), isEmpty);
      expect(await provider.title(_ref('a-vrai-dire/not-a-video-id')), isNull);
    });

    test('title reads the programme summary and wide image from its page', () async {
      final show = await _provider(_Site()).title(_ref('a-vrai-dire'));
      expect(show!.kind, ReplayKind.show);
      expect(show.summary, contains('vérification des faits'));
      expect(show.summary, contains('"À vrai dire"'));
      expect(show.backdropUrl, startsWith('https://www.publicsenat.fr/app/uploads/'));
      expect(show.posterUrl, startsWith('https://www.publicsenat.fr/app/uploads/'));
    });

    test('title resolves seasons and episodes through their parents', () async {
      final provider = _provider(_Site());
      final season = await provider.title(_ref('1000-pays-pour-demain/s2024'));
      expect(season!.kind, ReplayKind.season);
      expect(season.childCount, 5);
      final episode = await provider.title(_ref('1000-pays-pour-demain/kMWXCr0hpRdLZnDf8Ji'));
      expect(episode!.title, 'Dans le Calvados, avec Sonia de La Provôté');
      expect(episode.seasonNumber, 2024);
      expect(episode.episodeNumber, 5);
      expect(await provider.title(_ref('1000-pays-pour-demain/s1999')), isNull);
      expect(await provider.title(_ref('1000-pays-pour-demain/kdoesnotexist12345')), isNull);
    });

    test('children of an episode are empty', () async {
      expect(await _provider(_Site()).children(_ref('1000-pays-pour-demain/kMWXCr0hpRdLZnDf8Ji')), isEmpty);
    });
  });

  group('PublicSenatProvider page budget', () {
    test('a long programme stops at the page cap and cuts the oldest season', () async {
      final site = _Site();
      final provider = _provider(site);
      final seasons = await provider.children(_ref('long'));
      expect(site.ajaxCalls, PublicSenatCatalog.maxPages - 1);
      final oldest = await provider.children(seasons.first.ref);
      expect(oldest.every((e) => e.episodeNumber == null), isTrue);
      final newest = await provider.children(seasons.last.ref);
      expect(newest.every((e) => e.episodeNumber != null), isTrue);
    });

    test('a rate-limited page raises the retry delay', () async {
      final provider = _provider(_Site());
      await expectLater(
        provider.children(_ref('limited')),
        throwsA(
          isA<PublicSenatRateLimitedException>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30)),
        ),
      );
    });

    test('requests are spaced by the configured interval', () async {
      final site = _Site();
      final client = MediaServerHttpClient(client: MockClient((r) async => site.handle(r)));
      final api = PublicSenatApi(client, minInterval: const Duration(milliseconds: 60));
      final watch = Stopwatch()..start();
      await Future.wait([api.programmes(), api.replays(), api.show('a-vrai-dire')]);
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });

    test('a failed load is retried on the next call', () async {
      var failures = 1;
      final site = _Site();
      final client = MediaServerHttpClient(
        client: MockClient((r) async {
          if (failures-- > 0) return http.Response('boom', 500);
          return site.handle(r);
        }),
      );
      final provider = PublicSenatProvider.withApi(PublicSenatApi(client, minInterval: Duration.zero));
      await expectLater(provider.home(), throwsA(anything));
      expect((await provider.home()).first.titles, isNotEmpty);
    });
  });

  group('PublicSenatProvider artwork', () {
    test('cover images grow to the full file only when a larger size is asked', () async {
      final provider = _provider(_Site());
      final cover = (await provider.home()).last.titles.firstWhere((t) => t.ref.nativeId == '100-senat').posterUrl!;
      expect(cover, endsWith('-301x450.jpg'));
      expect(provider.imageUrl(cover, width: 200), cover);
      expect(provider.imageUrl(cover, width: 600), cover.replaceFirst('-301x450', ''));
    });

    test('episode images are the large Dailymotion thumbnail', () async {
      final episode = (await _provider(_Site()).home()).first.titles.first;
      expect(episode.backdropUrl, matches(RegExp(r'^https://s\d\.dmcdn\.net/v/[\w-]+/x1080$')));
      expect(episode.posterUrl, episode.backdropUrl);
    });

    test('images are claimed by origin', () {
      final provider = _provider(_Site());
      expect(provider.ownsImage('https://www.publicsenat.fr/app/uploads/2025/09/a-301x450.jpg'), isTrue);
      expect(provider.ownsImage('https://s2.dmcdn.net/v/abc/x1080'), isTrue);
      expect(provider.ownsImage('https://www.dailymotion.com/thumbnail/video/kabc'), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
    });
  });

  group('PublicSenatProvider playback', () {
    Future<ReplayPlayback> play(ReplayProvider provider, String id) => provider.playback(_ref(id));

    test('without a resolver every episode is unavailable with a reason', () async {
      final playback = await play(_provider(_Site()), 'a-vrai-dire/k1xaQB2sFKmBTvLVsym');
      expect(playback.availability, ReplayAvailability.unknown);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('robots.txt'));
    });

    test('a resolver turns the metadata into a clear stream without headers', () async {
      final metadata = jsonDecode(_fixture('player_metadata.json')) as Map<String, dynamic>;
      final asked = <String>[];
      final provider = _provider(
        _Site(),
        resolver: DailymotionResolver((id) async {
          asked.add(id);
          return metadata;
        }),
      );
      expect(provider.source.support, ReplayPlaybackSupport.clear);

      final episodes = await provider.children(_ref('a-vrai-dire/s2026'));
      final playback = await provider.playback(episodes.single.ref);
      expect(asked, ['k1xaQB2sFKmBTvLVsym']);
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'cdndirector.dailymotion.com');
      expect(playback.streams.single.url.path, endsWith('.m3u8'));
      expect(playback.streams.single.headers, isEmpty);
      expect(playback.streams.single.label, 'VF');
    });

    test('a country block is reported with the broadcaster wording', () async {
      final metadata = jsonDecode(_fixture('player_metadata_geoblocked.json')) as Map<String, dynamic>;
      final provider = _provider(_Site(), resolver: DailymotionResolver((_) async => metadata));
      final playback = await play(provider, 'a-vrai-dire/xbkcaqu');
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(playback.message, contains('votre pays'));
    });

    test('a video Dailymotion no longer has is expired', () async {
      final provider = _provider(_Site(), resolver: DailymotionResolver((_) async => null));
      expect((await play(provider, 'a-vrai-dire/xbkcaqu')).availability, ReplayAvailability.expired);
    });

    test('shows, seasons and malformed ids are not playable', () async {
      final provider = _provider(_Site(), resolver: DailymotionResolver((_) async => fail('must not be asked')));
      for (final id in ['a-vrai-dire', 'a-vrai-dire/s2026', 'a-vrai-dire/nope', '']) {
        expect((await play(provider, id)).availability, ReplayAvailability.unknown, reason: id);
      }
    });
  });
}
