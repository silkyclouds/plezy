import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'dw_ids.dart';
import 'dw_images.dart';
import 'dw_numbering.dart';

Map<String, dynamic>? dwMap(Object? value) => value is Map<String, dynamic> ? value : null;

/// A single line of text: markup removed, runs of whitespace collapsed, nothing when blank.
String? dwLine(Object? value) {
  if (value is! String) return null;
  final text = htmlToText(value).replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? null : text;
}

/// Running text that keeps its paragraph breaks.
String? dwParagraphs(Object? value) {
  if (value is! String) return null;
  final text = htmlToText(value);
  return text.isEmpty ? null : text;
}

DateTime? dwDate(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

/// Splits "Euromaxx — Culture. Ideas. Europe." into the programme name and its tagline.
({String name, String? tagline}) dwSplitProgrammeTitle(String title) {
  const separator = ' — ';
  final cut = title.indexOf(separator);
  if (cut <= 0) return (name: title, tagline: null);
  final tagline = title.substring(cut + separator.length).trim();
  return (name: title.substring(0, cut).trim(), tagline: tagline.isEmpty ? null : tagline);
}

/// A programme, from the programme overview or from a programme page.
ReplayTitle? dwShowFromProgramme(Map<String, dynamic> programme) {
  final id = (programme['id'] as num?)?.toInt();
  final fullTitle = dwLine(programme['title']);
  if (id == null || fullTitle == null) return null;
  final split = dwSplitProgrammeTitle(fullTitle);
  final image = dwImageReference(dwMap(programme['mainContentImage'])?['staticUrl']);
  return ReplayTitle(
    ref: dwRef(dwShowId(id)),
    kind: ReplayKind.show,
    title: dwLine(programme['name']) ?? split.name,
    subtitle: split.tagline,
    summary: dwParagraphs(programme['teaser']),
    posterUrl: image,
    backdropUrl: image,
  );
}

/// Everything the mapper needs to know about one video, whichever endpoint it came from.
class _Video {
  final int id;
  final String title;
  final String? summary;
  final DateTime? published;
  final int? seconds;
  final String? image;
  final String? kicker;
  final int? programme;
  final String? programmeName;

  const _Video({
    required this.id,
    required this.title,
    this.summary,
    this.published,
    this.seconds,
    this.image,
    this.kicker,
    this.programme,
    this.programmeName,
  });
}

/// A video that belongs to a programme is an episode of it, in the season of its year. One that does not is a clip.
ReplayTitle _title(_Video v) {
  final date = v.published;
  final programme = v.programme;
  final inShow = programme != null;
  final year = date?.year;
  return ReplayTitle(
    ref: dwRef('${v.id}'),
    kind: inShow ? ReplayKind.episode : ReplayKind.clip,
    title: v.title,
    summary: v.summary,
    posterUrl: v.image,
    backdropUrl: v.image,
    durationSeconds: v.seconds,
    year: year,
    genres: v.kicker == null ? const [] : [v.kicker!],
    airDate: date,
    seasonNumber: inShow ? year : null,
    episodeNumber: inShow && date != null ? dwDayOfYear(date) : null,
    showRef: inShow ? dwRef(dwShowId(programme)) : null,
    showTitle: inShow ? v.programmeName : null,
    seasonRef: inShow && year != null ? dwRef(dwSeasonId(programme, year)) : null,
  );
}

/// A video from a search hit. [programme] is the programme being browsed, preferred when the hit lists several.
ReplayTitle? dwVideoFromHit(Map<String, dynamic> hit, {int? programme}) {
  final id = int.tryParse('${dwMap(hit['_meta'])?['id']}');
  final title = dwLine(_raw(hit, 'title'));
  if (id == null || title == null) return null;
  final ids = _list(_raw(hit, 'unifiedPrograms.id'));
  final names = _list(_raw(hit, 'unifiedPrograms.name'));
  final at = ids.indexWhere((v) => v is num && v.toInt() == programme);
  final slot = at >= 0 ? at : 0;
  final programmeId = slot < ids.length && ids[slot] is num ? (ids[slot] as num).toInt() : null;
  return _title(
    _Video(
      id: id,
      title: title,
      summary: dwParagraphs(_raw(hit, 'teaser')) ?? dwParagraphs(_raw(hit, 'shortTeaser')),
      published: dwDate(_raw(hit, 'contentDate')),
      seconds: (_raw(hit, 'duration') as num?)?.toInt(),
      image: dwImageReference(_raw(hit, 'mainContentImageLink.target.staticUrl')),
      kicker: dwLine(_raw(hit, 'roadTeaserKicker')),
      programme: programmeId,
      programmeName: programmeId != null && slot < names.length ? dwLine(names[slot]) : null,
    ),
  );
}

/// A video from the content graph, or null when the document is not a video.
ReplayTitle? dwVideoFromContent(Map<String, dynamic> content) {
  final id = (content['id'] as num?)?.toInt();
  final title = dwLine(content['title']);
  if (content['__typename'] != 'Video' || id == null || title == null) return null;
  final programmes = content['unifiedPrograms'];
  final owner = programmes is List ? programmes.whereType<Map<String, dynamic>>().firstOrNull : null;
  final programmeId = (owner?['id'] as num?)?.toInt();
  final programmeTitle = dwLine(owner?['title']);
  return _title(
    _Video(
      id: id,
      title: title,
      summary: dwParagraphs(content['teaser']) ?? dwParagraphs(content['shortTeaser']),
      published: dwDate(content['contentDate']),
      seconds: (content['duration'] as num?)?.toInt(),
      image: dwImageReference(dwMap(content['mainContentImage'])?['staticUrl']),
      programme: programmeId,
      programmeName:
          dwLine(owner?['name']) ?? (programmeTitle == null ? null : dwSplitProgrammeTitle(programmeTitle).name),
    ),
  );
}

Object? _raw(Map<String, dynamic> hit, String field) => dwMap(hit[field])?['raw'];

List<Object?> _list(Object? value) => value is List ? value : [value];
