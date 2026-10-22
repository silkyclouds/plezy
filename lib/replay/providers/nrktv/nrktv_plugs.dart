import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_dates.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_text.dart';

/// Layouts that are promotions, not rows of titles.
const _promoLayouts = {'inlineHero'};

/// The rows of a page (front page or category). Sections that only ask the viewer to log in, promotions and rows
/// without a name are left out.
List<ReplayRail> nrkRailsFromPage(Map<String, dynamic> page) {
  final rails = <ReplayRail>[];
  for (final section in (page['sections'] as List? ?? const []).whereType<Map>()) {
    final included = section['included'];
    if (section['type'] != 'included' || included is! Map) continue;
    final title = (included['title'] as String? ?? '').trim();
    if (title.isEmpty || _promoLayouts.contains(included['displayContract']) || _asksForLogin(title)) continue;
    final titles = nrkTitlesFromPlugs(included['plugs']);
    if (titles.isNotEmpty) rails.add(ReplayRail(id: '${section['id']}', title: title, titles: titles));
  }
  return rails;
}

/// Every distinct title of a list of plugs, in order.
List<ReplayTitle> nrkTitlesFromPlugs(Object? plugs) {
  final seen = <ReplayRef>{};
  return [
    for (final plug in (plugs as List? ?? const []).whereType<Map>())
      if (_titleOf(plug) case final title? when seen.add(title.ref)) title,
  ];
}

bool _asksForLogin(String title) => title.toLowerCase().contains('logg deg på');

ReplayTitle? _titleOf(Map plug) {
  final content = plug['displayContractContent'] as Map? ?? const {};
  final title = (content['contentTitle'] as String? ?? '').trim();
  if (title.isEmpty) return null;
  final description = nrkPlainText(content['description'] as String? ?? '');
  final backdrop = nrkImageRef(content['displayContractImage'] ?? content['fallbackImage']);
  final logo = nrkImageRef(content['logoImage']);
  return switch (plug['targetType']) {
    'series' => _series(plug['series'], title, description, backdrop, logo),
    'episode' => _episode(plug['episode'], title, description, backdrop),
    'standaloneProgram' => _program(plug['standaloneProgram'], title, description, backdrop),
    _ => null,
  };
}

ReplayTitle? _series(Object? target, String title, String description, String? backdrop, String? logo) {
  final id = target is Map ? target['seriesId'] : null;
  if (id is! String || id.isEmpty) return null;
  return ReplayTitle(
    ref: nrkShowRef(id),
    kind: ReplayKind.show,
    title: title,
    summary: description.isEmpty ? null : description,
    backdropUrl: backdrop,
    logoUrl: logo,
  );
}

ReplayTitle? _episode(Object? target, String title, String description, String? backdrop) {
  final id = target is Map ? target['programId'] : null;
  if (target is! Map || id is! String || id.isEmpty) return null;
  final seriesId = target['seriesId'];
  final seasonId = target['seasonId'];
  final hasShow = seriesId is String && seriesId.isNotEmpty;
  return ReplayTitle(
    ref: nrkProgramRef(id),
    kind: ReplayKind.episode,
    title: title,
    summary: description.isEmpty ? null : description,
    backdropUrl: backdrop,
    durationSeconds: nrkParseDuration(target['duration'])?.inSeconds,
    showRef: hasShow ? nrkShowRef(seriesId) : null,
    seasonRef: hasShow && seasonId is String && seasonId.isNotEmpty ? nrkSeasonRef(seriesId, seasonId) : null,
  );
}

ReplayTitle? _program(Object? target, String title, String description, String? backdrop) {
  final id = target is Map ? target['programId'] : null;
  if (target is! Map || id is! String || id.isEmpty) return null;
  final age = (target['legalAge'] as Map?)?['displayValue'];
  return ReplayTitle(
    ref: nrkProgramRef(id),
    kind: ReplayKind.movie,
    title: title,
    summary: description.isEmpty ? null : description,
    backdropUrl: backdrop,
    durationSeconds: nrkParseDuration(target['duration'])?.inSeconds,
    contentRating: age is String && age.isNotEmpty ? age : null,
  );
}
