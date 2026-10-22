import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/lrt/lrt_api.dart';
import 'package:plezy/replay/providers/lrt/lrt_article.dart';
import 'package:plezy/replay/providers/lrt/lrt_dates.dart';
import 'package:plezy/replay/providers/lrt/lrt_feed.dart';
import 'package:plezy/replay/providers/lrt/lrt_flight.dart';
import 'package:plezy/replay/providers/lrt/lrt_images.dart';
import 'package:plezy/replay/providers/lrt/lrt_index.dart';
import 'package:plezy/replay/providers/lrt/lrt_models.dart';
import 'package:plezy/replay/providers/lrt/lrt_numbering.dart';
import 'package:plezy/replay/providers/lrt/lrt_playback.dart';
import 'package:plezy/replay/providers/lrt/lrt_refs.dart';
import 'package:plezy/replay/providers/lrt/lrt_search.dart';
import 'package:plezy/replay/providers/lrt/lrt_show_page.dart';

import 'lrt_test_support.dart';

String _push(String piece) => '<script>self.__next_f.push([1,${jsonEncode(piece)}])</script>';

LrtRecording _recording(String id, String title, {DateTime? at}) =>
    LrtRecording(postId: id, title: title, published: at);

/// Parsers and small rules, against recorded bodies and against bodies that are broken on purpose.
void lrtParsingCases() {
  group('LRT feed', () {
    test('items become recordings with picture, date and programme', () {
      final feed = parseLrtFeed(lrtFixture('rss_show_head.xml'));
      expect(feed.map((r) => r.postId), ['2000901019', '2000901017', '2000901016']);
      expect(feed.first.title, 'Žinios');
      expect(feed.first.showTitle, 'Žinios');
      expect(feed.first.published, DateTime.utc(2026, 10, 22, 5, 44));
      expect(feed.first.imageTemplate, 'https://www.lrt.lt/img/2026/10/22/2518160-705862-{WxH}.jpg');
      expect(feed.last.title, startsWith('Trumpas išplūdo'));
    });

    test('a body that is not XML gives nothing', () {
      expect(parseLrtFeed('<rss><channel><item><title>x'), isEmpty);
      expect(parseLrtFeed('<html>Not found</html>'), isEmpty);
      expect(parseLrtFeed(null), isEmpty);
      expect(parseLrtFeed(''), isEmpty);
    });

    test('items without a recording link or title are dropped', () {
      const body = '''<rss><channel>
<item><title>No link</title></item>
<item><title>Wrong link</title><link>https://www.lrt.lt/naujienos/1</link></item>
<item><title>  </title><link>https://www.lrt.lt/mediateka/irasas/2000000010/a</link></item>
<item><title>Good &amp; fine</title><link>https://www.lrt.lt/mediateka/irasas/2000000011/a</link><pubDate>soon</pubDate></item>
<item><title>Again</title><guid>https://www.lrt.lt/mediateka/irasas/2000000011/b</guid></item>
</channel></rss>''';
      final feed = parseLrtFeed(body);
      expect(feed, hasLength(1));
      expect(feed.single.title, 'Good & fine');
      expect(feed.single.published, isNull);
      expect(feed.single.imageTemplate, isNull);
    });
  });

  group('LRT page payload', () {
    test('pieces are joined before objects are read', () {
      final html = '${_push('{"a":')}${_push('"x')}${_push(' y"}')}';
      expect(lrtFlightText(html), '{"a":"x y"}');
    });

    test('a piece that is not a valid string is skipped', () {
      const html =
          r'<script>self.__next_f.push([1,"{\"a\":"])</script>'
          r'<script>self.__next_f.push([1,"bad \q escape"])</script>'
          r'<script>self.__next_f.push([1,"1}"])</script>';
      expect(lrtFlightText(html), '{"a":1}');
    });

    test('a cut-off piece ends the text without failing', () {
      expect(lrtFlightText('${_push('ab')}<script>self.__next_f.push([1,"never closed'), 'ab');
      expect(lrtFlightText('no scripts here'), '');
    });

    test('braces inside strings do not end an object', () {
      const text = r'x:{"show":{"title":"a } b \" {","seasons":[]}} tail';
      expect(lrtFlightObject(text, '"show":')?['title'], r'a } b " {');
    });

    test('an occurrence that is cut off or unwanted is passed over', () {
      const text = '"show":false "show":{"title":"x" "show":{"menu":1} "show":{"title":"ok","seasons":[]}';
      final found = lrtFlightObject(text, '"show":', accept: (m) => m['seasons'] is List);
      expect(found?['title'], 'ok');
      expect(lrtFlightObject('"show":{"title":"x"', '"show":'), isNull);
    });

    test('a recorded programme page gives title, seasons and recordings', () {
      final page = parseLrtShowPage(lrtFixture('show_page_zinios.html'), slug: 'zinios')!;
      expect(page.slug, 'zinios');
      expect(page.title, 'Žinios');
      expect(page.summary, isNull);
      expect(page.imageTemplate, 'https://www.lrt.lt/img/2025/06/09/2094718-346385-{WxH}.jpg');
      expect(page.seasons.map((s) => s.slug), ['2026', '2025', '2024-2', '2024', '2023', '2022']);
      expect(page.episodeTotal, 3406);
      expect(page.episodes, hasLength(3));
      final first = page.episodes.first;
      expect(first.postId, '2000901019');
      expect(first.durationSeconds, 820);
      expect(first.showSlug, 'zinios');
      expect(first.seasonSlug, '2026');
      expect(first.published, DateTime.utc(2026, 10, 22, 5, 44));
    });

    test('a page without the payload, or without a programme, is null', () {
      expect(parseLrtShowPage('<html><body>Hello</body></html>', slug: 'x'), isNull);
      expect(parseLrtShowPage(null, slug: 'x'), isNull);
      expect(parseLrtShowPage(_push('{"show":{"title":"No seasons"}}'), slug: 'x'), isNull);
      expect(parseLrtShowPage(_push('{"show":{"title":"  ","seasons":[]}}'), slug: 'x'), isNull);
    });

    test('a page that lacks the recording list still gives the programme', () {
      final html = _push(
        '{"show":{"title":"A","description":"<p>One &amp; two</p>","url":"/mediateka/video/a-b","seasons":'
        '[{"title":"2020","url":"/mediateka/video/a-b/2020"},{"title":"x"},{"title":"2020","url":"/mediateka/video/a-b/2020"}]}}',
      );
      final page = parseLrtShowPage(html, slug: 'a')!;
      expect(page.slug, 'a');
      expect(page.summary, 'One & two');
      expect(page.seasons.map((s) => s.slug), ['2020']);
      expect(page.episodes, isEmpty);
      expect(page.episodeTotal, isNull);
    });

    test('recordings with a missing link or title are skipped', () {
      final html = _push(
        '{"episodes":{"total":"9","items":[{"title":"No url"},{"url":"/mediateka/irasas/2000000012/a"},'
        '7,{"title":"Fine","url":"/mediateka/irasas/2000000013/a","date":"\$D2026-01-02T03:04:05.000Z","duration":"00:01:05"}]},'
        '"show":{"title":"S","seasons":[]}}',
      );
      final page = parseLrtShowPage(html, slug: 's')!;
      expect(page.episodes.map((e) => e.postId), ['2000000013']);
      expect(page.episodes.single.published, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(page.episodes.single.durationSeconds, 65);
      expect(page.episodeTotal, 9);
    });
  });

  group('LRT programme index', () {
    test('every programme link is read with its title decoded', () {
      final programmes = parseLrtProgrammeIndex(lrtFixture('tv_laidos_sample.html'));
      expect(programmes, hasLength(18));
      expect(programmes.first.slug, '1-000-pasaulio-stebuklu-su-vertimu-i-gestu-k');
      expect(programmes.first.title, '1 000 pasaulio stebuklų (su vertimu į gestų k.)');
      final titles = programmes.map((p) => p.title);
      expect(titles, contains('Vakaro žinios & orai'));
      expect(titles, contains('Sporto vakaras \'26 "Finalas"'));
    });

    test('repeats and links to recordings are left out', () {
      final slugs = parseLrtProgrammeIndex(lrtFixture('tv_laidos_sample.html')).map((p) => p.slug);
      expect(slugs.toSet(), hasLength(slugs.length));
      expect(slugs, isNot(contains('x')));
    });

    test('a link without a title attribute uses its text', () {
      const html =
          '<a class="tag-list-block__link" href="/mediateka/video/abc"><span>Laida <b>A</b> &#x41;&#66;&bogus;</span></a>';
      expect(parseLrtProgrammeIndex(html).single.title, 'Laida A AB&bogus;');
    });

    test('other bodies give nothing', () {
      expect(parseLrtProgrammeIndex(null), isEmpty);
      expect(parseLrtProgrammeIndex('<html></html>'), isEmpty);
      expect(parseLrtProgrammeIndex('<a class="tag-list-block__link" href="/mediateka/video/z">'), isEmpty);
    });
  });

  group('LRT search', () {
    test('hits become recordings that know their programme and season', () {
      final page = parseLrtSearch(lrtFixture('search_video.json'));
      expect(page.total, 2322);
      expect(page.recordings, hasLength(4));
      final first = page.recordings.first;
      expect(first.postId, '2000900035');
      expect(first.showTitle, 'Labas rytas, Lietuva');
      expect(first.showSlug, 'labas-rytas-lietuva');
      expect(first.seasonSlug, '2026');
      expect(first.published, DateTime.utc(2026, 10, 21, 4, 46));
      expect(first.imageTemplate, 'https://www.lrt.lt/img/2026/10/21/2517394-198716-{WxH}.jpg');
      expect(page.programmes.single.slug, 'mylekime-gamta');
      expect(page.programmes.single.imageTemplate, isNull);
    });

    test('a programme takes the picture of one of its recordings', () {
      final json = jsonDecode(lrtFixture('search_video.json')) as Map<String, dynamic>;
      (json['similar_categories'] as List).first['category_id'] = 278;
      final page = parseLrtSearch(json);
      expect(page.programmes.single.imageTemplate, page.recordings.first.imageTemplate);
    });

    test('audio, Epika and non-video hits are left out', () {
      final json = jsonDecode(lrtFixture('search_video.json')) as Map<String, dynamic>;
      final items = (json['items'] as List).cast<Map<String, dynamic>>();
      items[0]['is_audio'] = 1;
      items[1]['is_epika'] = 1;
      items[2]['is_video'] = 0;
      expect(parseLrtSearch(json).recordings.map((r) => r.postId), ['2000895052']);
    });

    test('broken bodies give an empty page', () {
      expect(parseLrtSearch('{"items":[{"id"').recordings, isEmpty);
      expect(parseLrtSearch('<html>').total, 0);
      expect(parseLrtSearch(null).programmes, isEmpty);
      expect(parseLrtSearch({'items': 'many', 'total_found': 'lots'}).recordings, isEmpty);
    });

    test('a total that is not a number falls back to the hits', () {
      final json = jsonDecode(lrtFixture('search_video.json')) as Map<String, dynamic>..['total_found'] = 'lots';
      expect(parseLrtSearch(json).total, 4);
    });
  });

  group('LRT metadata record', () {
    test('the article gives summary, length, programme and season', () {
      final recording = parseLrtArticle(lrtFixture('article.json'), postId: '2000901016')!;
      expect(recording.postId, '2000901016');
      expect(recording.summary, startsWith('Jungtinių Valstijų prezidentas'));
      expect(recording.summary, isNot(contains('<')));
      expect(recording.durationSeconds, 796);
      expect(recording.showSlug, 'zinios');
      expect(recording.seasonSlug, '2026');
      expect(recording.published, DateTime.utc(2026, 10, 22, 4, 43));
      expect(recording.imageTemplate, 'https://www.lrt.lt/img/2026/10/22/2518147-674788-{WxH}.jpg');
      expect(recording.availableUntil, isNull);
    });

    test('an expiry date is kept and a body without a title is refused', () {
      final json = jsonDecode(lrtFixture('article.json')) as Map<String, dynamic>
        ..['validTill'] = '2027-01-01T00:00:00.000Z';
      expect(parseLrtArticle(json, postId: '1')!.availableUntil, DateTime.utc(2027));
      expect(parseLrtArticle('{"id":1}', postId: '1'), isNull);
      expect(parseLrtArticle('oops', postId: '1'), isNull);
    });
  });

  group('LRT dates', () {
    test('a feed date keeps its zone', () {
      expect(lrtParseRfc822('Thu, 22 Oct 2026 08:44:00 +0300'), DateTime.utc(2026, 10, 22, 5, 44));
      expect(lrtParseRfc822('Wed, 31 Dec 2025 18:56:00 +0200'), DateTime.utc(2025, 12, 31, 16, 56));
      expect(lrtParseRfc822('Sat, 26 May 2018 09:26 -0500'), DateTime.utc(2018, 5, 26, 14, 26));
      expect(lrtParseRfc822('1 Jan 2027 00:00:00 GMT'), DateTime.utc(2027));
      expect(lrtParseRfc822('tomorrow'), isNull);
      expect(lrtParseRfc822(null), isNull);
    });

    test('local stamps follow Lithuanian summer time', () {
      expect(lrtLocalStamp(DateTime.utc(2026, 10, 22, 5, 44)), '2026-10-22 08:44');
      expect(lrtLocalStamp(DateTime.utc(2026, 12, 31, 22, 30)), '2027-01-01 00:30');
      expect(lrtLocalStamp(DateTime.utc(2026, 10, 25, 0, 59)), '2026-10-25 03:59');
      expect(lrtLocalStamp(DateTime.utc(2026, 10, 25, 1)), '2026-10-25 03:00');
      expect(lrtLocalStamp(DateTime.utc(2026, 3, 29, 0, 59)), '2026-03-29 02:59');
      expect(lrtLocalStamp(DateTime.utc(2026, 3, 29, 1)), '2026-03-29 04:00');
    });

    test('lengths come as seconds or as a clock', () {
      expect(lrtParseDuration(820), 820);
      expect(lrtParseDuration('00:13:16'), 796);
      expect(lrtParseDuration('13:16'), 796);
      expect(lrtParseDuration('1:00:00'), 3600);
      expect(lrtParseDuration(0), isNull);
      expect(lrtParseDuration('soon'), isNull);
      expect(lrtParseDuration('1:2:3:4'), isNull);
      expect(lrtParseDuration(null), isNull);
    });

    test('an ISO date may carry the payload marker', () {
      expect(lrtParseIso(r'$D2026-10-22T05:44:00.000Z'), DateTime.utc(2026, 10, 22, 5, 44));
      expect(lrtParseIso('nonsense'), isNull);
      expect(lrtParseIso(12), isNull);
    });
  });

  group('LRT numbering', () {
    test('titles state their number in several ways', () {
      const cases = {
        'Pažvelk į profesiją kitaip. 102 dalis': 102,
        'Pažvelk į profesiją kitaip 100 dalis': 100,
        'Alyvos žydės. Nijolė 50 metų scenoje! 2 d.': 2,
        'Alyvos žydės. Nijolė 50 metų scenoje! 1d': 1,
        'Labas rytas, Lietuva I d.': 1,
        'Labas rytas, Lietuva IV dalis': 4,
        'Serija 5': 5,
        'Epizodas 12: Pavadinimas': 12,
        '3-oji laida': 3,
      };
      cases.forEach((title, number) => expect(lrtEpisodeNumberFromTitle(title), number, reason: title));
    });

    test('titles with years or no counter state nothing', () {
      for (final title in [
        'Žinios',
        '2019 UEFA U-21 vaikinų futbolo čempionatas',
        '1 000 pasaulio stebuklų',
        '0 dalis',
      ]) {
        expect(lrtEpisodeNumberFromTitle(title), isNull, reason: title);
      }
    });

    test('stated numbers order a season whatever the dates say', () {
      final recordings = [
        _recording('1', 'Laida 3 dalis', at: DateTime.utc(2020, 1, 1)),
        _recording('2', 'Laida 1 dalis', at: DateTime.utc(2020, 3, 1)),
        _recording('3', 'Laida 2 dalis', at: DateTime.utc(2020, 2, 1)),
      ];
      final numbered = lrtNumberRecordings(recordings, complete: false);
      expect(numbered.map((n) => n.recording.postId), ['2', '3', '1']);
      expect(numbered.map((n) => n.number), [1, 2, 3]);
    });

    test('clashing numbers fall back to dates, oldest first', () {
      final recordings = [
        _recording('1', 'Laida 1 dalis', at: DateTime.utc(2020, 3, 1)),
        _recording('2', 'Laida 1 dalis', at: DateTime.utc(2020, 2, 1)),
        _recording('3', 'Laida', at: DateTime.utc(2020, 1, 1)),
      ];
      final numbered = lrtNumberRecordings(recordings, complete: true);
      expect(numbered.map((n) => n.recording.postId), ['3', '2', '1']);
      expect(numbered.map((n) => n.number), [1, 2, 3]);
    });

    test('equal dates keep the feed reversed and a cut feed is not ranked', () {
      final day = DateTime.utc(2025, 12, 31);
      final recordings = [
        _recording('3', 'Žinios', at: day),
        _recording('2', 'Žinios', at: day),
        _recording('1', 'Žinios', at: day),
      ];
      expect(lrtNumberRecordings(recordings, complete: true).map((n) => n.recording.postId), ['1', '2', '3']);
      final cut = lrtNumberRecordings(recordings, complete: false);
      expect(cut.map((n) => n.recording.postId), ['1', '2', '3']);
      expect(cut.map((n) => n.number), [null, null, null]);
      expect(lrtNumberRecordings(const [], complete: true), isEmpty);
    });

    test('year seasons run oldest first and 2024-2 follows 2024', () {
      LrtSeason season(String title) => LrtSeason(id: title, title: title, slug: title);
      final ordered = lrtOrderSeasons([
        for (final t in ['2026', '2025', '2024-2', '2024', '2023']) season(t),
      ]);
      expect(ordered.map((s) => s.title), ['2023', '2024', '2024-2', '2025', '2026']);
      expect(lrtOrderSeasons([season('B'), season('A')]).map((s) => s.title), ['A', 'B']);
      expect(lrtOrderSeasons([season('2020'), season('Special')]).map((s) => s.title), ['Special', '2020']);
      expect(lrtSeasonYear('2024-2'), 2024);
      expect(lrtSeasonYear('Special'), isNull);
    });
  });

  group('LRT images', () {
    test('templates come from sized URLs, paths and page parts', () {
      expect(
        lrtImageTemplate('https://www.lrt.lt/img/2026/10/22/2518160-705862-1287x836.jpg'),
        'https://www.lrt.lt/img/2026/10/22/2518160-705862-{WxH}.jpg',
      );
      expect(
        lrtImageTemplate('/img/2026/10/21/2517394-198716-{WxH}.jpg'),
        'https://www.lrt.lt/img/2026/10/21/2517394-198716-{WxH}.jpg',
      );
      expect(lrtImageTemplate('/img/2025/12/24/2274235-199517-1287x836.png'), endsWith('-{WxH}.png'));
      expect(
        lrtImageTemplateFromParts('/img/2025/06/09/2094718-346385-', '.jpg'),
        'https://www.lrt.lt/img/2025/06/09/2094718-346385-{WxH}.jpg',
      );
    });

    test('pictures outside the picture tree are not used', () {
      expect(lrtImageTemplate('https://www.lrt.lt/images/logo/logo-tv-hd.svg'), isNull);
      expect(lrtImageTemplate('https://example.com/img/a-1x1.jpg'), isNull);
      expect(lrtImageTemplate(null), isNull);
      expect(lrtImageTemplateFromParts(null, '.jpg'), isNull);
      expect(lrtImageTemplateFromParts('', '.jpg'), isNull);
    });

    test('sizes are always ones the picture server answers', () {
      const template = 'https://www.lrt.lt/img/2026/10/22/2518147-674788-{WxH}.jpg';
      expect(lrtImageUrl(template, width: 100), endsWith('-282x158.jpg'));
      expect(lrtImageUrl(template, width: 300), endsWith('-393x221.jpg'));
      expect(lrtImageUrl(template), endsWith('-615x345.jpg'));
      expect(lrtImageUrl(template, width: 700), endsWith('-756x425.jpg'));
      expect(lrtImageUrl(template, width: 4000), endsWith('-1287x836.jpg'));
      expect(lrtImageUrl(template, width: 200, height: 400), endsWith('-615x345.jpg'));
      expect(lrtImageUrl('https://www.lrt.lt/img/fixed.jpg', width: 300), 'https://www.lrt.lt/img/fixed.jpg');
      expect(isLrtImage(template), isTrue);
      expect(isLrtImage('https://static.arte.tv/a.jpg'), isFalse);
    });
  });

  group('LRT ids', () {
    test('an id names its level', () {
      expect(lrtRefKind('rec:2000901016'), LrtRefKind.recording);
      expect(lrtRefKind('rec:31066'), LrtRefKind.recording);
      expect(lrtRefKind('rec:'), LrtRefKind.show);
      expect(lrtPostIdOfNative('rec:31066'), '31066');
      expect(lrtPostIdOfNative('31066'), isNull);
      expect(lrtRecordingRef('31066').toString(), 'lrt:rec:31066');
      expect(lrtRefKind('zinios/2024-2'), LrtRefKind.season);
      expect(lrtRefKind('zinios'), LrtRefKind.show);
      expect(lrtRefKind('2026'), LrtRefKind.show);
      expect(lrtSplitSeasonId('zinios/2024-2'), (show: 'zinios', season: '2024-2'));
      expect(lrtSplitSeasonId('zinios/'), isNull);
      expect(lrtSplitSeasonId('/2024'), isNull);
    });

    test('paths give their parts, relative or absolute', () {
      expect(lrtPostIdOf('https://www.lrt.lt/mediateka/irasas/2000901016/zinios'), '2000901016');
      expect(lrtShowSlugOf('/mediateka/video/zinios/2026'), 'zinios');
      expect(lrtSeasonSlugOf('/mediateka/video/zinios/2024-2?x=1'), '2024-2');
      expect(lrtSeasonSlugOf('/mediateka/video/zinios'), isNull);
      expect(lrtPostIdOf(null), isNull);
      expect(lrtPostIdOf('/mediateka/video/zinios'), isNull);
    });
  });

  group('LRT stream lookup', () {
    test('a recording yields its playlist', () {
      final target = parseLrtMediaInfo(lrtFixture('media_info_ok.json'));
      expect(target.stream.toString(), lrtMasterUrl);
      expect(target.refusal, isNull);
    });

    test('the Lithuania-only placeholder is geoblocked', () {
      final target = parseLrtMediaInfo(lrtFixture('media_info_geo_tikLT.json'));
      expect(target.stream, isNull);
      expect(target.refusal!.availability, ReplayAvailability.geoBlocked);
      expect(target.refusal!.message, contains('Lithuania'));
      const other = '{"title":"t","playlist_item":{"file":"https://www.lrt.lt/static/mp4/tikLT.mp4?v=2"}}';
      expect(parseLrtMediaInfo(other).refusal!.availability, ReplayAvailability.geoBlocked);
    });

    test('a record the site does not know is gone', () {
      expect(
        parseLrtMediaInfo(lrtFixture('media_info_unknown.json')).refusal!.availability,
        ReplayAvailability.expired,
      );
    });

    test('bodies of the wrong shape are unknown, not errors', () {
      for (final body in [
        null,
        '',
        'oops',
        '[]',
        '{"title":"t"}',
        '{"title":"t","playlist_item":{"file":"nonsense"}}',
        '{"title":"t","playlist_item":{"file":""}}',
      ]) {
        expect(parseLrtMediaInfo(body).refusal!.availability, ReplayAvailability.unknown, reason: '$body');
      }
    });

    test('a probe answer decides between playable and each failure', () {
      final stream = Uri.parse(lrtMasterUrl);
      ReplayAvailability? outcome(int status, [String body = '']) =>
          lrtPlaybackFromProbe(stream, (status: status, body: body)).availability;
      expect(outcome(404, '<html>Not found</html>'), ReplayAvailability.expired);
      expect(outcome(410), ReplayAvailability.expired);
      expect(outcome(403), ReplayAvailability.geoBlocked);
      expect(outcome(500), ReplayAvailability.unknown);
      expect(outcome(200, '<html>login</html>'), ReplayAvailability.unknown);
      expect(outcome(200, lrtFixture('master.m3u8')), ReplayAvailability.playable);
      expect(lrtPlaybackFromProbe(stream, null).streams.single.label, 'LT');
    });

    test('a rate limit error says how long to wait', () {
      expect(const LrtRateLimitedException(Duration(seconds: 30)).toString(), contains('30'));
    });
  });
}
