import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'ardmediathek_json.dart';
import 'ardmediathek_mapper.dart';

// Rows that carry navigation or promotion rather than programmes.
const _skippedWidgets = {'banner', 'navigation', 'top_navigation'};
const _widgetsPath = '/page-gateway/widgets/';

/// Cards of one row or search result, without repeats and without what cannot be opened.
List<ReplayTitle> ardTitlesFromWidget(Map<String, dynamic> widget, {ArdContext context = ArdContext.none}) {
  final seen = <ReplayRef>{};
  return [
    for (final teaser in ardMaps(widget['teasers']))
      if (ardTitleFromTeaser(teaser, context: context) case final title? when seen.add(title.ref)) title,
  ];
}

/// The rows of a landing or category page that hold programmes.
List<ReplayRail> ardRailsFromPage(Map<String, dynamic> page) {
  final rails = <ReplayRail>[];
  for (final widget in ardMaps(page['widgets'])) {
    if (_skippedWidgets.contains(widget['type'])) continue;
    final titles = ardTitlesFromWidget(widget);
    if (titles.isEmpty) continue;
    final title = ardText(widget['title']) ?? '';
    rails.add(
      ReplayRail(
        id: ardText(widget['id']) ?? title,
        title: title,
        titles: titles,
        moreBrowseId: _hasMore(widget) ? ardBrowseId(widget) : null,
      ),
    );
  }
  return rails;
}

/// The path of a row below `/widgets/`, which `listing` fetches page by page. Null when the row has no link.
String? ardBrowseId(Map<String, dynamic> widget) {
  final href = ardText(ardMap(ardMap(widget['links'])?['self'])?['href']);
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null) return null;
  final at = uri.path.indexOf(_widgetsPath);
  if (at < 0) return null;
  final path = uri.path.substring(at + _widgetsPath.length);
  // Region rows keep a `{regionId}` placeholder in their path and cannot be fetched as they are.
  return path.contains('{') ? null : path;
}

bool _hasMore(Map<String, dynamic> widget) {
  final total = ardInt(ardMap(widget['pagination'])?['totalElements']) ?? 0;
  return total > ardMaps(widget['teasers']).length;
}
