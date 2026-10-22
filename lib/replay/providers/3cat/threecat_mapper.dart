import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'threecat_dates.dart';
import 'threecat_geo.dart';
import 'threecat_ids.dart';
import 'threecat_images.dart';
import 'threecat_numbering.dart';

/// Longest film-like video that is still shown as an episode when it has a programme name of its own.
const _movieMinimumSeconds = 75 * 60;

/// Turns catalogue items into titles and remembers the Spain-only flag of the videos it sees.
class ThreeCatMapper {
  final ThreeCatGeoMemory geo;
  final DateTime Function() now;

  ThreeCatMapper(this.geo, this.now);

  /// Titles of an item list. Radio, articles and anything else without a video are dropped, repeats are folded.
  List<ReplayTitle> titles(Iterable<Map<String, dynamic>> items, {ReplayRef? season}) {
    final seen = <ReplayRef>{};
    return [
      for (final item in items)
        if (title(item, season: season) case final mapped? when seen.add(mapped.ref)) mapped,
    ];
  }

  /// One item as a show or a video, or null for a type that has no place here. [season] puts every video of a list
  /// under that season, whatever its own data says.
  ReplayTitle? title(Map<String, dynamic> item, {ReplayRef? season}) => switch (item['tipologia']) {
    'PTVC_PROGRAMA' => threeCatShow(item),
    'DTY_VIDEO_MM' => _video(item, season),
    _ => null,
  };

  ReplayTitle? _video(Map<String, dynamic> item, ReplayRef? season) {
    final mapped = threeCatVideo(item, now: now(), season: season);
    final flag = threeCatSpainOnly(item['geolocalitzacions']);
    final id = _id(item);
    if (id != null && flag != null) geo.remember(id, spainOnly: flag);
    return mapped;
  }
}

/// A programme (TV series, magazine or documentary strand) as a show.
ReplayTitle? threeCatShow(Map<String, dynamic> item) {
  final id = _id(item);
  final name = _text(item['titol']);
  if (id == null || name == null) return null;
  final art = threeCatArtwork(item['imatges']);
  final info = _infoHtml(item);
  return ReplayTitle(
    ref: threeCatShowRef(id),
    kind: ReplayKind.show,
    title: name,
    summary: _infoSummary(info) ?? _text(item['entradeta']) ?? _text(item['entradeta_promo']),
    posterUrl: art.poster ?? art.backdrop,
    backdropUrl: art.backdrop ?? art.poster,
    logoUrl: art.logo,
    year: _infoYear(info),
    genres: _genres(item),
    cast: _cast(item['personatges']),
    contentRating: _rating(item['codis_etics']),
  );
}

/// A video as an episode, a film or a clip. Search results carry less than list items, so every field is optional.
ReplayTitle? threeCatVideo(Map<String, dynamic> item, {required DateTime now, ReplayRef? season}) {
  final id = _id(item);
  if (id == null) return null;
  final rawTitle = _text(item['titol']) ?? _text(item['permatitle']) ?? id;
  final numbering = threeCatNumbering(rawTitle);
  final programme = _programme(item);
  final key = threeCatSeasonKey(item);
  final episode = _positive(item['capitol_temporada']) ?? numbering.episode;
  final seconds = threeCatParseDuration(item['durada']);
  final kind = _videoKind(item, rawTitle, programme?.name, numbering, key, seconds);
  final art = threeCatArtwork(item['imatges']);
  final until = threeCatParseDate(item['data_caducitat'] ?? item['end_pub_date']);
  final published = threeCatParseDate(item['data_publicacio']);
  final isEpisode = kind == ReplayKind.episode;

  return ReplayTitle(
    ref: threeCatVideoRef(id),
    kind: kind,
    title: _displayTitle(numbering, rawTitle, programme?.name),
    summary: _text(item['entradeta']) ?? _text(item['entradeta_promo']),
    posterUrl: art.poster ?? art.backdrop,
    backdropUrl: art.backdrop ?? art.poster,
    durationSeconds: seconds,
    genres: _genres(item),
    contentRating: _rating(item['codis_etics']),
    airDate: threeCatParseDate(item['data_emissio']) ?? published,
    availableUntil: until,
    availability: _availability(published, until, now),
    seasonNumber: isEpisode && key != null ? threeCatSeasonNumber(key) : null,
    episodeNumber: isEpisode ? episode : null,
    showRef: isEpisode && programme != null ? threeCatShowRef(programme.id) : null,
    showTitle: isEpisode ? programme?.name : null,
    seasonRef: isEpisode ? season ?? _seasonRef(programme, key) : null,
  );
}

