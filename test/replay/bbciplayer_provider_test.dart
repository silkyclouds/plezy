import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/providers/bbciplayer/bbciplayer_images.dart';

import 'bbciplayer_playback_cases.dart';
import 'bbciplayer_season_cases.dart';
import 'bbciplayer_test_support.dart';

void main() {
  group('BbcIplayerProvider browsing', () {
    test('home has a featured row and a row per curated group', () async {
      final rails = await BbcFakeSite().provider().home();
      expect(rails.map((r) => r.id), ['featured', 'group:p07jlk69']);
      expect(rails.first.titles.every((t) => t.kind == ReplayKind.episode), isTrue);
      expect(rails.last.title, 'Comedy');
      expect(rails.last.titles, isNotEmpty);
      expect(rails.last.moreBrowseId, 'group:p07jlk69');
    });

    test('featured episodes name their show and their series', () async {
      final featured = (await BbcFakeSite().provider().home()).first.titles;
      final traitors = featured.firstWhere((t) => t.ref == bbcTestRef('m0030pxt'));
      expect(traitors.title, 'Episode 1');
      expect(traitors.showTitle, 'The Celebrity Traitors');
      expect(traitors.showRef, bbcTestRef('m002csng'));
      expect(traitors.seasonNumber, 2);
      expect(traitors.episodeNumber, 1);
    });

    test('categories list channels first and leave out radio', () async {
      final categories = await BbcFakeSite().provider().categories();
      final ids = categories.map((c) => c.id).toList();
      expect(ids.first, 'ch:bbc_one_london');
      expect(ids, isNot(contains('ch:bbc_radio_one')));
      expect(ids, contains('cat:documentaries'));
      expect(ids, isNot(contains('cat:cbeebies')));
    });

    test('a genre becomes one row with a see-all id', () async {
      final rails = await BbcFakeSite().provider().category('cat:documentaries');
      expect(rails, hasLength(1));
      expect(rails.single.title, 'Documentaries');
      expect(rails.single.moreBrowseId, 'cat:documentaries');
      expect(rails.single.titles.every((t) => t.kind == ReplayKind.show || t.kind == ReplayKind.movie), isTrue);
    });

    test('a channel page is its highlights', () async {
      final rails = await BbcFakeSite().provider().category('ch:bbc_one_london');
      expect(rails.map((r) => r.id), ['featured', 'group:p07jlk69']);
    });

    test('a genre listing reports the total and asks for the right page', () async {
      final site = BbcFakeSite();
      final page = await site.provider().listing('cat:documentaries', page: 2);
      expect(page.totalCount, 1135);
      expect(site.requests.last.url.queryParameters, {'page': '3', 'per_page': '40'});
    });

    test('a group listing is its episodes', () async {
      final page = await BbcFakeSite().provider().listing('group:p07jlk69');
      expect(page.totalCount, 47);
      expect(page.titles, isNotEmpty);
    });

    test('the whole catalogue runs letter after letter', () async {
      final provider = BbcFakeSite().provider();
      final first = await provider.listing(replayAllBrowseId);
      expect(first.totalCount, 155);
      expect(first.titles, hasLength(40));
      expect(first.titles.take(5).map((t) => t.ref.nativeId), ['p0-90', 'p0-91', 'pa0', 'pa1', 'pa2']);
      expect(first.titles[5].ref.nativeId, 'pb0');
    });

    test('a page past a hundred titles of one letter reads its second chunk', () async {
      final last = await BbcFakeSite().provider().listing(replayAllBrowseId, page: 3);
      expect(last.titles, hasLength(35));
      expect(last.titles.first.ref.nativeId, 'pb115');
      expect(last.titles.last.ref.nativeId, 'pb149');
    });

    test('a page beyond the end is empty', () async {
      final page = await BbcFakeSite().provider().listing(replayAllBrowseId, page: 4);
      expect(page.titles, isEmpty);
      expect(page.totalCount, 155);
    });

    test('search mixes shows and episodes and hides coming soon shows', () async {
      final results = await BbcFakeSite().provider().search('blue planet');
      final ids = results.map((r) => r.ref.nativeId).toList();
      expect(ids, ['m0033jdg', 'm000vbrk', 'm00149h3', 'p04tjbtx']);
      expect(results.firstWhere((r) => r.ref.nativeId == 'm00149h3').kind, ReplayKind.movie);
      expect(results.first.kind, ReplayKind.show);
    });

    test('an empty query or no hit returns nothing', () async {
      final provider = BbcFakeSite().provider();
      expect(await provider.search('zzzz'), isEmpty);
      expect(await provider.search('   '), isEmpty);
    });

    test('requests carry the identifying user agent', () async {
      final site = BbcFakeSite();
      await site.provider().search('blue planet');
      expect(site.requests.single.headers['User-Agent'], contains('Plezy-Replay'));
    });
  });

  group('BbcIplayerProvider titles', () {
    test('a show carries artwork, summary and its channel genre', () async {
      final show = await BbcFakeSite().provider().title(bbcTestRef('m002csng'));
      expect(show!.kind, ReplayKind.show);
      expect(show.title, 'The Celebrity Traitors');
      expect(show.summary, isNotEmpty);
      expect(show.genres, ['Entertainment']);
      expect(show.logoUrl, endsWith('.png'));
      expect(show.posterUrl, contains('{recipe}'));
    });

    test('an episode record reports duration, dates and expiry', () async {
      final episode = await BbcFakeSite().provider().title(bbcTestRef('m0030pxt'));
      expect(episode!.kind, ReplayKind.episode);
      expect(episode.durationSeconds, 4409);
      expect(episode.airDate, isNotNull);
      expect(episode.availableUntil, DateTime.utc(2027, 10, 30, 20, 22, 10));
      expect(episode.availability, ReplayAvailability.playable);
    });

    test('a one-off programme is a movie with its own runtime', () async {
      final film = await BbcFakeSite().provider().title(bbcTestRef('m001fyf7'));
      expect(film!.kind, ReplayKind.movie);
      expect(film.title, '2003');
      expect(film.durationSeconds, 741);
      expect(film.year, 2021);
      expect(film.showRef, isNull);
    });

    test('an unknown id is null', () async {
      expect(await BbcFakeSite().provider().title(bbcTestRef('m9999999')), isNull);
    });

    test('an episode past its window is listed as expired', () async {
      final site = BbcFakeSite();
      final late = await site.provider(now: DateTime.utc(2028)).title(bbcTestRef('m0030pxt'));
      expect(late!.availability, ReplayAvailability.expired);
      final early = await site.provider(now: DateTime.utc(2026, 9)).title(bbcTestRef('m0030pxt'));
      expect(early!.availability, ReplayAvailability.upcoming);
    });
  });

  group('BBC iPlayer images', () {
    const template = 'https://ichef.bbci.co.uk/images/ic/{recipe}/p0pcg6k9.jpg';

    test('landscape boxes use sizes the image server accepts', () {
      expect(bbcImageUrl(template, width: 300, height: 170), contains('/320x180/'));
      expect(bbcImageUrl(template, width: 1000, height: 560), contains('/1200x675/'));
      expect(bbcImageUrl(template, width: 9000, height: 5000), contains('/1280x720/'));
      expect(bbcImageUrl(template), contains('/640x360/'));
    });

    test('portrait boxes use the 2:3 sizes', () {
      expect(bbcImageUrl(template, width: 300, height: 450), contains('/304x456/'));
      expect(bbcImageUrl(template, width: 5000, height: 9000), contains('/640x960/'));
    });

    test('the provider recognises only its own images', () {
      final provider = BbcFakeSite().provider();
      expect(provider.ownsImage(template), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
      expect(provider.imageUrl(template, width: 300, height: 170), isNot(contains('{recipe}')));
    });
  });

  bbcSeasonCases();
  bbcPlaybackCases();
}
