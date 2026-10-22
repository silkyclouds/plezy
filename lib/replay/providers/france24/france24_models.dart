import 'france24_images.dart';
import 'france24_numbering.dart';

/// One page of a France 24 list, with the position the server reports.
class France24Page<T> {
  final List<T> items;
  final int total;
  final int page;
  final int lastPage;

  const France24Page({required this.items, required this.total, required this.page, required this.lastPage});
}

/// A programme (a show): a name and artwork, with its episodes held in a separate list.
class France24Programme {
  final String nid;
  final String title;
  final String? summaryHtml;
  final String? imageUrl;
  final String? squareImageUrl;

  const France24Programme({
    required this.nid,
    required this.title,
    this.summaryHtml,
    this.imageUrl,
    this.squareImageUrl,
  });

  static France24Programme? fromJson(Map<String, dynamic> json) {
    final nid = _text(json['nid']);
    final title = _text(json['title']) ?? _text(json['display_title']);
    if (nid == null || title == null) return null;
    return France24Programme(
      nid: nid,
      title: title,
      summaryHtml: _text(json['description']) ?? _text(json['intro']),
      imageUrl: france24OriginalImage(json['images']),
      squareImageUrl: france24OriginalImage(json['podcast_square_image']),
    );
  }
}

/// A playable video: a clip on its own, or the media of an edition.
class France24Video {
  final String nid;
  final String title;
  final String? summaryHtml;

  /// Editorial label such as "Analyse".
  final String? label;
  final int? durationSeconds;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime? publishedAt;

  /// Direct files by the broadcaster's format code (`MP4-HD`, `MP4-FULL-HD`, ...).
  final Map<String, String> formats;
  final String? imageUrl;
  final List<String> people;

  const France24Video({
    required this.nid,
    required this.title,
    required this.formats,
    this.summaryHtml,
    this.label,
    this.durationSeconds,
    this.validFrom,
    this.validUntil,
    this.publishedAt,
    this.imageUrl,
    this.people = const [],
  });

  static France24Video? fromJson(Map<String, dynamic> json) {
    final nid = _text(json['nid']);
    if (nid == null) return null;
    final millis = int.tryParse(_text(json['duration']) ?? '');
    return France24Video(
      nid: nid,
      title: _text(json['title']) ?? _text(json['title_news']) ?? nid,
      summaryHtml: _text(json['description']) ?? _text(json['intro']),
      label: _text(json['cartouche']),
      durationSeconds: millis == null ? null : (millis / 1000).round(),
      validFrom: _date(json['validity_start_date']),
      validUntil: _date(json['validity_end_date']),
      publishedAt: _date(json['created']),
      formats: _formats(json['formats']),
      imageUrl: france24OriginalImage(json['images']),
      people: _names(json['authors']),
    );
  }
}

/// One broadcast of a programme: the unit that becomes an episode.
class France24Edition {
  final String nid;
  final String title;
  final String? subtitle;
  final String? summaryHtml;
  final String? section;
  final DateTime? createdAt;
  final String? programmeNid;
  final String? programmeTitle;
  final France24Video? video;
  final String? imageUrl;
  final List<String> people;
  final List<String> themes;

  const France24Edition({
    required this.nid,
    required this.title,
    this.subtitle,
    this.summaryHtml,
    this.section,
    this.createdAt,
    this.programmeNid,
    this.programmeTitle,
    this.video,
    this.imageUrl,
    this.people = const [],
    this.themes = const [],
  });

  /// The calendar day the edition belongs to, which decides its season and episode number.
  DateTime? get day => france24DayOfNid(nid) ?? _dayOf(createdAt);

  DateTime? get airDate => createdAt ?? day;

  static France24Edition? fromJson(Map<String, dynamic> json) {
    final nid = _text(json['nid']);
    if (nid == null) return null;
    final programme = json['programs'];
    final videos = json['main_video'];
    final video = videos is List && videos.isNotEmpty && videos.first is Map<String, dynamic>
        ? France24Video.fromJson(videos.first as Map<String, dynamic>)
        : null;
    return France24Edition(
      nid: nid,
      title: _text(json['title']) ?? video?.title ?? nid,
      subtitle: _text(json['surtitle']),
      summaryHtml: _text(json['intro']) ?? video?.summaryHtml,
      section: _text(json['section']),
      createdAt: _date(json['created']),
      programmeNid: programme is Map<String, dynamic> ? _text(programme['nid']) : null,
      programmeTitle: programme is Map<String, dynamic> ? _text(programme['title']) : null,
      video: video,
      imageUrl: france24OriginalImage(json['images']) ?? video?.imageUrl,
      people: {..._names(json['authors']), ..._names(json['guests'])}.toList(),
      themes: _themes(json['taxonomy']),
    );
  }
}

/// Taxonomy vocabulary that holds subject tags; the other vocabularies list people and programmes.
const _themeVocabulary = '102_D220_17';

DateTime? _dayOf(DateTime? moment) => moment == null ? null : DateTime.utc(moment.year, moment.month, moment.day);

String? _text(Object? value) {
  final text = value is String ? value.trim() : (value is num ? '$value' : '');
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? millis) {
  final value = int.tryParse(_text(millis) ?? '');
  return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

Map<String, String> _formats(Object? raw) {
  if (raw is! List) return const {};
  return {
    for (final entry in raw.whereType<Map<String, dynamic>>())
      if (_text(entry['code']) case final code? when _text(entry['url']) != null) code: _text(entry['url'])!,
  };
}

List<String> _names(Object? raw) {
  if (raw is! List) return const [];
  return [for (final person in raw.whereType<Map<String, dynamic>>()) ?_text(person['name'])];
}

List<String> _themes(Object? taxonomy) {
  if (taxonomy is! List) return const [];
  return [
    for (final group in taxonomy.whereType<Map<String, dynamic>>())
      if (group['vid'] == _themeVocabulary) ..._names(group['tags']),
  ];
}
