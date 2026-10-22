import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_dates.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_ids.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_images.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_numbering.dart';
import 'package:plezy/replay/providers/nrktv/nrktv_text.dart';

import 'nrktv_test_support.dart';

Map<String, dynamic> _episode({int? sequence, String? released, String title = 'Title'}) => {
  'sequenceNumber': ?sequence,
  'releaseDateOnDemand': ?released,
  'titles': {'title': title},
};

void registerNrkTextCases() {
  group('NRK ids', () {
    test('show, season and programme ids survive a round trip', () {
      final show = ReplayRef.tryParse(nrkShowRef('humoretaten').toString())!;
      expect((parseNrkRef(show) as NrkSeriesTarget).seriesId, 'humoretaten');
      final season = ReplayRef.tryParse(nrkSeasonRef('humoretaten', '4').toString())!;
      expect((parseNrkRef(season) as NrkSeasonTarget).season, '4');
      final program = ReplayRef.tryParse(nrkProgramRef('FØST70001294').toString())!;
      expect((parseNrkRef(program) as NrkProgramTarget).programId, 'FØST70001294');
    });

    test('anything else is not ours', () {
      for (final id in ['x', 'series', 'series//1', 'program/a/b', 'season/a']) {
        expect(parseNrkRef(nrkTestRef(id)), isNull, reason: id);
      }
    });
  });

  group('NRK images', () {
    const first = 'https://gfx.nrk.no/aaa';
    final reference = nrkImageRef([
      {'url': 'https://gfx.nrk.no/ccc', 'width': 1920},
      {'url': first, 'width': 300},
      {'url': 'https://gfx.nrk.no/bbb', 'width': 960},
    ])!;

    test('the smallest picture that covers the width is chosen', () {
      expect(nrkImageUrl(reference, width: 100), first);
      expect(nrkImageUrl(reference, width: 500), 'https://gfx.nrk.no/bbb');
      expect(nrkImageUrl(reference, width: 5000), 'https://gfx.nrk.no/ccc');
      expect(nrkImageUrl(reference), 'https://gfx.nrk.no/bbb');
    });

    test('a reference is owned by NRK and a plain address passes through', () {
      expect(isNrkImage(reference), isTrue);
      expect(isNrkImage('https://example.com/a.jpg'), isFalse);
      expect(nrkImageUrl('https://gfx.nrk.no/zzz', width: 300), 'https://gfx.nrk.no/zzz');
    });

    test('page and search picture shapes are read too', () {
      final page = nrkImageRef({
        'webImages': [
          {'uri': first, 'width': 300},
        ],
      });
      final search = nrkImageRef({
        'webImages': [
          {'imageUrl': first, 'pixelWidth': 300},
        ],
      });
      expect(nrkImageUrl(page!), first);
      expect(nrkImageUrl(search!), first);
    });

    test('pictures from other hosts or without a width are ignored', () {
      expect(
        nrkImageRef([
          {'url': 'https://example.com/a.jpg', 'width': 300},
        ]),
        isNull,
      );
      expect(
        nrkImageRef([
          {'url': first},
        ]),
        isNull,
      );
      expect(nrkImageRef(null), isNull);
    });

    test('a title picture is served at a width through the provider', () async {
      final provider = nrkProvider();
      final title = (await provider.home()).first.titles.first;
      final url = provider.imageUrl(title.backdropUrl!, width: 300);
      expect(provider.ownsImage(title.backdropUrl!), isTrue);
      expect(url, startsWith('https://gfx.nrk.no/'));
      expect(url, isNot(contains('#')));
    });
  });

  group('NRK titles', () {
    test('a counter equal to the episode number is dropped', () {
      expect(nrkEpisodeTitle('1. Krompen er konge', number: 1), 'Krompen er konge');
      expect(nrkEpisodeTitle('1. episode', number: 1), 'Episode 1');
    });

    test('a number that is part of the title stays', () {
      expect(nrkEpisodeTitle('2. verdenskrig', number: 5), '2. verdenskrig');
      expect(nrkEpisodeTitle('Krompen er konge', number: 1), 'Krompen er konge');
      expect(nrkEpisodeTitle('1. Krompen er konge', number: null), '1. Krompen er konge');
    });

    test('a day of the month is not a counter', () {
      expect(nrkNumberPrefix('16. oktober · Dømt'), isNull);
      expect(nrkNumberPrefix('3. Foo')?.number, 3);
    });

    test('relative days in news titles become dates', () {
      const day = (year: 2026, month: 10, day: 20);
      expect(nrkNewsTitle('Tirsdag · Møtes i Oslo', day), '20. oktober · Møtes i Oslo');
      expect(nrkNewsTitle('i går · Orienterte Støre', day), '20. oktober · Orienterte Støre');
      expect(nrkNewsTitle('I dag', day), '20. oktober');
    });

    test('news titles with a date, or without one to use, stay as they are', () {
      const day = (year: 2026, month: 10, day: 20);
      expect(nrkNewsTitle('16. oktober · Dømt', day), '16. oktober · Dømt');
      expect(nrkNewsTitle('Tirsdag · Møtes i Oslo', null), 'Tirsdag · Møtes i Oslo');
    });

    test('line breaks are normalised', () {
      expect(nrkPlainText('a\rb\r\nc \r'), 'a\nb\nc');
    });
  });

  group('NRK numbering', () {
    test('stated numbers win when every episode has one', () {
      final numbered = nrkNumberEpisodes([_episode(sequence: 2), _episode(sequence: 1)]);
      expect(numbered.map((n) => n.number), [1, 2]);
      expect(numbered.first.episode['sequenceNumber'], 1);
    });

    test('the counter in a title counts as a stated number', () {
      final numbered = nrkNumberEpisodes([_episode(title: '2. B'), _episode(title: '1. A')]);
      expect(numbered.first.episode['titles'], {'title': '1. A'});
    });

    test('repeated numbers fall back to release dates', () {
      final numbered = nrkNumberEpisodes([
        _episode(sequence: 1, released: '2026-01-02T10:00:00+01:00', title: 'later'),
        _episode(sequence: 1, released: '2026-01-01T10:00:00+01:00', title: 'earlier'),
      ]);
      expect(numbered.map((n) => (n.episode['titles'] as Map)['title']), ['earlier', 'later']);
      expect(numbered.map((n) => n.number), [1, 2]);
    });

    test('with equal dates the later in NRK newest-first list is older', () {
      final numbered = nrkNumberEpisodes([_episode(title: 'newer'), _episode(title: 'older')]);
      expect(numbered.first.episode['titles'], {'title': 'older'});
    });

    test('season names that are numbers keep them, others get a position', () {
      expect(nrkSeasonNumbers(['1', '2']), [1, 2]);
      expect(nrkSeasonNumbers(['2022', '2021']), [2022, 2021]);
      expect(nrkSeasonNumbers(['a', 'b']), [1, 2]);
      expect(nrkSeasonNumbers(['1', '1']), [1, 2]);
    });
  });

  group('NRK dates', () {
    test('ISO durations are read, anything else is not', () {
      expect(nrkParseDuration('PT26M22.8S'), const Duration(minutes: 26, seconds: 22, milliseconds: 800));
      expect(nrkParseDuration('PT0S'), Duration.zero);
      expect(nrkParseDuration('26 min'), isNull);
      expect(nrkParseDuration(null), isNull);
    });

    test('the local date is the one NRK wrote, not the viewer one', () {
      expect(nrkLocalDate('2026-10-22T00:30:00+02:00'), (year: 2026, month: 10, day: 22));
      expect(nrkLocalDate('nonsense'), isNull);
    });

    test('the year 2100 means no end', () {
      expect(nrkExpiry('2100-01-01T23:59:59+01:00'), isNull);
      expect(nrkExpiry('2031-07-31T23:59:00+02:00')?.year, 2031);
    });
  });
}
