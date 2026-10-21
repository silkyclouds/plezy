import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_listing.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_mapper.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_images.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_numbering.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_rights.dart';
import 'package:plezy/replay/providers/rtbf/rtbf_tabs.dart';

import 'rtbf_test_support.dart';

Map<String, dynamic> _publication(
  List<String> products, {
  String from = '2026-01-01T00:00:00Z',
  String to = '2027-01-01T00:00:00Z',
}) => {'products': products, 'fromDate': from, 'toDate': to};

Map<String, dynamic> _asset(List<Map<String, dynamic>> publications) => {'publications': publications};

void main() {
  group('Season and episode numbers', () {
    test('a season suffix and an episode prefix are read', () {
      final n = rtbfParseNumbering(title: 'Ghosts S02', subtitle: '01 - Visite guidée');
      expect((n.showTitle, n.season, n.episode, n.episodeTitle), ('Ghosts', 2, 1, 'Visite guidée'));
    });

    test('a double space before the suffix is collapsed', () {
      final n = rtbfParseNumbering(title: 'Ghosts  S05', subtitle: '03 - Titre');
      expect((n.showTitle, n.season), ('Ghosts', 5));
    });

    test('hyphens inside the title and the episode name are kept', () {
      final n = rtbfParseNumbering(title: 'Les Douze - Meurtres au Botox S03', subtitle: '04 - Un - deux');
      expect((n.showTitle, n.season, n.episodeTitle), ('Les Douze - Meurtres au Botox', 3, 'Un - deux'));
    });

    test('an en dash after the number works too', () {
      expect(rtbfParseNumbering(title: 'X', subtitle: '7 – Retour').episode, 7);
    });

    test('a numbered episode without a season marker has no season', () {
      final n = rtbfParseNumbering(title: 'Les disparus des Argonnes', subtitle: '01 - Episode 1');
      expect((n.season, n.episode), (null, 1));
    });

    test('a subtitle that reads Episode N gives the number and stays whole', () {
      for (final subtitle in ['Episode 4', 'Épisode 4', 'épisode 4 - suite']) {
        final n = rtbfParseNumbering(title: 'True Beauty', subtitle: subtitle);
        expect(n.episode, 4, reason: subtitle);
        expect(n.episodeTitle, subtitle);
      }
    });

    test('a subtitle that only starts with digits is not an episode', () {
      final n = rtbfParseNumbering(title: 'Magazine', subtitle: '10 ans après #MeToo, les violences continuent');
      expect(n.isNumbered, isFalse);
      expect(n.episodeTitle, startsWith('10 ans'));
    });

    test('a title ending in a lone S is left alone', () {
      expect(rtbfParseNumbering(title: 'Tous les S', subtitle: null).season, isNull);
    });

    test('a missing subtitle falls back to the title', () {
      final n = rtbfParseNumbering(title: 'Ghosts S01', subtitle: '');
      expect((n.episodeTitle, n.isNumbered), ('Ghosts S01', true));
    });

    test('nothing at all gives empty text', () {
      final n = rtbfParseNumbering(title: null, subtitle: null);
      expect((n.showTitle, n.episodeTitle, n.isNumbered), ('', '', false));
    });
  });

  group('Tabs', () {
    test('the context in the URL decides season, year or single bucket', () {
      final tabs = rtbfParseTabs({
        'data': {
          'content': [
            {
              'title': 'Saison 1',
              'subtitle': '6 épisodes',
              'contentPath': 'https://x/widgets/1?context%5BprogramId%5D=1&context%5Bseason%5D=1',
              'season': 1,
            },
            {
              'title': 'Année 2026',
              'subtitle': '5 épisodes',
              'contentPath': 'https://x/widgets/1?context%5BprogramId%5D=1&context%5Byear%5D=2026',
              'season': 2026,
            },
            {
              'title': 'Tous les épisodes',
              'subtitle': '12 épisodes',
              'contentPath': 'https://x/widgets/1?context%5BprogramId%5D=1',
              'season': null,
            },
          ],
        },
      });
      expect(tabs.map((t) => t.key), ['s1', 'y2026', 'all']);
      expect(tabs.map((t) => t.number), [1, 2026, null]);
      expect(tabs.map((t) => t.count), [6, 5, 12]);
    });

    test('a tab without a content path is skipped', () {
      expect(
        rtbfParseTabs({
          'data': {
            'content': [
              {'title': 'Saison 1'},
            ],
          },
        }),
        isEmpty,
      );
    });
  });

  group('Rights from the asset record', () {
    final now = DateTime.utc(2026, 10, 21);

    test('the anonymous product is open to everyone', () {
      final asset = _asset([
        _publication(['free_product_6BA97Bb', 'anonymous_product_6BA97Bb']),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.playable);
    });

    test('the free product alone needs an account', () {
      final asset = _asset([
        _publication(['free_product_6BA97Bb']),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.loginRequired);
    });

    test('the paid offer needs an account', () {
      final asset = _asset([
        _publication(['sooner_6BA97Bb']),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.loginRequired);
    });

    test('technical access does not count as a publication', () {
      final asset = _asset([
        _publication(['technical-access_6BA97Bb']),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.unknown);
    });

    test('a publication that ended is expired', () {
      final asset = _asset([
        _publication(['anonymous_product_6BA97Bb'], to: '2026-10-01T00:00:00Z'),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.expired);
    });

    test('a publication that has not started is upcoming', () {
      final asset = _asset([
        _publication(['anonymous_product_6BA97Bb'], from: '2026-11-01T00:00:00Z'),
      ]);
      expect(rtbfAvailabilityFromAsset(asset, now), ReplayAvailability.upcoming);
    });

    test('an unknown asset is expired', () {
      expect(rtbfAvailabilityFromAsset(null, now), ReplayAvailability.expired);
    });

    test('the recorded records give open and account-only verdicts', () {
      expect(rtbfAvailabilityFromAsset(rtbfJson('redbee_asset_anonymous'), now), ReplayAvailability.playable);
      expect(rtbfAvailabilityFromAsset(rtbfJson('redbee_asset_login_required'), now), ReplayAvailability.loginRequired);
    });
  });

  group('Availability in lists', () {
    test('a card past its window is expired and a future one upcoming', () async {
      final late = await rtbfProvider(now: DateTime.utc(2027, 3, 1)).children(rtbfRef('p32284/s2'));
      expect(late.every((e) => e.availability == ReplayAvailability.expired), isTrue);
      final early = await rtbfProvider(now: DateTime.utc(2026, 10, 1)).children(rtbfRef('p32284/s2'));
      expect(early.every((e) => e.availability == ReplayAvailability.upcoming), isTrue);
    });

    test('only the first thirty episodes of a list are looked up', () async {
      final log = <http.Request>[];
      final cards = [
        for (var i = 0; i < 40; i++)
          {
            ...(rtbfJson('widget_media_list')['data'] as Map)['content'][0] as Map,
            'id': '${3516000 + i}',
            'subtitle': '${i + 1} - Titre',
          },
      ];
      final provider = rtbfProvider(
        log: log,
        handler: (request) => request.url.path.endsWith('/widgets/18800')
            ? rtbfReply({
                'data': {'content': cards},
                'links': {'next': null},
              })
            : null,
      );
      final episodes = await provider.children(rtbfRef('p32284/s2'));
      expect(episodes, hasLength(40));
      expect(log.where((r) => r.url.path.contains('/content/asset/')), hasLength(rtbfPredictionLimit));
    });

    test('a failing rights lookup leaves the verdict out instead of failing the list', () async {
      final provider = rtbfProvider(
        handler: (request) => request.url.path.contains('/content/asset/') ? http.Response('', 503) : null,
      );
      final episodes = await provider.children(rtbfRef('p32284/s2'));
      expect(episodes, hasLength(3));
      expect(episodes.every((e) => e.availability == ReplayAvailability.playable), isTrue);
    });
  });

  group('Listing pages', () {
    RtbfListing listing(List<http.Request> log) {
      final api = rtbfApi(log: log);
      return RtbfListing(api.bff, RtbfMapper(() => rtbfNow), () => rtbfNow);
    }

    test('pages stay aligned when audio is dropped from server pages', () async {
      final listings = listing([]);
      final pages = [for (var i = 0; i < 3; i++) await listings.page(replayAllBrowseId, i, 4)];
      expect(pages.map((p) => p.titles.length), [4, 4, 2]);
      expect({for (final p in pages) ...p.titles.map((t) => t.ref)}, hasLength(10));
      expect(pages.first.totalCount, 8398);
      expect(pages.last.totalCount, 10);
    });

    test('two requests at once read each server page once', () async {
      final log = <http.Request>[];
      final listings = listing(log);
      await Future.wait([listings.page(replayAllBrowseId, 0, 4), listings.page(replayAllBrowseId, 1, 4)]);
      expect(log.where((r) => r.url.path.endsWith('/mosaic/program')), hasLength(2));
    });
  });

  group('Home requests', () {
    test('promotions, paid rows and login rows are never fetched', () async {
      final log = <http.Request>[];
      await rtbfProvider(log: log).home();
      final paths = log.map((r) => r.url.toString()).join('\n');
      expect(paths, isNot(contains('u2c-service')));
      expect(paths, isNot(contains('/widgets/19010')));
      expect(paths, isNot(contains('/widgets/19737')));
    });

    test('at most twelve rows are fetched for one page', () async {
      final log = <http.Request>[];
      await rtbfProvider(log: log).home();
      expect(log.where((r) => r.url.path.contains('/widgets/')).length, lessThanOrEqualTo(12));
    });
  });

  group('API version', () {
    test('a retired version is replaced by the one the website names', () async {
      final log = <http.Request>[];
      final provider = rtbfProvider(
        log: log,
        handler: (request) {
          final url = request.url;
          if (url.host == 'auvio.rtbf.be') {
            return http.Response(
              '<script src="https://bff-service.rtbf.be/auvio/v1.25/widgets/1"></script>',
              200,
              headers: {'content-type': 'text/html'},
            );
          }
          if (url.path.startsWith('/auvio/v1.23/pages/home')) return rtbfReply({'status': 410}, status: 410);
          if (url.path.startsWith('/auvio/v1.25/pages/home')) return rtbfReply(rtbfFixture('home'));
          if (url.path.startsWith('/auvio/v1.25/widgets/')) return rtbfReply(rtbfFixture('widget_program_list'));
          return rtbfReply(rtbfFixture('error_not_found'), status: 404);
        },
      );
      final rails = await provider.home();
      expect(rails, isNotEmpty);
      final widgetCalls = log.where((r) => r.url.path.contains('/widgets/'));
      expect(widgetCalls.every((r) => r.url.path.startsWith('/auvio/v1.25/')), isTrue);
    });

    test('a retired version with no replacement is an error', () async {
      final provider = rtbfProvider(
        handler: (request) => request.url.host == 'auvio.rtbf.be'
            ? http.Response('<html></html>', 200, headers: {'content-type': 'text/html'})
            : rtbfReply({'status': 410}, status: 410),
      );
      await expectLater(provider.home(), throwsA(isA<Exception>()));
    });
  });

  group('Artwork', () {
    const poster = 'https://static-content.rtbf.be/image/media/program/2x3/1248xauto/f/d/7/fd7fa.jpg';
    const still = 'https://static-content.rtbf.be/image/media/object/default/16x9/770x433/f/7/b/f7bf.jpg';

    test('a poster takes the smallest step that covers the width', () {
      expect(rtbfImageUrl(poster, width: 300), contains('/370xauto/'));
      expect(rtbfImageUrl(poster, width: 371), contains('/770xauto/'));
      expect(rtbfImageUrl(poster, width: 5000), contains('/1920xauto/'));
    });

    test('a still changes width and height together', () {
      expect(rtbfImageUrl(still, width: 100), contains('/16x9/180x100/'));
      expect(rtbfImageUrl(still, width: 1000), contains('/16x9/1248x702/'));
    });

    test('a height alone picks the step of a 16:9 box', () {
      expect(rtbfImageUrl(still, height: 200), contains('/370x208/'));
    });

    test('no size asked leaves the reference as stored', () {
      expect(rtbfImageUrl(poster), poster);
    });

    test('a picture without a size folder is returned unchanged', () {
      const background = 'https://static-content.rtbf.be/media/program/background/f8958199.jpg';
      expect(rtbfImageUrl(background, width: 300), background);
    });

    test('the placeholder picture is resized like the others', () {
      const fallback = 'https://ds1.static.rtbf.be/default/image/770x433/default-auvio_0.jpg';
      expect(rtbfImageUrl(fallback, width: 200), contains('/image/370x208/'));
    });

    test('only Auvio picture hosts are claimed', () {
      expect(isRtbfImage(poster), isTrue);
      expect(isRtbfImage('https://ds1.static.rtbf.be/default/image/770x433/default-auvio_0.jpg'), isTrue);
      expect(isRtbfImage('https://api-cdn.arte.tv/img/v2/image/abc/720x405'), isFalse);
      expect(isRtbfImage('not a url'), isFalse);
    });

    test('the provider sizes artwork it produced', () async {
      final provider = rtbfProvider();
      final rails = await provider.home();
      final reference = rails.firstWhere((r) => r.id == '22683').titles.first.posterUrl!;
      expect(provider.ownsImage(reference), isTrue);
      expect(provider.imageUrl(reference, width: 300), contains('/370xauto/'));
    });
  });
}
