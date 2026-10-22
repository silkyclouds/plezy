import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_item.dart';
import 'ardmediathek_json.dart';
import 'ardmediathek_numbering.dart';
import 'ardmediathek_refs.dart';
import 'ardmediathek_versions.dart';

// Base64 of "crid://arte.tv/": ARTE content the gateway lists is left to the ARTE provider.
const _arteIdPrefix = 'Y3JpZDovL2FydGUudHYv';

const _seriesCore = 'SEASON_SERIES';
const _infiniteCore = 'INFINITE_SERIES';
const _singleCore = 'SINGLE';

/// Where a card was found, so an episode knows its show and season.
class ArdContext {
  final ReplayRef? show;
  final String? showTitle;
  final ReplayRef? season;
  final int? seasonNumber;

  const ArdContext({this.show, this.showTitle, this.season, this.seasonNumber});

  static const none = ArdContext();
}

/// The show a card says it belongs to.
typedef _ParentShow = ({String id, String? title, String? core});

/// Season numbers of a show, from the `availableSeasons` list of strings, in order and without repeats.
List<int> ardSeasonNumbers(Object? availableSeasons) {
  if (availableSeasons is! List) return const [];
  return ({for (final entry in availableSeasons) ?ardInt(entry)}.toList()..sort());
}

/// Maps one card of a row, list or search result. Null for everything that is not a show or a video this
/// provider can open: pages, live channels, banners, ARTE content, copies in another version, login-only videos.
ReplayTitle? ardTitleFromTeaser(Map<String, dynamic> teaser, {ArdContext context = ArdContext.none, DateTime? now}) {
  if (_isArte(teaser) || teaser['blockedByLoginOnly'] == true || ardIsAlternateVersion(teaser)) return null;
  final clock = now ?? DateTime.now();
  return switch (teaser['type']) {
    'show' => _showFromTeaser(teaser),
    'ondemand' || 'poster' => _videoFromTeaser(teaser, context, clock),
    _ => null,
  };
}

/// The show behind a grouping page, or null for ARTE content.
ReplayTitle? ardShowFromGrouping(Map<String, dynamic> page, String id) {
  final title = ardText(page['title']);
  if (title == null || _isArte(page) || id.startsWith(_arteIdPrefix)) return null;
  final images = ardMap(page['images']);
  return ReplayTitle(
    ref: ardShowRef(id),
    kind: ReplayKind.show,
    title: title,
    summary: _plain(ardText(page['synopsis'])),
    posterUrl: _image(images, 'aspect3x4'),
    backdropUrl: _image(images, 'aspect16x9'),
  );
}

/// The video behind an item page, with the synopsis the cards lack.
ReplayTitle? ardTitleFromItemPage(Map<String, dynamic> page, String id, ArdItemFacts facts, {DateTime? now}) {
  final widget = ardMaps(page['widgets']).firstOrNull;
  final headline = ardText(widget?['title']);
  if (widget == null || headline == null || _isArte(widget)) return null;
  final meta = ardMap(ardMap(ardMap(widget['mediaCollection'])?['embedded'])?['meta']);
  return _video(
    _VideoFields(
      id: id,
      headline: headline,
      core: null,
      show: _parentShow(ardMap(widget['show'])),
      backdrop: ardText(ardMap(widget['image'])?['src']),
      duration: ardInt(meta?['durationSeconds']),
      summary: _plain(ardText(widget['synopsis'])),
      airDate: ardDate(widget['broadcastedOn']),
      availableUntil: ardDate(widget['availableTo']),
      rating: ardText(widget['maturityContentRating']),
      gate: facts.availability,
    ),
    ArdContext.none,
    now ?? DateTime.now(),
  );
}

ReplayTitle? _showFromTeaser(Map<String, dynamic> teaser) {
  final link = ardLinkTarget(teaser);
  final headline = _headline(teaser);
  if (link == null || link.kind != 'grouping' || headline == null || link.id.startsWith(_arteIdPrefix)) return null;
  final parts = ardSplitTitle(headline);
  final seasons = ardSeasonNumbers(teaser['availableSeasons']);
  final images = ardMap(teaser['images']);
  return ReplayTitle(
    ref: ardShowRef(link.id),
    kind: ReplayKind.show,
    title: parts.title,
    subtitle: parts.subtitle,
    posterUrl: _image(images, 'aspect3x4'),
    backdropUrl: _image(images, 'aspect16x9'),
    childCount: seasons.isEmpty ? null : seasons.length,
  );
}

