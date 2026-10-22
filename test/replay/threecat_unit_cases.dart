import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/3cat/threecat_dates.dart';
import 'package:plezy/replay/providers/3cat/threecat_geo.dart';
import 'package:plezy/replay/providers/3cat/threecat_ids.dart';
import 'package:plezy/replay/providers/3cat/threecat_images.dart';
import 'package:plezy/replay/providers/3cat/threecat_mapper.dart';
import 'package:plezy/replay/providers/3cat/threecat_numbering.dart';

import 'threecat_fake_site.dart';

final _now = DateTime.utc(2026, 10, 22, 12);

Map<String, dynamic> _image(String size, String rel, String name) => {
  'text': 'https://img.3cat.cat/multimedia/jpg/$name.jpg',
  'mida': size,
  'rel_name': rel,
};

void threeCatUnitCases() {
  group('3Cat dates', () {
    test('summer time is two hours ahead of UTC', () {
      expect(threeCatParseDate('21/10/2026 14:30:00'), DateTime.utc(2026, 10, 21, 12, 30));
    });

    test('winter time is one hour ahead of UTC', () {
      expect(threeCatParseDate('15/01/2026 10:00:00'), DateTime.utc(2026, 1, 15, 9));
    });

    test('the clock change follows the last Sunday', () {
      expect(threeCatParseDate('25/10/2026 02:30:00'), DateTime.utc(2026, 10, 25, 0, 30));
      expect(threeCatParseDate('25/10/2026 03:30:00'), DateTime.utc(2026, 10, 25, 2, 30));
      expect(threeCatParseDate('29/03/2026 01:30:00'), DateTime.utc(2026, 3, 29, 0, 30));
      expect(threeCatParseDate('29/03/2026 03:30:00'), DateTime.utc(2026, 3, 29, 1, 30));
    });

    test('a date alone and bad text are handled', () {
      expect(threeCatParseDate('21/10/2026'), DateTime.utc(2026, 10, 20, 22));
      expect(threeCatParseDate('21/10/2026 14:30'), DateTime.utc(2026, 10, 21, 12, 30));
      expect(threeCatParseDate('yesterday'), isNull);
      expect(threeCatParseDate(null), isNull);
    });

    test('durations drop the frame count', () {
      expect(threeCatParseDuration('00:54:00:23'), 3240);
      expect(threeCatParseDuration('01:02:03'), 3723);
      expect(threeCatParseDuration('00:00:00:12'), isNull);
      expect(threeCatParseDuration('soon'), isNull);
    });
  });

  group('3Cat numbering', () {
    test('season and episode come out of the title', () {
      final numbering = threeCatNumbering('T1xC1 - Els peripatètics');
      expect((numbering.season, numbering.episode, numbering.title), (1, 1, 'Els peripatètics'));
    });

    test('a dated title keeps the date as its name', () {
      final numbering = threeCatNumbering('T4xC37 - 25/06/2009');
      expect((numbering.season, numbering.episode, numbering.title), (4, 37, '25/06/2009'));
    });

    test('a plain title has no numbers', () {
      final numbering = threeCatNumbering('Alcarràs');
      expect((numbering.season, numbering.episode, numbering.title), (null, null, 'Alcarràs'));
    });

    test('a number with no name keeps the whole title', () {
      expect(threeCatNumbering('T2xC3').title, 'T2xC3');
    });

    test('the season key prefers the broadcaster id', () {
      final both = <String, dynamic>{
        'titol': 'T9xC1 - x',
        'temporades': [
          {'id': 'PUTEMP_2', 'desc': '2a Temporada', 'main': true},
        ],
      };
      expect(threeCatSeasonKey(both), 'PUTEMP_2');
      expect(threeCatSeasonKey({'titol': 'T9xC1 - x'}), 'T9');
      expect(threeCatSeasonKey({'titol': 'x'}), isNull);
      expect(threeCatSeasonNumber('PUTEMP_12'), 12);
      expect(threeCatSeasonNumber('_all'), isNull);
    });
  });

  group('3Cat refs', () {
    test('every kind of ref survives a round trip', () {
      expect(parseThreeCatRef(threeCatShowRef('54076')), isA<ThreeCatShowTarget>());
      final season = parseThreeCatRef(threeCatSeasonRef('54076', 'PUTEMP_2')) as ThreeCatSeasonTarget;
      expect((season.programmeId, season.seasonKey), ('54076', 'PUTEMP_2'));
      final video = parseThreeCatRef(threeCatVideoRef('6431752')) as ThreeCatVideoTarget;
      expect(video.videoId, '6431752');
      expect(ReplayRef.tryParse(threeCatVideoRef('6431752').toString()), threeCatVideoRef('6431752'));
    });

    test('foreign and malformed refs are refused', () {
      expect(parseThreeCatRef(const ReplayRef('arte', 'p1')), isNull);
      expect(parseThreeCatRef(const ReplayRef('3cat', 'x1')), isNull);
      expect(parseThreeCatRef(const ReplayRef('3cat', 'pabc')), isNull);
      expect(parseThreeCatRef(const ReplayRef('3cat', 'p1/')), isNull);
      expect(parseThreeCatRef(const ReplayRef('3cat', 'v')), isNull);
    });
  });

  group('3Cat artwork', () {
    test('a poster and a backdrop are chosen by size', () {
      final art = threeCatArtwork([
        _image('MASTER', 'IMAGE', 'master'),
        _image('120x68', 'KEYVIDEO', 'tiny'),
        _image('326x184', 'KEYVIDEO', 'small'),
        _image('670x378', 'KEYVIDEO', 'medium'),
        _image('1014x570', 'KEYVIDEO', 'large'),
        _image('288x422', 'KEYVIDEO', 'portrait'),
        _image('1014x570_logo', 'IMAGE', 'baked'),
        _image('400x80', 'IMG_IPTV', 'banner'),
      ]);
      expect(art.backdrop, endsWith('/medium.jpg'));
      expect(art.poster, endsWith('/portrait.jpg'));
    });

    test('the largest backdrop below the target is used when none reaches it', () {
      final art = threeCatArtwork([_image('326x184', 'IMAGE', 'a'), _image('426x240', 'IMAGE', 'b')]);
      expect(art.backdrop, endsWith('/b.jpg'));
    });

    test('originals stand in only when no sized picture fits', () {
      final art = threeCatArtwork([
        _image('MASTER', 'IMG_POSTER', 'poster'),
        _image('MASTER', 'IMATGE_169', 'wide'),
        _image('MASTER', 'IMG_LOGO', 'logo'),
        _image('MASTER', 'IMG_IPTV', 'tv'),
      ]);
      expect(art.poster, endsWith('/poster.jpg'));
      expect(art.backdrop, endsWith('/wide.jpg'));
      expect(art.logo, endsWith('/logo.jpg'));
    });

    test('no pictures means no artwork', () {
      final art = threeCatArtwork(null);
      expect((art.poster, art.backdrop, art.logo), (null, null, null));
    });

    test('references are final addresses owned by the provider', () {
      const url = 'https://img.3cat.cat/multimedia/jpg/1/2/3.jpg';
      final provider = ThreeCatFakeSite().provider();
      expect(provider.imageUrl(url, width: 300, height: 450), url);
      expect(provider.ownsImage(url), isTrue);
      expect(provider.ownsImage('https://statics.3cat.cat/img/logos/tv3.svg'), isTrue);
      expect(provider.ownsImage('https://example.com/a.jpg'), isFalse);
    });
  });

  group('3Cat kinds and windows', () {
    ReplayTitle map(Map<String, dynamic> item) => threeCatVideo(item, now: _now)!;

    Map<String, dynamic> item(
      String title, {
      String programme = 'Programa',
      String? duration,
      Map<String, dynamic>? extra,
    }) => {
      ...threeCatVideoItem(id: 7, title: title, programmeId: '5', programmeName: programme, duration: duration),
      ...?extra,
    };

    test('a numbered video is an episode of its show', () {
      final title = map(item('T3xC2 - Nom'));
      expect(title.kind, ReplayKind.episode);
      expect(title.showRef, threeCatShowRef('5'));
    });

    test('a film has no show', () {
      final title = map(item('Alcarràs', programme: 'Alcarràs', duration: '01:58:00:00'));
      expect(title.kind, ReplayKind.movie);
      expect(title.showRef, isNull);
      expect(title.seasonRef, isNull);
    });

    test('a long unnumbered video of a strand is a film', () {
      expect(map(item('Una història', programme: 'Cinema', duration: '01:40:00:00')).kind, ReplayKind.movie);
    });

    test('a web clip is a clip', () {
      final title = map(item('Resum', extra: {'tipus_contingut': 'PPW'}));
      expect(title.kind, ReplayKind.clip);
      expect(title.isPlayable, isTrue);
    });

    test('an item with no id is dropped', () {
      expect(threeCatVideo({'titol': 'x'}, now: _now), isNull);
    });

    test('an expired or unpublished video says so', () {
      final expired = map(item('T1xC1 - A', extra: {'data_caducitat': '01/01/2026 00:00:00'}));
      expect(expired.availability, ReplayAvailability.expired);
      final upcoming = map(item('T1xC1 - A', extra: {'data_publicacio': '30/10/2026 08:00:00'}));
      expect(upcoming.availability, ReplayAvailability.upcoming);
      expect(map(item('T1xC1 - A')).availability, ReplayAvailability.playable);
    });

    test('items of other types are not titles', () {
      final mapper = ThreeCatMapper(ThreeCatGeoMemory(), () => _now);
      expect(mapper.title({'tipologia': 'NOT_NOTICIA', 'id': 1, 'titol': 'x'}), isNull);
      expect(mapper.title({'tipologia': 'WCR_AUDIO_MM', 'id': 1, 'titol': 'x'}), isNull);
    });
  });
}
