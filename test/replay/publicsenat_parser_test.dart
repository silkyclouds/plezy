import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/providers/publicsenat/publicsenat_parser.dart';

const _fixtures = 'test/replay/fixtures/publicsenat';

String _fixture(String name) => File('$_fixtures/$name').readAsStringSync();

void main() {
  group('entities', () {
    test('numeric, hex and named entities decode in one pass', () {
      expect(decodeEntities('Cap sur l&#039;&Eacute;lys&#233;e &amp; &#x41;'), "Cap sur l'&Eacute;lysée & A");
      expect(decodeEntities('&laquo;&nbsp;oui&nbsp;&raquo;'), '« oui »');
    });

    test('an escaped entity is not decoded twice', () {
      expect(decodeEntities('&amp;lt;b&amp;gt;'), '&lt;b&gt;');
    });

    test('an out-of-range code point is left as written', () {
      expect(decodeEntities('&#99999999;'), '&#99999999;');
    });
  });

  group('programme page', () {
    test('a card carries every field the page shows', () {
      final card = parseShowPage(_fixture('show_unnumbered.html'), 'documentaire').cards.first;
      expect(card.videoId, 'k1Q8jzk5KFFnRoLDHwy');
      expect(card.title, "Dans l'ombre de Berlusconi");
      expect(card.showSlug, 'documentaire');
      expect(card.showTitle, 'Documentaire');
      expect(card.theme, 'Société');
      expect(card.airDate, DateTime.utc(2026, 10, 18));
      expect(card.durationSeconds, 4320);
      expect(card.siteNumber, 0);
      expect(card.imageUrl, matches(RegExp(r'^https://s\d\.dmcdn\.net/')));
    });

    test('captions read as hours and minutes or minutes alone', () {
      final cards = parseShowPage(_fixture('show_unnumbered.html'), 'documentaire').cards;
      final byTitle = {for (final c in cards) c.title: c.durationSeconds};
      expect(byTitle['Pompidou, la cruauté du pouvoir'], 104 * 60);
      expect(byTitle['Les guetteuses du 7 octobre'], 52 * 60);
      expect(byTitle['Balladur - Chirac : mensonges et trahisons'], 60 * 60);
    });

    test('only the episode grid counts, not the suggestions after it', () {
      final page = parseShowPage(_fixture('show_numbered.html'), '1000-pays-pour-demain');
      expect(page.cards, hasLength(12));
      expect(page.cards.every((c) => c.showSlug == '1000-pays-pour-demain'), isTrue);
    });

    test('without the grid marker only cards of the same programme are kept', () {
      final html = _fixture('show_without_episodes.html');
      expect(parseShowPage(html, 'cap-sur-lelysee').cards, isEmpty);
      expect(parseShowPage(html, 'documentaire').cards, hasLength(3));
    });

    test('header facts come from the page metadata', () {
      final page = parseShowPage(_fixture('show_single.html'), 'a-vrai-dire');
      expect(page.title, 'À vrai dire');
      expect(page.summary, startsWith('"À vrai dire" se concentre'));
      expect(page.backdropUrl, startsWith('https://www.publicsenat.fr/app/uploads/'));
    });

    test('paging reads the term, batch size and nonce', () {
      final paging = parseShowPage(_fixture('show_numbered.html'), '1000-pays-pour-demain').paging!;
      expect(
        (paging.termId, paging.limit, paging.nonce, paging.action, paging.total),
        ('1338', 12, 'fixturenonce', 'replays', 16),
      );
    });

    test('a page without the load-more script has no paging', () {
      expect(
        parseShowPage(
          '<html><body><section data-module="Program" data-term-id="1" data-limit="12"></section></body></html>',
          'x',
        ).paging,
        isNull,
      );
    });
  });

  group('markup tolerance', () {
    test('attribute order and class names do not matter', () {
      const html =
          '<article class="whatever"><picture data-x="1" thumb="https://www.dailymotion.com/thumbnail/video/kAbCdEfGhIjKlMnOpQr">'
          '<b>5mn</b></picture><a title="A &amp; B" href="/emission/show-one/a-b-e3" data-seo-target>x</a>'
          '<time datetime="2026-01-02">2 janvier</time></article>';
      final card = parseCards(html).single;
      expect(card.title, 'A & B');
      expect(card.showSlug, 'show-one');
      expect(card.siteNumber, 3);
      expect(card.durationSeconds, 300);
      expect(card.imageUrl, 'https://www.dailymotion.com/thumbnail/video/kAbCdEfGhIjKlMnOpQr');
    });

    test('a card without a Dailymotion id or an episode link is skipped', () {
      const noId = '<article><a href="/emission/s/e-e1" title="t">t</a></article>';
      const noLink =
          '<article><picture thumb="https://www.dailymotion.com/thumbnail/video/kAbCdEfGhIjKlMnOpQr"></picture></article>';
      expect(parseCards(noId + noLink), isEmpty);
    });

    test('a card with no date or caption still parses', () {
      const html =
          '<article><picture thumb="https://www.dailymotion.com/thumbnail/video/kAbCdEfGhIjKlMnOpQr"></picture>'
          '<a href="/emission/s/e-e0" title="t">t</a></article>';
      final card = parseCards(html).single;
      expect(card.airDate, isNull);
      expect(card.durationSeconds, isNull);
      expect(card.theme, isNull);
      expect(card.showTitle, isNull);
    });
  });

  group('index and load-more', () {
    test('programme covers list each programme once with an absolute poster', () {
      final programmes = parseProgrammes(_fixture('programmes.html'));
      expect(programmes.map((p) => p.slug), hasLength(8));
      expect(programmes.first.title, '100% Sénat');
      expect(
        programmes.first.posterUrl,
        'https://www.publicsenat.fr/app/uploads/2025/09/2526-CENT-verticale-site-301x450.jpg',
      );
    });

    test('the load-more answer is read as an object or as text', () {
      const body = {
        'success': true,
        'data': {'template': '<article></article>'},
      };
      expect(parseMoreTemplate(body), '<article></article>');
      expect(parseMoreTemplate(jsonEncode(body)), '<article></article>');
    });

    test('anything else from the load-more call is ignored', () {
      expect(parseMoreTemplate('0'), isNull);
      expect(parseMoreTemplate('<html>login</html>'), isNull);
      expect(parseMoreTemplate({'success': false, 'data': 'no'}), isNull);
      expect(parseMoreTemplate(null), isNull);
    });
  });
}
