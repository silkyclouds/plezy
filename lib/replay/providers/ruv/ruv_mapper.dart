import '../../model/replay_title.dart';
import 'ruv_dates.dart';
import 'ruv_ids.dart';
import 'ruv_numbering.dart';

/// Category whose single-episode programmes are films.
const ruvFilmCategory = 'kvikmyndir';

/// The programme id of a card or a programme page. Cards in panels and categories also carry an unrelated `id`.
int? ruvProgramId(Map<String, dynamic> program) => ((program['programID'] ?? program['id']) as num?)?.toInt();

List<Map<String, dynamic>> _episodesOf(Map<String, dynamic> program) {
  final episodes = program['episodes'];
  return episodes is List ? episodes.whereType<Map<String, dynamic>>().toList() : const [];
}

/// Whether RÚV files a programme under films. Some series are filed there too.
bool ruvFiledAsFilm(Map<String, dynamic> program) {
  final categories = program['categories'];
  return categories is List && categories.any((c) => c is Map && c['slug'] == ruvFilmCategory);
}

/// Whether a programme is a film: filed under films with exactly one episode. [program] must list all its
/// episodes (up to two are enough); the single episode a list carries cannot tell a film from a series.
bool ruvIsFilm(Map<String, dynamic> program) => ruvFiledAsFilm(program) && _episodesOf(program).length == 1;

/// A programme as a show, or as a movie when it is a film. Null for radio, and for a programme with no episode:
/// there is nothing to open or play.
ReplayTitle? ruvTitleFromProgram(Map<String, dynamic> program, {required DateTime now}) {
  final id = ruvProgramId(program);
  final episodes = _episodesOf(program);
  if (id == null || episodes.isEmpty || program['format'] == 'radio') return null;
  final title = _text(program['title']) ?? '$id';
  final first = episodes.first;
  final film = ruvIsFilm(program);
  final until = ruvExpiry(first['file_expires']);
  final image = _text(program['image']);
  final portrait = _text(program['portrait_image']);

  return ReplayTitle(
    ref: ruvShowRef(id),
    kind: film ? ReplayKind.movie : ReplayKind.show,
    title: title,
    subtitle: _originalTitle(program, title),
    summary: _text(program['description']) ?? _text(program['short_description']),
    posterUrl: portrait ?? image,
    backdropUrl: image ?? portrait,
    durationSeconds: film ? (first['duration'] as num?)?.toInt() : null,
    genres: _genres(program),
    contentRating: _rating(first['rating']),
    airDate: film ? ruvDateTime(first['firstrun']) : null,
    availableUntil: film ? until : null,
    availability: film && _isExpired(until, now) ? ReplayAvailability.expired : ReplayAvailability.playable,
    childCount: film ? null : 1,
  );
}

/// The single season of a programme, numbered from its title ("Kappsmál II" is season 2, otherwise 1).
ReplayTitle? ruvSeasonFromProgram(Map<String, dynamic> program) {
  final id = ruvProgramId(program);
  final episodes = _episodesOf(program);
  if (id == null || episodes.isEmpty) return null;
  final title = _text(program['title']) ?? '$id';
  final image = _text(program['image']);
  final portrait = _text(program['portrait_image']);
  return ReplayTitle(
    ref: ruvSeasonRef(id),
    kind: ReplayKind.season,
    title: title,
    posterUrl: portrait ?? image,
    backdropUrl: image ?? portrait,
    seasonNumber: ruvSeasonNumber(title) ?? 1,
    childCount: episodes.length,
    showRef: ruvShowRef(id),
    showTitle: title,
  );
}

/// Every episode of a programme, numbered and in ascending order. Episodes without an id are left out.
List<ReplayTitle> ruvEpisodesFromProgram(Map<String, dynamic> program, {required DateTime now}) {
  final id = ruvProgramId(program);
  if (id == null) return const [];
  final showTitle = _text(program['title']) ?? '$id';
  final seasonNumber = ruvSeasonNumber(showTitle) ?? 1;
  final image = _text(program['image']);
  final seen = <String>{};
  final usable = [
    for (final e in _episodesOf(program))
      if (e['id'] is String && seen.add(e['id'] as String)) e,
  ];
  return [
    for (final (:episode, :number) in ruvNumberEpisodes(usable))
      _episode(id, showTitle, seasonNumber, episode, number, image, now),
  ];
}

ReplayTitle _episode(
  int programId,
  String showTitle,
  int seasonNumber,
  Map<String, dynamic> episode,
  int number,
  String? programImage,
  DateTime now,
) {
  final until = ruvExpiry(episode['file_expires']);
  final image = _text(episode['image']) ?? programImage;
  return ReplayTitle(
    ref: ruvEpisodeRef(programId, episode['id'] as String),
    kind: ReplayKind.episode,
    title: _text(episode['title']) ?? showTitle,
    summary: _text(episode['description']),
    posterUrl: image,
    backdropUrl: image,
    durationSeconds: (episode['duration'] as num?)?.toInt(),
    contentRating: _rating(episode['rating']),
    airDate: ruvDateTime(episode['firstrun']),
    availableUntil: until,
    availability: _isExpired(until, now) ? ReplayAvailability.expired : ReplayAvailability.playable,
    seasonNumber: seasonNumber,
    episodeNumber: number,
    showRef: ruvShowRef(programId),
    showTitle: showTitle,
    seasonRef: ruvSeasonRef(programId),
  );
}

/// Titles for a list of programme maps: one card per programme, repeats and unusable entries dropped.
List<ReplayTitle> ruvTitlesFromPrograms(Iterable<Map<String, dynamic>> programs, {required DateTime now}) {
  final seen = <int>{};
  return [
    for (final program in programs)
      if (ruvTitleFromProgram(program, now: now) case final title? when seen.add(ruvProgramId(program)!)) title,
  ];
}

bool _isExpired(DateTime? until, DateTime now) => until != null && until.isBefore(now);

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _originalTitle(Map<String, dynamic> program, String title) {
  final original = _text(program['foreign_title']);
  return original == null || original == title ? null : original;
}

List<String> _genres(Map<String, dynamic> program) {
  final categories = program['categories'];
  if (categories is! List) return const [];
  return [for (final c in categories.whereType<Map<String, dynamic>>()) ?_text(c['title'])];
}

String? _rating(Object? age) => age is num && age > 0 ? '${age.toInt()}+' : null;
