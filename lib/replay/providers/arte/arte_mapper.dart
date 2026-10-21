import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';

const arteSourceId = 'arte';

/// Where an item was found, so episodes know their show and season.
class ArteContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const ArteContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = ArteContext();
}

ReplayRef arteRef(String nativeId) => ReplayRef(arteSourceId, nativeId);

/// Maps one catalogue item (a "teaser" or a program page entry) to a [ReplayTitle], or null for items
/// that cannot be played or opened here: paid store links, external links and teasers without an id.
ReplayTitle? arteTitleFromItem(Map<String, dynamic> item, {ArteContext context = ArteContext.none, DateTime? now}) {
  final kindCode = (item['kind'] as Map?)?['code'] as String?;
  final isCollection = (item['kind'] as Map?)?['isCollection'] == true;
  if (kindCode == 'VOD' || kindCode == 'EXTERNAL') return null;

  final nativeId = _nativeId(item, isCollection);
  if (nativeId == null) return null;

  final info = item['episodeInfo'] as Map<String, dynamic>?;
  final kind = _kindOf(kindCode, isCollection, nativeId, info, item);
  final availability = item['availability'] as Map<String, dynamic>?;
  final seasonNumber = (info?['season'] as num?)?.toInt() ?? context.seasonNumber;

  return ReplayTitle(
    ref: arteRef(nativeId),
    kind: kind,
    title: (item['title'] as String?)?.trim() ?? nativeId,
    subtitle: _nonEmpty(item['subtitle'] as String?),
    summary: _summary(item),
    posterUrl: _imageTemplate(item),
    backdropUrl: _imageTemplate(item),
    logoUrl: _logo(item),
    durationSeconds: (item['duration'] as num?)?.toInt(),
    year: _year(item),
    genres: _genres(item),
    directors: _credits(item, 'REA'),
    cast: _credits(item, 'ACT'),
    contentRating: _rating(item['ageRating']),
    airDate: _date(availability?['start']),
    availableUntil: _date(availability?['end']),
    availability: _availability(availability, now ?? DateTime.now()),
    seasonNumber: seasonNumber,
    episodeNumber: (info?['episode'] as num?)?.toInt(),
    showRef: context.show,
    showTitle: context.showTitle,
    seasonRef: context.season,
  );
}

/// Items of a catalogue zone, without unplayable teasers and without repeats.
List<ReplayTitle> arteTitlesFromZone(Map<String, dynamic> zone, {ArteContext context = ArteContext.none}) {
  final seen = <ReplayRef>{};
  final data = (zone['content'] as Map?)?['data'];
  if (data is! List) return const [];
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>)
        if (arteTitleFromItem(raw, context: context) case final title? when seen.add(title.ref)) title,
  ];
}

/// Rows of a page. Promotional banners, login rows and empty rows are dropped.
List<ReplayRail> arteRailsFromPage(Map<String, dynamic> page) {
  final zones = page['zones'];
  if (zones is! List) return const [];
  final rails = <ReplayRail>[];
  for (final zone in zones.whereType<Map<String, dynamic>>()) {
    if (zone['authenticatedContent'] != null) continue;
    final template = (zone['displayOptions'] as Map?)?['template'] as String? ?? '';
    if (template.contains('event-') || template.contains('newsletter')) continue;
    final titles = arteTitlesFromZone(zone);
    if (titles.isEmpty) continue;
    rails.add(
      ReplayRail(
        id: zone['code'] as String? ?? zone['id'] as String,
        title: (zone['title'] as String?)?.trim() ?? '',
        titles: titles,
        moreBrowseId: (zone['link'] as Map?)?['page'] as String?,
      ),
    );
  }
  return rails;
}

String? _nativeId(Map<String, dynamic> item, bool isCollection) {
  final programId = item['programId'] as String?;
  if (programId != null && programId.isNotEmpty) return programId;
  if (!isCollection) return null;
  final id = item['id'] as String?;
  if (id == null) return null;
  final match = RegExp(r'^(RC-\d+)').firstMatch(id);
  return match?.group(1);
}

ReplayKind _kindOf(
  String? code,
  bool isCollection,
  String nativeId,
  Map<String, dynamic>? info,
  Map<String, dynamic> item,
) {
  if (isCollection) return ReplayKind.show;
  if (code == 'BONUS' || code == 'CLIP' || code == 'TRAILER' || code == 'SHORTS') return ReplayKind.clip;
  final episodeBlock = RegExp(r'^\d+-(\d{3})-').firstMatch(nativeId)?.group(1);
  final isEpisode = (info?['episode'] != null) || (episodeBlock != null && episodeBlock != '000');
  return isEpisode ? ReplayKind.episode : ReplayKind.movie;
}

ReplayAvailability _availability(Map<String, dynamic>? availability, DateTime now) {
  if (availability == null) return ReplayAvailability.playable;
  final end = _date(availability['end']);
  if (end != null && end.isBefore(now)) return ReplayAvailability.expired;
  final start = _date(availability['start']);
  if (availability['hasVideoStreams'] == false || (start != null && start.isAfter(now))) {
    return ReplayAvailability.upcoming;
  }
  return ReplayAvailability.playable;
}

String? _summary(Map<String, dynamic> item) {
  final full = htmlToText(item['fullDescription'] as String?);
  if (full.isNotEmpty) return full;
  final short = htmlToText(item['shortDescription'] as String?);
  return short.isEmpty ? null : short;
}

String? _imageTemplate(Map<String, dynamic> item) => (item['mainImage'] as Map?)?['url'] as String?;

String? _logo(Map<String, dynamic> item) => (item['graphicalTitle'] as Map?)?['url'] as String?;

List<String> _genres(Map<String, dynamic> item) {
  final label = (item['genre'] as Map?)?['label'] as String?;
  return label == null ? const [] : [label];
}

List<String> _credits(Map<String, dynamic> item, String code) {
  final credits = item['credits'];
  if (credits is! List) return const [];
  for (final credit in credits.whereType<Map<String, dynamic>>()) {
    if (credit['code'] == code) return [for (final v in (credit['values'] as List? ?? const [])) v.toString()];
  }
  return const [];
}

int? _year(Map<String, dynamic> item) {
  final values = _credits(item, 'PRODUCTION_YEAR');
  return values.isEmpty ? null : int.tryParse(values.first);
}

String? _rating(Object? age) => age is num && age > 0 ? '${age.toInt()}+' : null;

String? _nonEmpty(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
