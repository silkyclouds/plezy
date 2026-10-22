import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'svtplay_dates.dart';
import 'svtplay_images.dart';
import 'svtplay_numbering.dart';
import 'svtplay_restrictions.dart';

const svtPlaySourceId = 'svtplay';

ReplayRef svtPlayRef(String nativeId) => ReplayRef(svtPlaySourceId, nativeId);

/// Where an item was found, so an episode knows its show and season.
class SvtContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const SvtContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = SvtContext();
}

const _showTypes = {'TvSeries', 'TvShow', 'KidsTvShow'};

// Rows that hold no playable catalogue: the viewer's own state, live placeholders, future programmes.
const _skippedRows = {'live', 'upcoming', 'keepWatching', 'favorites', 'personalRecommendations'};

const _accessibilityGenres = {'Tydligare tal', 'Uppläst undertext'};
final _internalLabel = RegExp(r'^[A-Z]\d? - ');
final _emphasis = RegExp(r'</?em>');

/// Turns catalogue items into neutral titles and records each one's geo and DRM flags as it goes by.
class SvtPlayMapper {
  final SvtPlayRestrictions _restrictions;
  final DateTime Function() _now;

  SvtPlayMapper(this._restrictions, this._now);

  /// One catalogue item as a show, movie or episode, or null for clips and other kinds the app does not list.
  /// [number] overrides the episode number the item states.
  ReplayTitle? title(Map<String, dynamic> item, {SvtContext context = SvtContext.none, int? number}) {
    final kind = switch (item['__typename']) {
      final String type when _showTypes.contains(type) => ReplayKind.show,
      'Single' => ReplayKind.movie,
      'Episode' => ReplayKind.episode,
      _ => null,
    };
    final id = item['svtId'] as String?;
    if (kind == null || id == null) return null;

    final ref = svtPlayRef(id);
    final restrictions = item['restrictions'] as Map?;
    final drm = restrictions?['drmCopyProtection'] == true;
    _restrictions.note(ref, swedenOnly: restrictions?['onlyAvailableInSweden'] == true, drm: drm);

    final images = item['images'] as Map?;
    final wide = svtPlayImageReference(images?['wide']);
    final parent = item['parent'] as Map?;
    final parentId = parent?['svtId'] as String?;
    final isEpisode = kind == ReplayKind.episode;

    return ReplayTitle(
      ref: ref,
      kind: kind,
      title: _clean(isEpisode ? svtEpisodeTitle(item) : item['name'] as String?) ?? id,
      summary: _nonEmpty(item['longDescription'] as String?) ?? _nonEmpty(item['shortDescription'] as String?),
      posterUrl: svtPlayImageReference(images?['portrait']) ?? wide,
      backdropUrl: wide,
      logoUrl: svtPlayImageReference(images?['logotype']),
      durationSeconds: (item['duration'] as num?)?.toInt(),
      year: (item['productionYear'] as num?)?.toInt(),
      genres: _genres(item['genres']),
      airDate: svtDate(item['validFrom']),
      availableUntil: svtDate(item['validTo']),
      availability: _availability(item, drm),
      seasonNumber: context.seasonNumber,
      episodeNumber: isEpisode ? number ?? svtEpisodeNumber(item) : null,
      showRef: context.show ?? (isEpisode && parentId != null ? svtPlayRef(parentId) : null),
      showTitle: context.showTitle ?? (isEpisode ? _clean(parent?['name'] as String?) : null),
      seasonRef: context.season,
    );
  }

  /// The title a details page describes, with the page's own artwork (it adds the title logo).
  ReplayTitle? fromDetails(Map<String, dynamic> page, {SvtContext context = SvtContext.none}) {
    final item = page['item'];
    if (item is! Map<String, dynamic>) return null;
    return title({...item, 'images': page['images']}, context: context);
  }

  /// A season is as restricted as its show.
  void inheritRestrictions(ReplayRef season, ReplayRef show) => _restrictions.inherit(season, show);

  /// Items of a list in order, without repeats. Items of unlisted kinds are skipped.
  List<ReplayTitle> titles(Iterable<Object?> items) {
    final seen = <ReplayRef>{};
    return [
      for (final raw in items)
        if (raw is Map<String, dynamic>)
          if (title(raw) case final found? when seen.add(found.ref)) found,
    ];
  }

  /// Items of rows or search hits (`{item: {...}}`, possibly under `teaser`).
  List<ReplayTitle> titlesOfEntries(Iterable<Object?> entries) => titles([
    for (final entry in entries)
      if (entry is Map) (entry['teaser'] is Map ? (entry['teaser'] as Map)['item'] : entry['item']),
  ]);

  /// Rows of a page. Personal, live and upcoming rows are dropped, and so are episodes no longer or not yet playable.
  List<ReplayRail> rails(Object? selections) {
    if (selections is! List) return const [];
    final rails = <ReplayRail>[];
    for (final row in selections.whereType<Map<String, dynamic>>()) {
      if (_skippedRows.contains(row['selectionType'])) continue;
      final titles = [
        for (final t in titlesOfEntries(row['items'] as List? ?? const []))
          if (t.availability != ReplayAvailability.upcoming && t.availability != ReplayAvailability.expired) t,
      ];
      if (titles.isEmpty) continue;
      rails.add(ReplayRail(id: row['id'] as String, title: (row['name'] as String? ?? '').trim(), titles: titles));
    }
    return rails;
  }

  ReplayAvailability _availability(Map<String, dynamic> item, bool drm) {
    if (drm) return ReplayAvailability.drmProtected;
    final until = svtDate(item['validTo']);
    if (until != null && until.isBefore(_now())) return ReplayAvailability.expired;
    final from = svtDate(item['validFrom']);
    if (from != null && from.isAfter(_now())) return ReplayAvailability.upcoming;
    return ReplayAvailability.playable;
  }

  List<String> _genres(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final genre in raw.whereType<Map>())
        if (_clean(genre['name'] as String?) case final name? when _isGenre(name)) name,
    ];
  }

  bool _isGenre(String name) => !_accessibilityGenres.contains(name) && !_internalLabel.hasMatch(name);
}

String? _clean(String? text) => _nonEmpty(text?.replaceAll(_emphasis, ''));

String? _nonEmpty(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
