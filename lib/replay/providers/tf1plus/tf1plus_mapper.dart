import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'tf1plus_images.dart';
import 'tf1plus_json.dart';
import 'tf1plus_numbering.dart';
import 'tf1plus_refs.dart';

/// Where a video was found, so episodes know their show and season.
class Tf1Context {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const Tf1Context({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = Tf1Context();
}

/// Every stream TF1+ hands out is DRM protected, so that is what a list can promise without a playback call.
const tf1ListedAvailability = ReplayAvailability.drmProtected;

/// A programme with exactly one replay is a film or a one-off; anything else is a show.
const _singleReplay = 1;

/// Maps a programme record from a listing, a search or a slug lookup. [detail] is the header from the
/// programme detail route and [video] the newest replay; both enrich the card when given.
ReplayTitle? tf1ProgramTitle(
  Map<String, dynamic> program, {
  Map<String, dynamic>? detail,
  Map<String, dynamic>? video,
  DateTime? now,
}) {
  final slug = tf1Text(program['slug']);
  if (slug == null) return null;
  final decoration = tf1Map(program['decoration']);
  final headline = tf1Map(detail?['decoration']);
  final isMovie = _replayTotal(program) == _singleReplay;
  // Length, rating and expiry belong to one video, so only a film (whose single replay is the title) has them.
  final film = isMovie ? video : null;
  final playing = tf1Map(film?['playingInfos']);

  return ReplayTitle(
    ref: tf1Ref(slug),
    kind: isMovie ? ReplayKind.movie : ReplayKind.show,
    title: tf1Text(program['name']) ?? tf1Text(headline['label']) ?? slug,
    summary: tf1Text(decoration['description']) ?? tf1Text(headline['description']) ?? tf1Text(headline['catchPhrase']),
    posterUrl:
        tf1PickImage(decoration['image'], targetWidth: Tf1ImageWidth.poster) ??
        tf1PickImage(headline['image'], targetWidth: Tf1ImageWidth.poster),
    backdropUrl: _programBackdrop(decoration) ?? _programBackdrop(headline),
    logoUrl:
        tf1PickImage(decoration['logo'], targetWidth: Tf1ImageWidth.logo) ??
        tf1PickImage(headline['logo'], targetWidth: Tf1ImageWidth.logo),
    durationSeconds: (playing['duration'] as num?)?.toInt(),
    year: _programYear(program, headline),
    genres: _genres(program, detail),
    directors: _people(_section(detail, 'ProgramInfoSection')?['directors']),
    cast: _people(_section(detail, 'ProgramInfoSection')?['actors']),
    contentRating: tf1ContentRating(tf1Text(program['rating']) ?? tf1Text(film?['rating'])),
    airDate: _airDate(film),
    availableUntil: _availableUntil(playing, now ?? DateTime.now()),
    availability: tf1ListedAvailability,
    childCount: isMovie || detail == null ? null : _seasonCount(detail),
  );
}

/// Maps a video record from a season list, a programme's video list or a search.
ReplayTitle? tf1VideoTitle(
  Map<String, dynamic> video, {
  Tf1Context context = Tf1Context.none,
  Object? listImage,
  DateTime? now,
}) {
  final id = tf1Text(video['id']);
  if (id == null) return null;
  final decoration = tf1Map(video['decoration']);
  final program = tf1Map(video['program']);
  final programName = tf1Text(decoration['programLabel']) ?? tf1Text(program['name']) ?? context.showTitle;
  final label = tf1Text(decoration['label']) ?? tf1Text(decoration['shortLabel']) ?? '';
  final spelled = tf1NumbersFromLabel(tf1Text(decoration['shortLabel']) ?? label);
  final episode = tf1Positive(video['episode']) ?? spelled.episode;
  final programSlug = tf1Text(program['slug']);
  final playing = tf1Map(video['playingInfos']);
  final type = tf1Text(video['type']);

  return ReplayTitle(
    ref: tf1Ref(id),
    kind: type == null || type == 'REPLAY' ? ReplayKind.episode : ReplayKind.clip,
    title: label.isEmpty ? (programName ?? id) : tf1EpisodeTitle(label, programName: programName, episode: episode),
    subtitle: tf1Text(decoration['subLabel']),
    summary: tf1Text(decoration['description']) ?? tf1Text(decoration['summary']),
    backdropUrl: tf1PickImage(listImage, targetWidth: Tf1ImageWidth.still) ?? tf1PickVideoImage(decoration['images']),
    durationSeconds: (playing['duration'] as num?)?.toInt(),
    contentRating: tf1ContentRating(tf1Text(video['rating'])),
    airDate: _airDate(video),
    availableUntil: _availableUntil(playing, now ?? DateTime.now()),
    availability: tf1ListedAvailability,
    seasonNumber: context.seasonNumber ?? tf1Positive(video['season']) ?? spelled.season,
    episodeNumber: episode,
    showRef: context.show ?? (programSlug == null ? null : tf1Ref(programSlug)),
    showTitle: context.showTitle ?? programName,
    seasonRef: context.season,
  );
}

/// French rating classes as the short labels the rest of the app shows. "Tous publics" has no age.
String? tf1ContentRating(String? csa) => switch (csa) {
  'CSA_ALL' => 'TP',
  'CSA_10' => '10+',
  'CSA_12' => '12+',
  'CSA_16' => '16+',
  'CSA_18' => '18+',
  _ => null,
};

/// The broadcast time. Archive series carry a placeholder first-of-January date, where the time the
/// video reached TF1+ is the only real one.
DateTime? _airDate(Map<String, dynamic>? video) {
  final date = tf1Date(video?['date']);
  final published = tf1Date(video?['published']);
  final isPlaceholder =
      date != null && date.month == 1 && date.day == 1 && published != null && published.year != date.year;
  return isPlaceholder ? published : (date ?? published);
}

/// The API gives days left, not an end date; the end is that many days from now.
DateTime? _availableUntil(Map<String, dynamic> playing, DateTime now) {
  final days = tf1Positive(playing['remainingDays']);
  return days == null ? null : now.toUtc().add(Duration(days: days));
}

String? _programBackdrop(Map<String, dynamic> decoration) =>
    tf1PickImage(decoration['background'], targetWidth: Tf1ImageWidth.backdrop) ??
    tf1PickImage(decoration['thumbnail'], targetWidth: Tf1ImageWidth.backdrop);

int? _replayTotal(Map<String, dynamic> program) => (tf1Map(program['replay'])['total'] as num?)?.toInt();

final _yearBeforeDuration = RegExp(r'^((?:19|20)\d{2})\s*·');

/// Films state their year in the sub label ("2018  ·  2h07"); the plain year field is usually empty.
int? _programYear(Map<String, dynamic> program, Map<String, dynamic> headline) {
  final plain = int.tryParse(tf1Text(program['releaseYear']) ?? '');
  if (plain != null) return plain;
  final fromLabel = _yearBeforeDuration.firstMatch(tf1Text(headline['subLabel']) ?? '')?.group(1);
  return fromLabel == null ? null : int.parse(fromLabel);
}

List<String> _genres(Map<String, dynamic> program, Map<String, dynamic>? detail) {
  final topics = detail?['topics'];
  if (topics is List && topics.isNotEmpty) return [for (final t in topics) t.toString()];
  final details = program['topicsDetails'];
  if (details is List && details.isNotEmpty) {
    return [for (final t in details.whereType<Map>()) ?tf1Text(t['label'])];
  }
  final categories = program['categories'];
  if (categories is! List) return const [];
  return {
    for (final c in categories.whereType<Map>())
      if (c['main'] != true) ?tf1Text(c['label']),
  }.toList();
}

List<String> _people(Object? groups) {
  if (groups is! List) return const [];
  final names = <String>[];
  for (final group in groups.whereType<Map>()) {
    for (final member in (group['members'] as List? ?? const []).whereType<Map>()) {
      final name = [tf1Text(member['firstName']), tf1Text(member['lastName'])].whereType<String>().join(' ');
      if (name.isNotEmpty) names.add(name);
    }
  }
  return names;
}

/// Season lists of a programme: the `lists` of its main content section, empty for films and news.
List<Map<String, dynamic>> tf1SeasonLists(Map<String, dynamic>? detail) {
  final lists = _section(detail, 'MainContentSection')?['lists'];
  return lists is List ? lists.whereType<Map<String, dynamic>>().toList() : const [];
}

/// A show without season lists is presented as one synthetic season.
int _seasonCount(Map<String, dynamic> detail) {
  final lists = tf1SeasonLists(detail).length;
  return lists == 0 ? 1 : lists;
}

Map<String, dynamic>? _section(Map<String, dynamic>? detail, String typename) {
  final sections = detail?['editorialSections'];
  if (sections is! List) return null;
  return sections.whereType<Map<String, dynamic>>().where((s) => s['__typename'] == typename).firstOrNull;
}

/// Programmes of a listing or search page, without repeats: pages overlap and a programme can appear twice.
List<ReplayTitle> tf1ProgramTitles(Object? items) {
  if (items is! List) return const [];
  final seen = <ReplayRef>{};
  return [
    for (final raw in items.whereType<Map<String, dynamic>>())
      if (tf1ProgramTitle(raw) case final title? when seen.add(title.ref)) title,
  ];
}

/// Videos of a search page, without repeats.
List<ReplayTitle> tf1VideoTitles(Object? items) {
  if (items is! List) return const [];
  final seen = <ReplayRef>{};
  return [
    for (final raw in items.whereType<Map<String, dynamic>>())
      if (tf1VideoTitle(raw) case final title? when seen.add(title.ref)) title,
  ];
}
