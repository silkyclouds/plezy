import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'bbciplayer_seasons.dart';

const bbcIplayerSourceId = 'bbciplayer';

ReplayRef bbcRef(String nativeId) => ReplayRef(bbcIplayerSourceId, nativeId);

/// Reference of a season: the show's id and the key of its slice.
ReplayRef bbcSeasonRef(String showId, String sliceKey) => bbcRef('$showId/$sliceKey');

/// Where an episode was found when the listing already knows more than the episode record does.
class BbcContext {
  final ReplayRef? season;
  final int? seasonNumber;
  final int? episodeNumber;

  const BbcContext({this.season, this.seasonNumber, this.episodeNumber});

  static const none = BbcContext();
}

/// Maps a programme (a show or a one-off) or an episode record; null for rows that are neither, such as groups.
ReplayTitle? bbcTitleFromItem(
  Map<String, dynamic> item, {
  required DateTime now,
  BbcContext context = BbcContext.none,
}) {
  final type = item['type'];
  if (type is! String || item['id'] is! String) return null;
  if (type.startsWith('programme')) return _programme(item, now);
  if (type.startsWith('episode')) return bbcEpisode(item, now: now, context: context);
  return null;
}

/// Titles of a list of records, without repeats.
List<ReplayTitle> bbcTitlesFromElements(Object? elements, DateTime now) {
  if (elements is! List) return const [];
  final seen = <ReplayRef>{};
  return [
    for (final raw in elements)
      if (raw is Map<String, dynamic>)
        if (bbcTitleFromItem(raw, now: now) case final title? when seen.add(title.ref)) title,
  ];
}

ReplayTitle _programme(Map<String, dynamic> item, DateTime now) {
  final id = item['id'] as String;
  final oneOff = item['tleo_type'] == 'episode';
  final child = oneOff ? _firstChild(item) : null;
  final version = child == null ? null : bbcDefaultVersion(child);
  return ReplayTitle(
    ref: bbcRef(id),
    kind: oneOff ? ReplayKind.movie : ReplayKind.show,
    title: _text(item['title']) ?? id,
    summary: _synopsis(item),
    posterUrl: _poster(item),
    backdropUrl: _backdrop(item),
    logoUrl: _image(item, 'logo'),
    durationSeconds: _duration(version),
    year: oneOff ? _year(child ?? item) : null,
    genres: _genres(item),
    airDate: _date(child?['release_date_time']),
    availableUntil: _date(_window(version)?['end']),
    availability: child == null ? _statusOnly(item) : _availability(child, now),
  );
}

/// Maps an episode record. Episodes of a show are named by their own title and point back at the show.
ReplayTitle bbcEpisode(Map<String, dynamic> item, {required DateTime now, BbcContext context = BbcContext.none}) {
  final id = item['id'] as String;
  final brand = item['tleo_id'] as String?;
  final inShow = item['tleo_type'] != 'episode' && brand != null && brand != id;
  final version = bbcDefaultVersion(item);
  final showTitle = _text(item['title']);
  final name = _text(item['original_title']) ?? _text(item['slice_subtitle']) ?? _text(item['subtitle']);
  final seasonNumber = context.seasonNumber ?? bbcSeriesNumber(item['subtitle']);

  return ReplayTitle(
    ref: bbcRef(id),
    kind: inShow ? ReplayKind.episode : ReplayKind.movie,
    title: inShow ? (name ?? showTitle ?? id) : (showTitle ?? name ?? id),
    subtitle: inShow ? showTitle : _text(item['subtitle']),
    summary: _synopsis(item),
    posterUrl: _poster(item),
    backdropUrl: _backdrop(item),
    durationSeconds: _duration(version),
    year: inShow ? null : _year(item),
    genres: _genres(item),
    airDate: _date(item['release_date_time']),
    availableUntil: _date(_window(version)?['end']),
    availability: _availability(item, now),
    seasonNumber: inShow ? seasonNumber : null,
    episodeNumber: inShow ? context.episodeNumber ?? (item['parent_position'] as num?)?.toInt() : null,
    showRef: inShow ? bbcRef(brand) : null,
    showTitle: inShow ? showTitle : null,
    seasonRef: inShow ? context.season ?? bbcSeasonRef(brand, bbcSliceKey(item)) : null,
  );
}

/// The version played by default: the original cut, else the editorial one, else any that is not a variant.
Map<String, dynamic>? bbcDefaultVersion(Map<String, dynamic> episode) {
  final versions = _versions(episode);
  for (final kind in const ['original', 'editorial']) {
    for (final version in versions) {
      if (version['kind'] == kind) return version;
    }
  }
  return versions.where((v) => v['kind'] != 'audio-described' && v['kind'] != 'signed').firstOrNull ??
      versions.firstOrNull;
}

List<Map<String, dynamic>> _versions(Map<String, dynamic> episode) {
  final versions = episode['versions'];
  return versions is List ? versions.whereType<Map<String, dynamic>>().toList() : const [];
}

Map<String, dynamic>? _firstChild(Map<String, dynamic> programme) {
  final children = programme['initial_children'];
  return children is List ? children.whereType<Map<String, dynamic>>().firstOrNull : null;
}

ReplayAvailability _statusOnly(Map<String, dynamic> item) => switch (item['status']) {
  'coming_soon' => ReplayAvailability.upcoming,
  'unavailable' => ReplayAvailability.expired,
  _ => ReplayAvailability.playable,
};

ReplayAvailability _availability(Map<String, dynamic> episode, DateTime now) {
  final byStatus = _statusOnly(episode);
  if (byStatus != ReplayAvailability.playable) return byStatus;
  final window = _window(bbcDefaultVersion(episode));
  final end = _date(window?['end']);
  if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
  final start = _date(window?['start']);
  if (start != null && start.isAfter(now)) return ReplayAvailability.upcoming;
  return ReplayAvailability.playable;
}

Map<String, dynamic>? _window(Map<String, dynamic>? version) {
  final window = version?['availability'];
  return window is Map<String, dynamic> ? window : null;
}

int? _duration(Map<String, dynamic>? version) => bbcParseDuration((version?['duration'] as Map?)?['value'] as String?);

/// Seconds in an ISO 8601 duration such as `PT1H2M10.133333S`, or null.
int? bbcParseDuration(String? iso) {
  if (iso == null) return null;
  final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$').firstMatch(iso);
  if (match == null) return null;
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
  final seconds = double.tryParse(match.group(3) ?? '') ?? 0;
  return hours * 3600 + minutes * 60 + seconds.round();
}

String? _synopsis(Map<String, dynamic> item) {
  final synopses = item['synopses'];
  if (synopses is! Map) return null;
  for (final key in const ['large', 'medium', 'small', 'editorial']) {
    final text = _text(synopses[key]);
    if (text != null) return text;
  }
  return null;
}

String? _image(Map<String, dynamic> item, String key) {
  final value = (item['images'] as Map?)?[key];
  return value is String && value.isNotEmpty ? value : null;
}

String? _poster(Map<String, dynamic> item) => _image(item, 'portrait') ?? _image(item, 'standard');

String? _backdrop(Map<String, dynamic> item) => _image(item, 'promotional') ?? _image(item, 'standard');

List<String> _genres(Map<String, dynamic> item) {
  final label = _text((item['labels'] as Map?)?['category']);
  return label == null ? const [] : [label];
}

int? _year(Map<String, dynamic> item) => _date(item['release_date_time'])?.year;

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