/// The video behind a media call, which is what a bare video ref can be resolved from.
ReplayTitle? threeCatVideoFromMedia(Map<String, dynamic> media, {required DateTime now}) {
  final info = media['informacio'];
  if (info is! Map<String, dynamic>) return null;
  final id = _id(info);
  if (id == null) return null;
  final rawTitle = _text(info['titol']) ?? id;
  final numbering = threeCatNumbering(rawTitle);
  final programme = _text(info['programa']);
  final millis = ((info['durada'] as Map?)?['milisegons'] as num?)?.round();
  final seconds = millis == null ? null : millis ~/ 1000;
  final image = (media['imatges'] as Map?)?['url'] as String?;
  final etic = info['codi_etic'];
  final kind = _videoKind(info, rawTitle, programme, numbering, null, seconds);
  return ReplayTitle(
    ref: threeCatVideoRef(id),
    kind: kind,
    title: _displayTitle(numbering, rawTitle, programme),
    summary: _text(info['descripcio']),
    posterUrl: image,
    backdropUrl: image,
    durationSeconds: seconds,
    genres: [?_text((info['tematica'] as Map?)?['text'])],
    contentRating: etic is Map ? _ratingFromId(etic['id']) : null,
    airDate: DateTime.tryParse('${(info['data_emissio'] as Map?)?['utc']}')?.toUtc(),
    showTitle: kind == ReplayKind.episode ? programme : null,
    seasonNumber: kind == ReplayKind.episode ? numbering.season : null,
    episodeNumber: kind == ReplayKind.episode ? numbering.episode : null,
    availability: ReplayAvailability.playable,
  );
}

ReplayKind _videoKind(
  Map<String, dynamic> item,
  String rawTitle,
  String? programme,
  ThreeCatNumbering numbering,
  String? seasonKey,
  int? seconds,
) {
  if (item['tipus_contingut'] != null && item['tipus_contingut'] != 'PPD') return ReplayKind.clip;
  final numbered = seasonKey != null || numbering.episode != null || _positive(item['capitol_temporada']) != null;
  if (numbered || threeCatHasDate(rawTitle)) return ReplayKind.episode;
  final standalone = programme == null || programme == numbering.title || (seconds ?? 0) >= _movieMinimumSeconds;
  return standalone ? ReplayKind.movie : ReplayKind.episode;
}

String _displayTitle(ThreeCatNumbering numbering, String rawTitle, String? programme) {
  if (numbering.title.isEmpty) return rawTitle;
  if (threeCatIsOnlyDate(numbering.title) && programme != null) return '$programme - ${numbering.title}';
  return numbering.title;
}

ReplayRef? _seasonRef(({String id, String name})? programme, String? key) =>
    programme == null ? null : threeCatSeasonRef(programme.id, key ?? threeCatLooseSeason);

({String id, String name})? _programme(Map<String, dynamic> item) {
  final programmes = item['programes_tv'];
  if (programmes is! List) return null;
  for (final p in programmes.whereType<Map<String, dynamic>>()) {
    final id = _id(p);
    final name = _text(p['titol']) ?? _text(item['programa']);
    if (p['tipologia'] == 'PTVC_PROGRAMA' && id != null && name != null) return (id: id, name: name);
  }
  return null;
}

ReplayAvailability _availability(DateTime? published, DateTime? until, DateTime now) {
  if (until != null && until.isBefore(now)) return ReplayAvailability.expired;
  if (published != null && published.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}

String? _id(Map<String, dynamic> item) {
  final id = item['id'];
  return id is num || (id is String && id.isNotEmpty) ? '$id' : null;
}

int? _positive(Object? value) => value is num && value > 0 ? value.toInt() : null;

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _genres(Map<String, dynamic> item) {
  final names = <String>{};
  for (final field in const ['formats', 'tematiques']) {
    final entries = item[field];
    if (entries is! List) continue;
    for (final entry in entries.whereType<Map>()) {
      if (_text(entry['desc']) case final name?) names.add(name);
    }
  }
  return names.toList();
}

String? _rating(Object? codes) {
  if (codes is! List) return null;
  final entries = codes.whereType<Map>().toList();
  final main = entries.where((e) => e['main'] == true).firstOrNull ?? entries.firstOrNull;
  return main == null ? null : _ratingFromId(main['id']);
}

String? _ratingFromId(Object? id) {
  if (id == 'CE_TP') return 'TP';
  final match = RegExp(r'^CE_(\d+)$').firstMatch('$id');
  return match == null ? null : '${match.group(1)}+';
}

List<String> _cast(Object? characters) {
  if (characters is! List) return const [];
  return [
    for (final c in characters.whereType<Map>())
      if (RegExp(r'\(([^)]+)\)\s*$').firstMatch('${c['desc']}')?.group(1) case final actor?) actor.trim(),
  ].take(12).toList();
}

String? _infoHtml(Map<String, dynamic> item) {
  final blocks = item['info'];
  if (blocks is! List) return null;
  for (final block in blocks.whereType<Map>()) {
    if (block['nom'] == 'PU_INFO' && block['text'] is String) return block['text'] as String;
  }
  return null;
}

String? _infoSummary(String? html) {
  if (html == null) return null;
  final lines = htmlToText(
    html,
  ).split('\n').where((l) => !RegExp(r'^(Origen|Any|Durada|Direcció):').hasMatch(l.trim()));
  final text = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return text.isEmpty ? null : text;
}

int? _infoYear(String? html) {
  final match = html == null ? null : RegExp(r'Any:\s*(?:</strong>)?\s*(\d{4})').firstMatch(html);
  return match == null ? null : int.parse(match.group(1)!);
}
