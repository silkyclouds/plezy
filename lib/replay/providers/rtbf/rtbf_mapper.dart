import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import '../../text/html_text.dart';
import 'rtbf_images.dart';
import 'rtbf_numbering.dart';

const rtbfSourceId = 'auvio';

ReplayRef rtbfProgramRef(String programId) => ReplayRef(rtbfSourceId, 'p$programId');

ReplayRef rtbfMediaRef(String mediaId) => ReplayRef(rtbfSourceId, 'm$mediaId');

/// A season is `p<programId>/<key>`. `s<n>` and `y<year>` are tabs of the programme page, `all` is the
/// single tab of a show, and `n<k>` is season k read from the numbers in the episode titles.
ReplayRef rtbfSeasonRef(String programId, String tabKey) => ReplayRef(rtbfSourceId, 'p$programId/$tabKey');

/// Where a media card was found, so an episode knows its show and season.
class RtbfContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  /// Every video of this list is an episode, even when its subtitle carries no number.
  final bool episodes;

  const RtbfContext({this.show, this.showTitle, this.season, this.seasonNumber, this.episodes = false});

  static const none = RtbfContext();
}

/// Turns Auvio cards and pages into [ReplayTitle]s.
///
/// Remembers the poster of every programme card it has seen: a programme page carries only a landscape
/// background, so the poster of an opened show comes from the card it was opened from.
class RtbfMapper {
  final DateTime Function() _now;
  final Map<String, String> _posters = {};

  RtbfMapper(this._now);

  /// A programme or media card from a list, or null for cards that are not titles (categories, channels)
  /// and for audio, which this video app does not offer. [rights] holds verdicts by media id.
  ReplayTitle? card(
    Map<String, dynamic> card, {
    RtbfContext context = RtbfContext.none,
    Map<String, ReplayAvailability> rights = const {},
  }) => switch (card['resourceType']) {
    'PROGRAM' => _programCard(card),
    'MEDIA' || 'MEDIA_PREMIUM' => _media(card, context: context, rights: rights),
    _ => null,
  };

