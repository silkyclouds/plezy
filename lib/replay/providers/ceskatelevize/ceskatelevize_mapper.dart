import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ceskatelevize_availability.dart';
import 'ceskatelevize_numbering.dart';
import 'ceskatelevize_refs.dart';
import 'ceskatelevize_text.dart';

/// A season of the show being listed, as episodes need to name it.
typedef CeskaTelevizeSeasonInfo = ({ReplayRef ref, int number});

/// What episodes of one show learn from the request that listed them.
class CeskaTelevizeShowContext {
  final ReplayRef show;
  final String showTitle;

  /// Seasons by the broadcaster's season id.
  final Map<String, CeskaTelevizeSeasonInfo> seasons;

  /// The season of an episode that names none: the synthetic one, or the one being listed.
  final CeskaTelevizeSeasonInfo? fallback;

  const CeskaTelevizeShowContext({required this.show, required this.showTitle, this.seasons = const {}, this.fallback});
}

/// Turns the broadcaster's programme and episode objects into neutral titles.
class CeskaTelevizeMapper {
  final DateTime Function() _clock;

  CeskaTelevizeMapper({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// A programme from a listing, a card, a search hit or the show header. A film becomes a movie unless [asShow]
  /// keeps it a show, which is how its single episode is reached through seasons.
  ReplayTitle? programme(Map<String, dynamic> p, {bool asShow = false}) {
    final sidp = _digits(p['sidp']) ?? _digits(p['id']);
    if (sidp == null) return null;
    final extra = _map(p['programme']);
    final isFilm = !asShow && (p['showType'] ?? extra['showType']) == 'movie';
    final images = _map(p['images']);
    final backdrop = _url(images['card']) ?? _url(p['imageUrl']);
    final credits = ceskatelevizeCredits(p['creators'] as String?);
    final label = ceskatelevizeLabel(p['durationText']);
    final seasons = p['seasons'];

    return ReplayTitle(
      ref: isFilm ? ceskatelevizeFilmRef(sidp) : ceskatelevizeShowRef(sidp),
      kind: isFilm ? ReplayKind.movie : ReplayKind.show,
      title: ceskatelevizeLabel(p['title']) ?? sidp,
      summary: ceskatelevizeBody(p['description']) ?? ceskatelevizeBody(p['shortDescription']),
      posterUrl: _url(images['cardPortrait']) ?? backdrop,
      backdropUrl: backdrop,
      logoUrl: _url(images['logo']),
      durationSeconds: isFilm ? ceskatelevizeDurationSeconds(label) : null,
      year: int.tryParse('${p['year'] ?? extra['year'] ?? ''}'),
      genres: _genres(p),
      directors: credits.directors,
      cast: credits.cast,
      availableUntil: _until(p['availability'] ?? extra['availability']),
      availability: _availability(p, extra),
      childCount: seasons is List ? (seasons.isEmpty ? 1 : seasons.length) : null,
    );
  }

  /// An episode from a season listing, a search hit or a home card.
  ReplayTitle? episode(Map<String, dynamic> item, {CeskaTelevizeShowContext? context}) {
    final idec = _digits(item['idec']) ?? _digits(item['id']);
    if (idec == null) return null;
    final raw = ceskatelevizeLabel(item['title']) ?? idec;
    final named = ceskatelevizeEpisodeName(raw);
    final sidp = _digits(item['showId']) ?? _digits(item['sidp']);
    final season = _seasonOf(item, context);
    final labels = _map(item['cardLabels']);
    final date = _map(item['date']);
    final images = _map(item['images']);

    return ReplayTitle(
      ref: ceskatelevizeEpisodeRef(idec),
      kind: ReplayKind.episode,
      title: named.name,
      summary: ceskatelevizeBody(item['description']),
      backdropUrl: _url(images['card']) ?? _url(item['previewImage']),
      durationSeconds:
          (item['duration'] as num?)?.toInt() ?? ceskatelevizeDurationSeconds(labels['bottomRight'] as String?),
      genres: _genres(item),
      airDate: DateTime.tryParse('${date['datetime'] ?? ''}')?.toUtc(),
      availableUntil: ceskatelevizeAvailableUntil(labels['topLeft'] as String?, _clock()),
      seasonNumber: season?.number,
      episodeNumber: named.number,
      showRef: sidp == null ? context?.show : ceskatelevizeShowRef(sidp),
      showTitle: ceskatelevizeLabel(item['showTitle']) ?? context?.showTitle,
      seasonRef: season?.ref,
    );
  }

  CeskaTelevizeSeasonInfo? _seasonOf(Map<String, dynamic> item, CeskaTelevizeShowContext? context) {
    if (context == null) return null;
    final groups = item['groups'];
    final ids = [
      if (item['season'] is Map<String, dynamic>) (item['season'] as Map<String, dynamic>)['id'],
      if (groups is List)
        for (final g in groups.whereType<Map<String, dynamic>>()) g['id'],
    ];
    for (final id in ids) {
      final known = context.seasons[id];
      if (known != null) return known;
    }
    return context.fallback;
  }

  ReplayAvailability _availability(Map<String, dynamic> p, Map<String, dynamic> extra) {
    final availability = p['availability'] ?? extra['availability'];
    final noRights = p['isPlayable'] == false || p['playable'] == false;
    final withdrawn = availability is Map && availability['isAvailable'] == false;
    return noRights || withdrawn ? ReplayAvailability.expired : ReplayAvailability.playable;
  }

  DateTime? _until(Object? availability) {
    if (availability is! Map) return null;
    final text = availability['textLong'] ?? availability['textShort'];
    return text is String ? ceskatelevizeAvailableUntil(text, _clock()) : null;
  }

  /// Genres of the finest level the card gives: a tree (header) drops its roots, a flat list stays as it is.
  List<String> _genres(Map<String, dynamic> p) {
    final tree = p['flatGenres'];
    final flat = tree is List ? tree : p['genres'];
    if (flat is! List) return const [];
    final entries = flat.whereType<Map<String, dynamic>>().toList();
    final leaves = tree is List ? entries.where((g) => g['parent'] != null).toList() : entries;
    return [for (final g in leaves.isEmpty ? entries : leaves) ?ceskatelevizeLabel(g['title'])];
  }

  Map<String, dynamic> _map(Object? value) => value is Map<String, dynamic> ? value : const <String, dynamic>{};

  String? _digits(Object? value) => value is String && RegExp(r'^\d+$').hasMatch(value) ? value : null;

  String? _url(Object? value) => value is String && value.isNotEmpty ? value : null;
}
