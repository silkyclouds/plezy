import '../../model/replay_title.dart';
import 'tvpvod_mapper.dart';

/// Rows of a home or category page. Rows that need an account, grids with no cards and rows that hold only live
/// channels or promo tiles are dropped.
List<ReplayRail> tvpRailsFromSections(Object? sections) {
  if (sections is! List) return const [];
  final rails = <ReplayRail>[];
  for (final section in sections.whereType<Map<String, dynamic>>()) {
    if (section['contentType'] != 'STATIC') continue;
    final items = [
      for (final element in (section['elements'] as List? ?? const []))
        if (element is Map && element['item'] is Map<String, dynamic>) element['item'] as Map<String, dynamic>,
    ];
    final titles = tvpTitlesFromItems(items);
    if (titles.isEmpty) continue;
    rails.add(ReplayRail(id: '${section['id']}', title: _railTitle(section), titles: titles));
  }
  return rails;
}

/// The lead banner is titled with an internal slot name, so it gets a plain label.
String _railTitle(Map<String, dynamic> section) {
  if (section['layout'] == 'BANNER') return 'Polecane';
  final title = (section['title'] as String?)?.trim();
  return title == null || title.isEmpty ? 'TVP VOD' : title;
}
