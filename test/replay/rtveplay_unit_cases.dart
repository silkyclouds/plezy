import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_api.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_dates.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_ids.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_images.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_mapper.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_numbering.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_playback.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_stream_urls.dart';
import 'package:plezy/replay/providers/rtveplay/rtveplay_text.dart';

import 'rtveplay_test_support.dart';

Map<String, dynamic> _video(Map<String, dynamic> fields) => {'id': '1', 'episode': 0, ...fields};

void defineRtveUnitCases() {
  group('RTVE refs', () {
    test('programmes, seasons and videos survive a round trip', () {
      expect(parseRtveRef(rtveRef('p175650')), isA<RtveShowTarget>());
      final season = parseRtveRef(rtveRef('p175650/1000630')) as RtveSeasonTarget;
      expect((season.programId, season.seasonId, season.isSynthetic), ('175650', '1000630', false));
      expect((parseRtveRef(rtveRef('p1/_all')) as RtveSeasonTarget).isSynthetic, isTrue);
      expect((parseRtveRef(rtveRef('v16177116')) as RtveVideoTarget).videoId, '16177116');
    });

    test('ids this provider never issues are rejected', () {
      for (final native in ['', '123', 'p', 'pabc', 'p1/', 'p1/x', 'v', 'v1/2', 'p1/2/3']) {
        expect(parseRtveRef(rtveRef(native)), isNull, reason: native);
      }
    });
  });

  group('RTVE numbering', () {
    test('a stated episode number wins over the title', () {
      expect(rtveEpisodeNumber(_video({'episode': 7, 'longTitle': 'Serie - T2 - Episodio 9: Otro'})), 7);
    });

    test('quiz and talk shows are numbered from "Programa N"', () {
      expect(rtveEpisodeNumber(_video({'title': 'Programa 540', 'longTitle': 'Cifras y letras - Programa 540'})), 540);
      expect(rtveEpisodeNumber(_video({'title': 'Mañaneros - Programa 232'})), 232);
    });

    test('other labels are read too', () {
      expect(rtveEpisodeNumber(_video({'longTitle': 'Serie - T3 - Capítulo 12: Título'})), 12);
      expect(rtveEpisodeNumber(_video({'longTitle': 'Serie - Episodio 7: Carlos'})), 7);
      expect(rtveEpisodeNumber(_video({'title': 'Serie T2 - E5'})), 5);
    });

    test('dates and times in a title are not episode numbers', () {
      expect(rtveEpisodeNumber(_video({'title': 'Telediario - 21 horas - 21/10/26'})), isNull);
      expect(rtveEpisodeNumber(_video({'title': 'Programa 20/10/26'})), isNull);
      expect(rtveEpisodeNumber(_video({'title': 'Informativo 24 horas - 20h - 21/10/26'})), isNull);
      expect(rtveEpisodeNumber(_video({'title': 'Programa 0'})), isNull);
    });

    test('the season is RTVE order, else "T3" or "Temporada 3" in the text', () {
      expect(rtveSeasonNumber(_video({'temporadaOrden': 23})), 23);
      expect(rtveSeasonNumber(_video({'temporada': 'Temporada 4'})), 4);
      expect(rtveSeasonNumber(_video({'longTitle': 'Cuéntame cómo pasó - T12 - Episodio 3'})), 12);
      expect(rtveSeasonNumber(_video({'title': 'Telediario'})), isNull);
    });
  });

  group('RTVE dates', () {
    test('summer and winter times are converted from Madrid time', () {
      expect(rtveParseDate('07-07-2024 10:25:00'), DateTime.utc(2024, 7, 7, 8, 25));
      expect(rtveParseDate('15-12-2025 20:24:08'), DateTime.utc(2025, 12, 15, 19, 24, 8));
    });

    test('the clock change days use the right offset', () {
      expect(rtveParseDate('30-03-2024 12:00:00'), DateTime.utc(2024, 3, 30, 11));
      expect(rtveParseDate('31-03-2024 04:00:00'), DateTime.utc(2024, 3, 31, 2));
      expect(rtveParseDate('26-10-2024 12:00:00'), DateTime.utc(2024, 10, 26, 10));
      expect(rtveParseDate('27-10-2024 12:00:00'), DateTime.utc(2024, 10, 27, 11));
    });

    test('text that is not a date gives null', () {
      for (final raw in [null, 42, '', 'yesterday', '2024-07-07 10:25:00', '32-13-2024 00:00:00']) {
        expect(rtveParseDate(raw), isNull, reason: '$raw');
      }
      expect(rtveFromEpoch(1720340700000), DateTime.utc(2024, 7, 7, 8, 25));
      expect(rtveFromEpoch(0), isNull);
    });
  });

  group('RTVE text', () {
    test('named, numeric and basic entities become characters', () {
      expect(
        rtvePlainText('<p>&iquest;Qu&eacute; &ldquo;tal&rdquo;? Ni&ntilde;a&nbsp;&#039;s &amp; &#241;</p>'),
        '¿Qué “tal”? Niña \'s & ñ',
      );
    });

    test('an entity RTVE never uses is left as it was', () {
      expect(rtvePlainText('a &madeup; b'), 'a &madeup; b');
    });

    test('the long description wins, an empty one falls back to the short one', () {
      expect(rtveSummary('<p>Largo</p>', 'Corto'), 'Largo');
      expect(rtveSummary('<p> </p>', 'Corto'), 'Corto');
      expect(rtveSummary(null, null), isNull);
    });

    test('credits are split on the bar and ratings read from the sentence', () {
      expect(rtveNames('Ana Duato | Imanol Arias |'), ['Ana Duato', 'Imanol Arias']);
      expect(rtveNames(null), isEmpty);
      expect(rtveContentRating('No recomendable para menores de 16 años'), '16+');
      expect(rtveContentRating('Recomendable para todos los públicos'), 'TP');
      expect(rtveContentRating('Especialmente recomendada para la infancia'), isNull);
    });
  });

  group('RTVE stream list', () {
    test('the recorded list decodes to HLS, DASH and MP4 addresses', () {
      final urls = rtveDecodeStreamUrls(rtveFixtureText('ztnr_16177116.b64'));
      expect(urls, hasLength(3));
      expect(urls[0].path, endsWith('/1720343452515.mp4/video.m3u8'));
      expect(urls[0].queryParameters['idasset'], '16177116');
      expect(urls[1].path, endsWith('/video.mpd'));
      expect(urls[2].scheme, 'http');
    });

    test('text that is not a stream list decodes to nothing', () {
      expect(rtveDecodeStreamUrls(''), isEmpty);
      expect(rtveDecodeStreamUrls('not base64 !!'), isEmpty);
      expect(rtveDecodeStreamUrls('aGVsbG8='), isEmpty);
    });

    test('HLS is preferred, DASH is the fallback, MP4 alone is not played', () {
      final hls = Uri.parse('https://a.example/x/video.m3u8?i=1');
      final dash = Uri.parse('https://a.example/x/video.mpd?i=1');
      final mp4 = Uri.parse('http://b.example/x.mp4?i=1');
      expect(rtvePickManifest([mp4, dash, hls]), hls);
      expect(rtvePickManifest([mp4, dash]), dash);
      expect(rtvePickManifest([mp4]), isNull);
    });
  });

  group('RTVE manifest answers', () {
    RtveProbe probe(int status, {String body = '', Map<String, String> headers = const {}}) =>
        RtveProbe(status: status, headers: headers, body: body);

    test('a clear playlist and a clear DASH manifest raise no refusal', () {
      expect(rtveRefusal(probe(200, body: rtveFixtureText('master.m3u8'))), isNull);
      expect(rtveRefusal(probe(200, body: rtveFixtureText('manifest_head.mpd'))), isNull);
      expect(rtveRefusal(probe(200, body: '#EXTM3U\n#EXT-X-KEY:METHOD=NONE')), isNull);
    });

    test('encryption in either format is DRM', () {
      expect(
        rtveRefusal(probe(200, body: '#EXT-X-KEY:METHOD=AES-128,URI="k"'))?.availability,
        ReplayAvailability.drmProtected,
      );
      expect(
        rtveRefusal(probe(200, body: '<MPD><ContentProtection/></MPD>'))?.availability,
        ReplayAvailability.drmProtected,
      );
    });

    test('statuses map to the reasons the player shows', () {
      expect(rtveRefusal(probe(403))?.availability, ReplayAvailability.geoBlocked);
      expect(rtveRefusal(probe(404))?.availability, ReplayAvailability.expired);
      expect(rtveRefusal(probe(410))?.availability, ReplayAvailability.expired);
      expect(rtveRefusal(probe(500))?.availability, ReplayAvailability.unknown);
    });
  });

  group('RTVE subtitles', () {
    test('every language is kept as an external WebVTT track', () {
      final tracks = rtveParseSubtitles(rtveFixture('subtitulos'));
      expect(tracks.map((t) => t.label), ['Español', 'English', 'Galego', 'Català', 'Euskara']);
      expect(tracks.every((t) => !t.forced), isTrue);
    });

    test('unknown languages keep their code and bad entries are dropped', () {
      final page = rtvePage([
        {'src': 'https://www.rtve.es/resources/vtt/1.vtt', 'lang': 'ru'},
        {'src': 'https://www.rtve.es/resources/vtt/1.vtt', 'lang': 'ru'},
        {'src': 'not a url', 'lang': 'es'},
        {'src': 'https://www.rtve.es/resources/vtt/2.vtt'},
      ]);
      final tracks = rtveParseSubtitles(page);
      expect(tracks, hasLength(1));
      expect(tracks.single.label, 'RU');
    });
  });

  group('RTVE titles', () {
    final now = DateTime.utc(2026, 10, 22, 12);

    test('a video whose end date has passed is expired', () {
      final title = rtveTitleFromVideo(_video({'expirationDate': '01-04-2026 00:00:00'}), now: now)!;
      expect(title.availability, ReplayAvailability.expired);
    });

    test('an unpublished video is expired and a future one is upcoming', () {
      expect(
        rtveAvailability(
          _video({
            'pubState': {'code': 'DESPU'},
          }),
          now,
        ),
        ReplayAvailability.expired,
      );
      expect(rtveAvailability(_video({'publicationDate': '23-10-2026 09:00:00'}), now), ReplayAvailability.upcoming);
      expect(
        rtveAvailability(
          _video({
            'pubState': {'code': 'ENPUB'},
          }),
          now,
        ),
        ReplayAvailability.playable,
      );
    });

    test('flags that do not predict playback are ignored', () {
      final title = rtveTitleFromVideo(
        _video({'hasDRM': true, 'geolocalizado': true, 'allowedInCountry': true}),
        now: now,
      )!;
      expect(title.availability, ReplayAvailability.playable);
    });

    test('clips and trailers are clips, full videos are episodes', () {
      expect(
        rtveTitleFromVideo(
          _video({
            'type': {'id': 39978, 'name': 'Fragmento'},
          }),
        )!.kind,
        ReplayKind.clip,
      );
      expect(
        rtveTitleFromVideo(
          _video({
            'type': {'id': 39816, 'name': 'Completo'},
          }),
        )!.kind,
        ReplayKind.episode,
      );
    });

    test('a video of a film container is a movie without numbers', () {
      final film = rtveTitleFromVideo(
        _video({
          'title': 'Programa 3',
          'programInfo': {'id': '9', 'title': 'Cine de barrio', 'programType': 'Contenedor Películas'},
        }),
      )!;
      expect(film.kind, ReplayKind.movie);
      expect(film.episodeNumber, isNull);
      expect(film.showRef, rtveRef('p9'));
    });

    test('a record without an id is not a title', () {
      expect(rtveTitleFromVideo({'title': 'x'}), isNull);
      expect(rtveShowFromProgram({'title': 'x'}), isNull);
    });
  });

  group('RTVE images', () {
    test('a programme picture is addressed by programme and field', () {
      final program = {
        'id': 7,
        'imgPoster': '',
        'imgPoster2': 'https://img.rtve.es/imagenes/a/b.jpg',
        'imgPortada': null,
      };
      expect(rtveProgramImage(program, rtvePosterFields), 'https://img.rtve.es/p/7?imgProgApi=imgPoster2');
      expect(rtveProgramImage(program, rtveBackdropFields), isNull);
    });

    test('resizable references get the requested width, within limits', () {
      expect(
        rtveImageUrl('https://img.rtve.es/p/7?imgProgApi=imgPoster', width: 300),
        'https://img.rtve.es/p/7?imgProgApi=imgPoster&w=300',
      );
      expect(rtveImageUrl('https://img.rtve.es/v/42', width: 320, height: 180), 'https://img.rtve.es/v/42?w=320');
      expect(rtveImageUrl('https://img.rtve.es/v/42', width: 9000), 'https://img.rtve.es/v/42?w=1900');
      expect(rtveImageUrl('https://img.rtve.es/v/42'), 'https://img.rtve.es/v/42?w=640');
    });

    test('a width already in the reference is replaced, not repeated', () {
      expect(
        rtveImageUrl('https://img.rtve.es/p/7?imgProgApi=imgPortada&w=400', width: 800),
        'https://img.rtve.es/p/7?imgProgApi=imgPortada&w=800',
      );
    });

    test('originals that RTVE cannot resize are left alone', () {
      const original = 'https://img.rtve.es/imagenes/show/01720343749071.jpg';
      expect(rtveImageUrl(original, width: 300), original);
      expect(rtveImageUrl('https://elsewhere.example/a.jpg', width: 300), 'https://elsewhere.example/a.jpg');
    });

    test('only RTVE pictures are claimed', () {
      expect(isRtveImage('https://img.rtve.es/v/42'), isTrue);
      expect(isRtveImage('https://api-cdn.arte.tv/img/x'), isFalse);
    });
  });
}
