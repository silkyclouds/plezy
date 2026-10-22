import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/drtv/drtv_access.dart';
import 'package:plezy/replay/providers/drtv/drtv_alphabet.dart';
import 'package:plezy/replay/providers/drtv/drtv_images.dart';
import 'package:plezy/replay/providers/drtv/drtv_mapper.dart';
import 'package:plezy/replay/providers/drtv/drtv_numbering.dart';
import 'package:plezy/replay/providers/drtv/drtv_provider.dart';
import 'package:plezy/replay/providers/drtv/drtv_refs.dart';

import 'drtv_test_support.dart';

ReplayRef _show(String id) => drtvShowRef(id);

ReplayRef _playable(String id) => drtvPlayableRef(id);

void main() {
  late DrtvFakeSite site;
  late DrtvProvider provider;

  setUp(() {
    site = DrtvFakeSite();
    provider = site.provider();
  });

  group('DrtvProvider browsing', () {
    test('home keeps rows with cards and names the untitled one', () async {
      final rails = await provider.home();
      expect(rails.map((r) => r.title), ['Udvalgt', 'Nye programmer', 'Nye og populære serier']);
      for (final rail in rails) {
        expect(rail.titles, isNotEmpty, reason: rail.title);
        expect(rail.titles.every((t) => t.ref.source == 'drtv'), isTrue);
      }
    });

    test('home drops category links and fills rows DR sent empty', () async {
      final rails = await provider.home();
      final ids = {
        for (final r in rails)
          for (final t in r.titles) t.ref.nativeId,
      };
      expect(ids.any((id) => id == '463050' || id == '376583'), isFalse);
      expect(rails.last.titles, hasLength(3));
      expect(site.where('/lists/209529'), hasLength(1));
    });

    test('a row with more pages points to its list', () async {
      final rails = await provider.home();
      expect(rails.firstWhere((r) => r.title == 'Nye programmer').moreBrowseId, 'list:559087');
      expect(rails.last.moreBrowseId, isNull);
    });

    test('a category is read from its page path', () async {
      final categories = await provider.categories();
      expect(categories.map((c) => c.id), containsAll(['natur', 'ramasjang', 'alle']));
      expect(await provider.category('natur'), isNotEmpty);
      expect(await provider.category('nope'), isEmpty);
      expect(site.where('/page').map((r) => r.url.queryParameters['path']), ['/kategorier/natur']);
    });

    test('the whole catalogue lists each title once', () async {
      final page = await provider.listing(replayAllBrowseId);
      expect(page.titles, hasLength(8));
      expect(page.titles.map((t) => t.ref).toSet(), hasLength(8));
      expect(page.totalCount, 8);
    });

    test('catalogue pages grow as letters are read', () async {
      final alphabet = DrtvAlphabet(site.api(), DrtvMapper(DrtvAccessBook()));
      final first = await alphabet.page(0, 3);
      expect(first.titles, hasLength(3));
      expect(first.totalCount, 4);
      final second = await alphabet.page(1, 3);
      expect(second.titles, hasLength(3));
      expect(second.totalCount, 7);
      final third = await alphabet.page(2, 3);
      expect(third.titles, hasLength(2));
      expect(third.totalCount, 8);
    });

    test('a list page reports an open end until the last page', () async {
      final first = await provider.listing('list:559087');
      expect(first.titles, hasLength(3));
      expect(first.totalCount, 4);
      final second = await provider.listing('list:559087', page: 1);
      expect(second.titles, hasLength(2));
      expect(second.totalCount, 102);
      expect((await provider.listing('unknown')).titles, isEmpty);
    });

    test('search returns shows before episodes and skips blank queries', () async {
      final found = await provider.search('natur');
      expect(found.take(5).every((t) => t.kind == ReplayKind.show), isTrue);
      expect(found.where((t) => t.kind == ReplayKind.episode), isNotEmpty);
      expect(found.where((t) => t.kind == ReplayKind.movie).single.title, 'Sommerfugle - Naturens superhelte');
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('  '), isEmpty);
      expect(site.where('/v2/search').first.url.queryParameters['group'], 'true');
    });

    test('a search episode is named by its number and knows its show', () async {
      final found = await provider.search('natur');
      final bidt = found.firstWhere((t) => t.ref == _playable('556031'));
      expect(bidt.title, '20. episode');
      expect(bidt.showTitle, 'Bidt af naturen');
      expect(bidt.episodeNumber, 20);
      expect(bidt.seasonNumber, 1);
      expect(bidt.showRef, _show('549556'));
      expect(bidt.seasonRef, drtvSeasonRef('549558'));
      final thoughts = found.firstWhere((t) => t.ref == _playable('543514'));
      expect(thoughts.title, 'Natur');
      expect(thoughts.showTitle, 'Tænkepauser');
    });
  });

  group('DrtvProvider shows', () {
    test('a show lists its seasons by year with their episode counts', () async {
      final seasons = await provider.children(_show('6954'));
      expect(seasons.map((s) => s.seasonNumber), [2008, 2009, 2010, 2011]);
      expect(seasons.map((s) => s.childCount), [8, 19, 18, 19]);
      expect(seasons.map((s) => s.title), ['Sæson 2008', 'Sæson 2009', 'Sæson 2010', 'Sæson 2011']);
      expect(seasons.every((s) => s.kind == ReplayKind.season && s.showRef == _show('6954')), isTrue);
      expect(seasons.first.ref, drtvSeasonRef('9008'));
      expect(seasons.first.showTitle, 'Frank & Kastaniegaarden');
    });

    test('empty seasons are dropped and unnumbered ones follow the list', () async {
      final seasons = await provider.children(_show('7003'));
      expect(seasons.map((s) => s.seasonNumber), [3, 2009, 2011]);
      expect(seasons.map((s) => s.ref.nativeId), ['saeson/7102', 'saeson/8761', 'saeson/8901']);
    });

    test('a season lists its episodes in watching order with numbers', () async {
      final episodes = await provider.children(drtvSeasonRef('567443'));
      expect(episodes.map((e) => e.episodeNumber), [12, 13, 14]);
      expect(episodes.map((e) => e.seasonNumber).toSet(), {2026});
      expect(episodes.first.title, 'Automatvanding med fjer og fåreuld');
      expect(episodes.last.title, '20 år på Kastaniegaarden');
      expect(episodes.first.kind, ReplayKind.episode);
      expect(episodes.first.seasonRef, drtvSeasonRef('567443'));
      expect(episodes.first.showRef, _show('6954'));
      expect(episodes.first.showTitle, 'Frank & Kastaniegaarden');
      expect(episodes.last.durationSeconds, 1695);
    });

    test('a show whose page lists no seasons gets the season it opened on', () async {
      final seasons = await provider.children(_show('7001'));
      expect(seasons.single.ref, drtvSeasonRef('567443'));
      expect(seasons.single.seasonNumber, 2026);
    });

    test('a show with no season at all gets one synthetic season', () async {
      final seasons = await provider.children(_show('7002'));
      expect(seasons.single.ref, drtvAllEpisodesRef('7002'));
      expect(seasons.single.seasonNumber, 1);
      expect(seasons.single.showRef, _show('7002'));
      final episodes = await provider.children(seasons.single.ref);
      expect(episodes.map((e) => e.episodeNumber), [12, 13, 14]);
      expect(episodes.first.seasonRef, drtvAllEpisodesRef('7002'));
    });

    test('titles resolve for shows, seasons and the synthetic season', () async {
      final show = await provider.title(_show('6954'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'Frank & Kastaniegaarden');
      expect(show.childCount, 19);
      final season = await provider.title(drtvSeasonRef('567443'));
      expect(season!.seasonNumber, 2026);
      expect(season.childCount, 14);
      expect((await provider.title(drtvAllEpisodesRef('6954')))!.ref, drtvAllEpisodesRef('6954'));
      expect(await provider.title(_show('424242')), isNull);
    });

    test('an episode page knows its show and season and a programme is a movie', () async {
      final episode = await provider.title(_playable('622110'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.title, '20 år på Kastaniegaarden');
      expect(episode.showTitle, 'Frank & Kastaniegaarden');
      expect(episode.showRef, _show('6954'));
      expect(episode.seasonRef, drtvSeasonRef('567443'));
      expect(episode.seasonNumber, 2026);
      expect(episode.episodeNumber, 14);
      expect(episode.genres, contains('Natur'));
      expect(episode.contentRating, 'Alle');
      final program = await provider.title(_playable('578151'));
      expect(program!.kind, ReplayKind.movie);
      expect(program.title, 'Afgrunden');
      expect(program.year, 2004);
      expect(program.contentRating, '15+');
      expect(await provider.title(_playable('1')), isNull);
    });

    test('artwork and dates come from the card', () async {
      final episode = (await provider.title(_playable('622110')))!;
      expect(episode.posterUrl, contains("ImageId='81717071'"));
      expect(episode.backdropUrl, contains("ImageId='81745934'"));
      expect(episode.airDate, DateTime.utc(2026, 10, 19, 4));
      expect(episode.availableUntil, DateTime.utc(2028, 10, 19, 21, 59));
      expect(episode.summary, startsWith('Det er ret præcist 20 år siden'));
    });

    test('a title past its offer is expired and one not yet out is upcoming', () async {
      final late = await site.provider(clock: DateTime.utc(2029)).title(_playable('622110'));
      expect(late!.availability, ReplayAvailability.expired);
      final early = await site.provider(clock: DateTime.utc(2026, 10, 1)).title(_playable('622110'));
      expect(early!.availability, ReplayAvailability.upcoming);
      expect((await provider.title(_playable('622110')))!.availability, ReplayAvailability.playable);
    });

    test('opaque ids that are not DR refs resolve to nothing', () async {
      expect(parseDrtvId('serie/12/alle'), isA<DrtvAllEpisodesId>());
      expect(parseDrtvId('saeson/x'), isNull);
      expect(await provider.title(const ReplayRef('arte', '1')), isNull);
      expect(await provider.children(_playable('622110')), isEmpty);
    });
  });

  group('DR numbering', () {
    test('structured fields win over labels', () {
      final numbers = drtvNumbers({
        'seasonNumber': 2,
        'episodeNumber': 5,
        'customFields': {'PlayButtonExtraDetails': 'S9:E9'},
      });
      expect(numbers, (season: 2, episode: 5));
    });

    test('the play button label gives year seasons and episodes', () {
      final numbers = drtvNumbers({
        'customFields': {'PlayButtonExtraDetails': 'S2026:E14 20 år på Kastaniegaarden'},
      });
      expect(numbers, (season: 2026, episode: 14));
    });

    test('the detail line gives them when the label is missing', () {
      final numbers = drtvNumbers({
        'customFields': {'ExtraDetails': 'SÆSON 2 EPISODE 7 | 29M'},
      });
      expect(numbers, (season: 2, episode: 7));
      expect(
        drtvNumbers({
          'customFields': {'ExtraDetails': 'Livsstil | SÆSON 2008'},
        }),
        (season: 2008, episode: null),
      );
    });

    test('the ordinal in the contextual title or the name is a last resort', () {
      expect(drtvNumbers({'contextualTitle': '12. episode'}), (season: null, episode: 12));
      expect(drtvNumbers({'title': 'Sporet - Afsnit 3'}), (season: null, episode: 3));
      expect(drtvNumbers({'seasonNumber': 0, 'episodeNumber': 0}), (season: null, episode: null));
    });

    test('a show title prefix is removed from episode names', () {
      final item = {
        'episodeName': 'Mors dreng: Hvor irriterende må mor være?',
        'contextualTitle': '3. Hvor irriterende må mor være?',
      };
      expect(drtvEpisodeName(item, showTitle: 'Mors dreng'), (
        name: 'Hvor irriterende må mor være?',
        show: 'Mors dreng',
      ));
      expect(drtvEpisodeName(item), (name: 'Hvor irriterende må mor være?', show: 'Mors dreng'));
    });

    test('an episode named like its show falls back to its number', () {
      final item = {'episodeName': 'Bidt af naturen', 'contextualTitle': '20. episode'};
      expect(drtvEpisodeName(item, showTitle: 'Bidt af naturen').name, '20. episode');
      expect(drtvEpisodeName(item), (name: '20. episode', show: 'Bidt af naturen'));
      expect(drtvEpisodeName({'title': 'Alene'}), (name: 'Alene', show: null));
    });
  });

  group('DrtvProvider playback', () {
    test('an open title yields its HLS master, subtitles and no probe', () async {
      final playback = await provider.playback(_playable('622110'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.single.url.host, 'drod20p.akamaized.net');
      expect(playback.streams.single.label, 'Standard');
      expect(playback.subtitles.single.languageCode, 'da');
      expect(playback.subtitles.single.url.path, endsWith('.vtt'));
      expect(site.requests.where((r) => r.url.host.endsWith('akamaized.net')), isEmpty);
    });

    test('a Denmark-only stream refused by the CDN is geoblocked', () async {
      final playback = await provider.playback(_playable('616476'));
      expect(playback.availability, ReplayAvailability.geoBlocked);
      expect(playback.streams, isEmpty);
      expect(site.requests.where((r) => r.url.host.endsWith('akamaized.net')), hasLength(1));
    });

    test('a Denmark-only stream the CDN serves plays with its variants', () async {
      site.manifestStatus = 200;
      final playback = await provider.playback(_playable('616476'));
      expect(playback.isPlayable, isTrue);
      expect(playback.streams.map((s) => s.label), ['Standard', 'Lydbeskrivelse']);
      expect(playback.credits?.start, const Duration(seconds: 3361));
      expect(playback.credits?.end, const Duration(seconds: 3407));
    });

    test('a probe answered 404 or 500 is expired or unknown', () async {
      site.manifestStatus = 404;
      expect((await provider.playback(_playable('616476'))).availability, ReplayAvailability.expired);
      site.manifestStatus = 500;
      final failed = await provider.playback(_playable('616476'));
      expect(failed.availability, ReplayAvailability.unknown);
      expect(failed.message, contains('500'));
    });

    test('a DRM stream is reported and never returned', () async {
      final playback = await provider.playback(_playable('543349'));
      expect(playback.availability, ReplayAvailability.drmProtected);
      expect(playback.streams, isEmpty);
      expect(site.requests.where((r) => r.url.host.endsWith('akamaized.net')), isEmpty);
    });

    test('a title already known as DRM is not even asked for', () async {
      site.items['777'] = drtvEdited('item_episode', (j) {
        j['id'] = '777';
        (j['customFields'] as Map)['IsSeriesDRMPlayoutRequired'] = 'True';
      });
      final title = await provider.title(_playable('777'));
      expect(title!.availability, ReplayAvailability.drmProtected);
      expect((await provider.playback(_playable('777'))).availability, ReplayAvailability.drmProtected);
      expect(site.where('/videos'), isEmpty);
    });

    test('missing, empty and non-playable refs say why', () async {
      expect((await provider.playback(_playable('404404'))).availability, ReplayAvailability.expired);
      expect((await provider.playback(_playable('500000'))).availability, ReplayAvailability.unknown);
      expect((await provider.playback(_show('6954'))).isPlayable, isFalse);
      expect((await provider.playback(drtvSeasonRef('567443'))).isPlayable, isFalse);
    });

    test('rate limiting is reported and spares the next request', () async {
      final first = await provider.playback(_playable('429429'));
      expect(first.isPlayable, isFalse);
      expect(first.message, contains('30'));
      final before = site.requests.length;
      final second = await provider.playback(_playable('622110'));
      expect(second.message, contains('retry'));
      expect(site.requests.length, before);
    });
  });

  group('DrtvProvider availability forecast', () {
    test('Denmark-only titles are geoblocked for a viewer abroad', () async {
      final found = await provider.search('natur');
      final verdicts = await provider.predictAvailability(found, 'BE');
      expect(verdicts[_show('623812')], ReplayAvailability.geoBlocked);
      expect(verdicts[_show('550577')], ReplayAvailability.geoBlocked);
      expect(verdicts[_playable('465063')], ReplayAvailability.geoBlocked);
      expect(verdicts[_playable('543514')], ReplayAvailability.geoBlocked);
    });

    test('open titles and unknown titles get no verdict', () async {
      final found = await provider.search('natur');
      final verdicts = await provider.predictAvailability([
        ...found,
        ReplayTitle(ref: _playable('999999'), kind: ReplayKind.movie, title: 'Never listed'),
      ], 'BE');
      expect(verdicts.containsKey(_show('186894')), isFalse);
      expect(verdicts.containsKey(_playable('556031')), isFalse);
      expect(verdicts.containsKey(_playable('999999')), isFalse);
      expect(verdicts.values.toSet(), {ReplayAvailability.geoBlocked});
    });

    test('a viewer in Denmark is told nothing about geography', () async {
      final found = await provider.search('natur');
      expect(await provider.predictAvailability(found, 'DK'), isEmpty);
      expect(await provider.predictAvailability(found, 'dk'), isEmpty);
    });

    test('DRM shows are protected whatever the country', () async {
      site.items['778'] = drtvEdited('item_episode', (j) {
        j['id'] = '778';
        (j['customFields'] as Map)
          ..['IsSeriesDRMPlayoutRequired'] = 'True'
          ..['IsGeoRestricted'] = 'True';
      });
      final title = (await provider.title(_playable('778')))!;
      for (final country in ['DK', 'BE', 'us']) {
        final verdicts = await provider.predictAvailability([title], country);
        expect(verdicts[title.ref], ReplayAvailability.drmProtected, reason: country);
      }
    });

    test('the access flags are read from the strings DR uses', () {
      expect(
        drtvAccessOf({
          'customFields': {'IsGeoRestricted': 'True'},
        }).denmarkOnly,
        isTrue,
      );
      expect(
        drtvAccessOf({
          'customFields': {'IsGeoRestricted': 'False'},
        }).denmarkOnly,
        isFalse,
      );
      expect(
        drtvAccessOf({
          'customFields': {'IsSeasonDRMPlayoutRequired': 'True'},
        }).drm,
        isTrue,
      );
      const parent = DrtvAccess(denmarkOnly: true, drm: true);
      final inherited = drtvAccessOf({'customFields': <String, dynamic>{}}, inherited: parent);
      expect((inherited.denmarkOnly, inherited.drm), (true, true));
      expect(
        drtvAccessOf({
          'customFields': {'IsGeoRestricted': 'False'},
        }, inherited: parent).denmarkOnly,
        isFalse,
      );
    });
  });

  group('DR requests', () {
    test('catalogue calls carry the anonymous token and an honest agent', () async {
      await provider.title(_show('6954'));
      final sso = site.requests.firstWhere((r) => r.url.host == 'isl.dr-massive.com');
      expect(sso.body, contains('"Catalog"'));
      expect(sso.body, contains('device-test'));
      final page = site.where('/page').single;
      expect(page.headers['Authorization'], 'Bearer token-account-test');
      expect(page.headers['User-Agent'], contains('Plezy-Replay'));
      expect(page.url.queryParameters['lang'], 'da');
      expect(page.url.queryParameters['segments'], 'drtv,optedout');
    });

    test('a refused token is renewed once and the call repeated', () async {
      site.refuseCatalogue = 1;
      expect(await provider.title(_show('6954')), isNotNull);
      expect(site.requests.where((r) => r.url.host == 'isl.dr-massive.com'), hasLength(2));
      expect(site.where('/page'), hasLength(2));
    });

    test('catalogue pages are kept for a few minutes', () async {
      await provider.home();
      await provider.home();
      expect(site.where('/page'), hasLength(1));
    });
  });

  group('DR images', () {
    const tile =
        "https://prod95-static.dr-massive.com/api/shain/v1/dataservice/ResizeImage/\$value?Format='png'&Quality=85&EntityType='Item'&EntityId='1'&Width=1920&Height=1080&ImageId='9'";
    const poster =
        "https://prod95-static.dr-massive.com/api/shain/v1/dataservice/ResizeImage/\$value?Format='png'&Quality=85&EntityType='Item'&EntityId='1'&Width=1440&Height=2160&ImageId='9'";

    test('the format, quality and size are rewritten', () {
      final url = drtvImageUrl(tile, width: 640, height: 360);
      expect(url, contains("Format='jpg'"));
      expect(url, contains('Quality=75'));
      expect(url, contains('Width=640'));
      expect(url, contains('Height=360'));
      expect(url, contains("ImageId='9'"));
    });

    test('the original ratio is kept whichever side is given', () {
      expect(drtvImageUrl(tile, width: 320), allOf(contains('Width=320'), contains('Height=180')));
      expect(drtvImageUrl(poster, height: 600), allOf(contains('Width=400'), contains('Height=600')));
      expect(drtvImageUrl(tile), allOf(contains('Width=640'), contains('Height=360')));
    });

    test('a box with another ratio is covered, not stretched', () {
      expect(drtvImageUrl(tile, width: 300, height: 300), allOf(contains('Width=533'), contains('Height=300')));
    });

    test('an image is never asked larger than its original', () {
      expect(drtvImageUrl(tile, width: 5000), allOf(contains('Width=1920'), contains('Height=1080')));
    });

    test('only DR picture hosts are claimed', () {
      expect(provider.ownsImage(tile), isTrue);
      expect(provider.ownsImage('https://api-cdn.arte.tv/img/x'), isFalse);
      expect(provider.imageUrl(poster, width: 200, height: 300), contains('Width=200'));
    });
  });

  test('a native id survives a ref round trip', () {
    for (final ref in [_show('1'), drtvSeasonRef('2'), drtvAllEpisodesRef('3'), _playable('4')]) {
      expect(ReplayRef.tryParse(ref.toString()), ref);
      expect(parseDrtvId(ref.nativeId), isNotNull);
    }
  });
}