ReplayTitle? _videoFromTeaser(Map<String, dynamic> teaser, ArdContext context, DateTime now) {
  final link = ardLinkTarget(teaser);
  final headline = _headline(teaser);
  if (link == null || link.kind != 'item' || headline == null || link.id.startsWith(_arteIdPrefix)) return null;
  final images = ardMap(teaser['images']);
  return _video(
    _VideoFields(
      id: link.id,
      headline: headline,
      core: ardText(teaser['coreAssetType']),
      show: _parentShow(ardMap(teaser['show'])),
      poster: _image(images, 'aspect3x4'),
      backdrop: _image(images, 'aspect16x9'),
      duration: ardInt(teaser['duration']),
      airDate: ardDate(teaser['broadcastedOn']),
      availableUntil: ardDate(teaser['availableTo']),
      rating: ardText(teaser['maturityContentRating']),
    ),
    context,
    now,
  );
}

class _VideoFields {
  final String id;
  final String headline;
  final String? core;
  final _ParentShow? show;
  final String? poster;
  final String? backdrop;
  final int? duration;
  final String? summary;
  final DateTime? airDate;
  final DateTime? availableUntil;
  final String? rating;
  final ReplayAvailability gate;

  const _VideoFields({
    required this.id,
    required this.headline,
    required this.core,
    required this.show,
    this.poster,
    this.backdrop,
    this.duration,
    this.summary,
    this.airDate,
    this.availableUntil,
    this.rating,
    this.gate = ReplayAvailability.playable,
  });
}

ReplayTitle _video(_VideoFields f, ArdContext context, DateTime now) {
  final numbers = ardEpisodeTitle(f.headline);
  final parts = ardSplitTitle(numbers.title);
  // A film is the only video of its own SINGLE grouping, so it has no show to belong to.
  final parent = f.show?.core == _singleCore ? null : f.show;
  final isClip = f.core?.startsWith('EXTRA_') ?? false;
  final kind = isClip
      ? ReplayKind.clip
      : (parent != null || numbers.episode != null || numbers.season != null ? ReplayKind.episode : ReplayKind.movie);

  final showRef = context.show ?? (parent == null ? null : ardShowRef(parent.id));
  final seasonRef = context.season ?? (kind == ReplayKind.episode ? _seasonRefOf(parent, numbers.season) : null);
  final inAllVideos = seasonRef != null && seasonRef.nativeId.endsWith('/$ardAllVideosSeason');
  final expired = f.availableUntil != null && f.availableUntil!.isBefore(now);

  return ReplayTitle(
    ref: ardItemRef(f.id),
    kind: kind,
    title: parts.title,
    subtitle: parts.subtitle,
    summary: f.summary,
    posterUrl: f.poster,
    backdropUrl: f.backdrop,
    durationSeconds: f.duration,
    contentRating: _rating(f.rating),
    airDate: f.airDate,
    availableUntil: f.availableUntil,
    availability: expired ? ReplayAvailability.expired : _titleAvailability(f.gate),
    seasonNumber: numbers.season ?? context.seasonNumber ?? (inAllVideos ? 1 : null),
    episodeNumber: numbers.episode,
    showRef: showRef,
    showTitle: context.showTitle ?? parent?.title,
    seasonRef: seasonRef,
  );
}

// An episode of a numbered series belongs to the season its label names. Series without numbered seasons keep
// every video in one synthetic season.
ReplayRef? _seasonRefOf(_ParentShow? show, int? season) {
  if (show == null) return null;
  if (show.core == _infiniteCore) return ardSeasonRef(show.id, ardAllVideosSeason);
  if (show.core == _seriesCore && season != null) return ardSeasonRef(show.id, '$season');
  return null;
}

// A page that offers no streams for a reason the viewer can act on shows that reason on its card. Pages that are
// merely unreadable stay playable: a card is never greyed out on a guess.
ReplayAvailability _titleAvailability(ReplayAvailability gate) =>
    gate == ReplayAvailability.unknown ? ReplayAvailability.playable : gate;

_ParentShow? _parentShow(Map<String, dynamic>? show) {
  if (show == null) return null;
  final crid = ardText(show['id']);
  final id = ardText(ardMap(show['self'])?['id']) ?? (crid != null && !crid.startsWith('crid:') ? crid : null);
  if (id == null || id.startsWith(_arteIdPrefix)) return null;
  return (id: id, title: ardText(show['title']), core: ardText(show['coreAssetType']));
}

bool _isArte(Map<String, dynamic> card) =>
    ardText(ardMap(card['publicationService'])?['partner'])?.toLowerCase() == 'arte' ||
    (ardText(card['id'])?.startsWith(_arteIdPrefix) ?? false);

String? _headline(Map<String, dynamic> teaser) =>
    ardText(teaser['longTitle']) ?? ardText(teaser['mediumTitle']) ?? ardText(teaser['shortTitle']);

String? _image(Map<String, dynamic>? images, String ratio) => ardText(ardMap(images?[ratio])?['src']);

String? _rating(String? raw) {
  final age = RegExp(r'^FSK\s*(\d+)$', caseSensitive: false).firstMatch(raw ?? '')?.group(1);
  return age == null ? null : 'FSK $age';
}

String? _plain(String? text) => text?.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
