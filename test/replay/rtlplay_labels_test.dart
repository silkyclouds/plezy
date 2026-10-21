import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_episodes.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_ids.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_labels.dart';
import 'package:plezy/replay/providers/rtlplay/rtlplay_mapper.dart';

List<RtlPlayLabel> _labels(Map<String, String> byKind) => [
  for (final e in byKind.entries) (text: e.value, kind: e.key),
];

void main() {
  group('RtlPlay label parsing', () {
    test('a French broadcast date becomes a UTC date', () {
      expect(frenchDateOf('mar. 20 oct. 2026'), DateTime.utc(2026, 10, 20));
      expect(frenchDateOf('jeu. 08 oct. 2026'), DateTime.utc(2026, 10, 8));
      expect(frenchDateOf('dim. 4 janv. 2026'), DateTime.utc(2026, 1, 4));
      expect(frenchDateOf('ven. 17 juil. 2026'), DateTime.utc(2026, 7, 17));
      expect(frenchDateOf('sam. 20 juin 2026'), DateTime.utc(2026, 6, 20));
      expect(frenchDateOf('mer. 12 août 2026'), DateTime.utc(2026, 8, 12));
      expect(frenchDateOf('mercredi'), isNull);
      expect(frenchDateOf(null), isNull);
    });

    test('a date at the end of a title is read as day/month/year', () {
      expect(slashDateOf('RTL info 19 heures (20/10/2026)'), DateTime.utc(2026, 10, 20));
      expect(slashDateOf('Persuasion'), isNull);
    });

    test('episode numbers are removed from titles', () {
      expect(stripEpisodePrefix('3. Persuasion'), 'Persuasion');
      expect(stripEpisodePrefix('293. RTL info 19 heures (20/10/2026)'), 'RTL info 19 heures (20/10/2026)');
      expect(stripEpisodePrefix('1917'), '1917');
      expect(stripEpisodePrefix('2001. L\'odyssée'), 'L\'odyssée');
    });

    test('durations read minutes and hours', () {
      expect(durationOf(_labels({'Durée': '93 min'})), 5580);
      expect(durationOf(_labels({'Durée': '1 h 20 min'})), 4800);
      expect(durationOf(_labels({'Durée': 'long'})), isNull);
      expect(durationOf(_labels({})), isNull);
    });

    test('season counts read singular and plural', () {
      expect(seasonCountOf(_labels({'x': '1 saison'})), 1);
      expect(seasonCountOf(_labels({'x': '5 saisons'})), 5);
      expect(seasonCountOf(_labels({'x': '87 min'})), isNull);
    });

    test('age rating codes become an age, unknown codes are dropped', () {
      expect(ratingOf(['PG_12']), '12+');
      expect(ratingOf(['PG_16']), '16+');
      expect(ratingOf(['AL']), isNull);
      expect(ratingOf([]), isNull);
    });

    test('sort keys ignore case and accents', () {
      final titles = ['Zorro', 'Éclats', 'alerte', 'Œuvres'];
      expect((titles.toList()..sort((a, b) => sortKey(a).compareTo(sortKey(b)))), [
        'alerte',
        'Éclats',
        'Œuvres',
        'Zorro',
      ]);
    });
  });

  group('RtlPlay ids', () {
    test('programme, season and episode ids round trip', () {
      for (final native in ['abc', 'abc/3', 'abc/2026/def']) {
        expect(RtlPlayId.tryParse(native)!.toString(), native);
      }
      final episode = RtlPlayId.tryParse('abc/3/def')!;
      expect((episode.programme, episode.season, episode.episode), ('abc', 3, 'def'));
      expect((episode.isEpisode, episode.isSeason, episode.isProgramme), (true, false, false));
    });

    test('malformed ids are rejected', () {
      for (final native in ['', 'a/', '/a', 'a/x', 'a/1/b/c', 'a//b']) {
        expect(RtlPlayId.tryParse(native), isNull, reason: native);
      }
    });
  });

  group('RtlPlay season numbering', () {
    test('ordinary seasons keep their index', () {
      expect(rtlPlaySeasonNumber([1, 2, 3], 2), 2);
    });

    test('calendar-year seasons are numbered by position', () {
      expect(rtlPlaySeasonNumber([2026], 2026), 1);
      expect(rtlPlaySeasonNumber([2027, 2026], 2027), 2);
    });
  });

  group('RtlPlay teasers', () {
    Map<String, dynamic> teaser(Map<String, dynamic> extra) => {'title': 'T', 'detailId': 'id-1', ...extra};

    test('an unreleased title is upcoming and keeps its release label', () {
      final title = rtlPlayTitleFromTeaser(
        teaser({
          'comingSoon': {'fromLabel': 'Demain'},
        }),
      )!;
      expect(title.availability, ReplayAvailability.upcoming);
      expect(title.subtitle, 'Demain');
    });

    test('a search genre tells a film from a series', () {
      expect(rtlPlayTitleFromTeaser(teaser({'genre': 'Film'}))!.kind, ReplayKind.movie);
      expect(rtlPlayTitleFromTeaser(teaser({'genre': 'Série'}))!.kind, ReplayKind.show);
      expect(rtlPlayTitleFromTeaser(teaser({'genre': 'Magazine'}))!.genres, ['Magazine']);
    });

    test('labels without a season count mean a film', () {
      final label = {'label': '2020', 'accessibilityLabel': 'Année de production'};
      expect(
        rtlPlayTitleFromTeaser(
          teaser({
            'labels': [label],
          }),
        )!.kind,
        ReplayKind.movie,
      );
      final seasons = {'label': '2 saisons', 'accessibilityLabel': null};
      expect(
        rtlPlayTitleFromTeaser(
          teaser({
            'labels': [label, seasons],
          }),
        )!.kind,
        ReplayKind.show,
      );
    });

    test('a teaser without a detail id is dropped', () {
      expect(rtlPlayTitleFromTeaser({'title': 'Live'}), isNull);
    });

    test('a broadcast date label becomes the air date', () {
      final title = rtlPlayTitleFromTeaser(
        teaser({
          'labels': [
            {'label': 'jeu. 08 oct. 2026', 'accessibilityLabel': 'Date de diffusion'},
          ],
        }),
      )!;
      expect(title.airDate, DateTime.utc(2026, 10, 8));
    });
  });
}