  /// Cards of a list without unusable entries and without repeats.
  List<ReplayTitle> cards(
    Iterable<Object?> raw, {
    RtbfContext context = RtbfContext.none,
    Map<String, ReplayAvailability> rights = const {},
  }) {
    final seen = <ReplayRef>{};
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          if (card(item, context: context, rights: rights) case final title? when seen.add(title.ref)) title,
    ];
  }

  /// A programme page (`pages/emission/{id}`): a show, or a movie for a one-off programme.
  ReplayTitle? programPage(Map<String, dynamic> content, {Map<String, ReplayAvailability> rights = const {}}) {
    final id = _id(content['id']);
    final type = content['type'] as String? ?? '';
    if (id == null || _isAudioProgram(type)) return null;

    final category = (content['category'] as Map?)?['label'] as String?;
    final background = rtbfIllustration(content['background'], rtbfStillSize);
    final media = content['media'];
    if (type == 'STANDALONE' && media is Map<String, dynamic>) {
      final film = _media(media, context: RtbfContext.none, rights: rights, programTitle: content['title'] as String?);
      return film == null ? null : _asProgramMovie(film, id, content, background);
    }
    return ReplayTitle(
      ref: rtbfProgramRef(id),
      kind: type == 'STANDALONE' ? ReplayKind.movie : ReplayKind.show,
      title: _clean(content['title'] as String?) ?? id,
      summary: _text(content['description']),
      posterUrl: _posters[id],
      backdropUrl: background,
      logoUrl: rtbfIllustration(content['logo'], rtbfPosterSize),
      genres: category == null ? const [] : [category],
      childCount: (content['seasonCount'] as num?)?.toInt(),
    );
  }

  /// A media page (`pages/media/{id}`), which also knows its programme, cast and genre.
  ReplayTitle? mediaPage(
    Map<String, dynamic> content, {
    Map<String, ReplayAvailability> rights = const {},
    String? image,
  }) {
    final program = content['program'];
    final programMap = program is Map<String, dynamic> ? program : null;
    final programId = _id(programMap?['id']);
    final inShow = programMap != null && {'SERIE', 'SHOW'}.contains(programMap['type']);
    final context = inShow && programId != null
        ? RtbfContext(
            show: rtbfProgramRef(programId),
            showTitle: _clean(programMap['title'] as String?),
            episodes: true,
          )
        : RtbfContext.none;
    return _media(content, context: context, rights: rights, includeAudio: true, fallbackBackdrop: image);
  }

  ReplayTitle? _programCard(Map<String, dynamic> card) {
    final id = _id(card['id']);
    final type = card['type'] as String? ?? '';
    if (id == null || _isAudioProgram(type)) return null;
    final poster = rtbfIllustration(card['illustration'], rtbfPosterSize);
    if (poster != null) _posters[id] = poster;
    return ReplayTitle(
      ref: rtbfProgramRef(id),
      kind: type == 'STANDALONE' ? ReplayKind.movie : ReplayKind.show,
      title: _clean(card['title'] as String?) ?? id,
      posterUrl: poster,
    );
  }

  ReplayTitle? _media(
    Map<String, dynamic> card, {
    required RtbfContext context,
    required Map<String, ReplayAvailability> rights,
    String? programTitle,
    bool includeAudio = false,
    String? fallbackBackdrop,
  }) {
    final id = _id(card['id']);
    if (id == null) return null;
    final isAudio = card['type'] == 'AUDIO';
    if (isAudio && !includeAudio) return null;

    final numbering = rtbfParseNumbering(title: card['title'] as String?, subtitle: card['subtitle'] as String?);
    final isEpisode = !isAudio && (context.episodes || numbering.isNumbered);
    final kind = isAudio
        ? ReplayKind.clip
        : isEpisode
        ? ReplayKind.episode
        : ReplayKind.movie;

    final programId = _id(card['programId']);
    final show = context.show ?? (isEpisode && programId != null ? rtbfProgramRef(programId) : null);
    final from = _date(card['publishedFrom']);
    final to = _date(card['publishedTo']);
    final tagline = _clean(card['subtitle'] as String?);

    return ReplayTitle(
      ref: rtbfMediaRef(id),
      kind: kind,
      title: isEpisode ? numbering.episodeTitle : (programTitle ?? numbering.showTitle),
      subtitle: isEpisode ? null : tagline,
      summary: _text(card['description']) ?? _text(card['shortDescription']),
      backdropUrl: rtbfIllustration(card['illustration'], rtbfStillSize) ?? fallbackBackdrop,
      durationSeconds: (card['duration'] as num?)?.toInt(),
      genres: _genres(card),
      directors: _directors(card),
      cast: _cast(card),
      contentRating: _clean(card['rating'] as String?),
      airDate: from,
      availableUntil: to,
      availability: _availability(card, from, to, rights[id]),
      seasonNumber: isEpisode ? _seasonNumber(context, numbering) : null,
      episodeNumber: isEpisode ? numbering.episode : null,
      showRef: show,
      showTitle: isEpisode ? (context.showTitle ?? numbering.showTitle) : null,
      seasonRef: context.season,
    );
  }

  ReplayTitle _asProgramMovie(ReplayTitle film, String programId, Map<String, dynamic> content, String? background) {
    return ReplayTitle(
      ref: rtbfProgramRef(programId),
      kind: ReplayKind.movie,
      title: film.title,
      subtitle: film.subtitle,
      summary: _text(content['description']) ?? film.summary,
      posterUrl: _posters[programId],
      backdropUrl: background ?? film.backdropUrl,
      logoUrl: film.logoUrl,
      durationSeconds: film.durationSeconds,
      genres: film.genres.isNotEmpty
          ? film.genres
          : [if ((content['category'] as Map?)?['label'] case final String label) label],
      directors: film.directors,
      cast: film.cast,
      contentRating: film.contentRating,
      airDate: film.airDate,
      availableUntil: film.availableUntil,
      availability: film.availability,
    );
  }

  ReplayAvailability _availability(
    Map<String, dynamic> card,
    DateTime? from,
    DateTime? to,
    ReplayAvailability? verdict,
  ) {
    final now = _now();
    if (to != null && to.isBefore(now)) return ReplayAvailability.expired;
    if (from != null && from.isAfter(now)) return ReplayAvailability.upcoming;
    if (card['resourceType'] == 'MEDIA_PREMIUM' || card['isPremium'] == true) return ReplayAvailability.loginRequired;
    return verdict ?? ReplayAvailability.playable;
  }
}

/// A show with episode numbers but no season marker is read as season 1, so every episode has a season.
int? _seasonNumber(RtbfContext context, RtbfNumbering numbering) =>
    context.seasonNumber ?? numbering.season ?? (context.episodes || numbering.episode != null ? 1 : null);

bool _isAudioProgram(String type) => type.startsWith('AUDIO_');

/// Ids are numbers in some responses and strings in others, and empty strings stand for "none".
String? _id(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty || text == '0' ? null : text;
}

String? _clean(String? text) {
  final value = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value == null || value.isEmpty ? null : value;
}

String? _text(Object? text) {
  if (text is! String) return null;
  final value = htmlToText(text);
  return value.isEmpty ? null : value;
}

DateTime? _date(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;

List<String> _genres(Map<String, dynamic> card) {
  final label = _clean(card['categoryLabel'] as String?) ?? _clean((card['category'] as Map?)?['label'] as String?);
  return label == null ? const [] : [label];
}

const _directorRoles = {'Réalisateur', 'Réalisatrice'};

const _crewRoles = {
  'Réalisateur',
  'Réalisatrice',
  'Producteur',
  'Productrice',
  'Scénariste',
  'Compositeur',
  'Compositrice',
  'Auteur',
  'Autrice',
};

List<String> _directors(Map<String, dynamic> card) {
  final casting = card['casting'];
  if (casting is! List) return const [];
  return [
    for (final entry in casting.whereType<Map<String, dynamic>>())
      if (_directorRoles.contains(entry['role']) && entry['name'] is String) entry['name'] as String,
  ];
}

List<String> _cast(Map<String, dynamic> card) {
  final casting = card['casting'];
  if (casting is! List) return const [];
  return [
    for (final entry in casting.whereType<Map<String, dynamic>>())
      if (entry['name'] is String && !_crewRoles.contains(entry['role'])) entry['name'] as String,
  ];
}
