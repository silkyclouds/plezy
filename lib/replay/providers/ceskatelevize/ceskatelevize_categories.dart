import '../../model/replay_title.dart';
import 'ceskatelevize_text.dart';

/// The top-level genres of the site menu. A menu entry's `categoryId` is the path from the root; its last element is
/// the id every category query takes. Entries without one are plain list pages and cannot be browsed here.
List<ReplayCategory> ceskatelevizeCategories(Map<String, dynamic> data) {
  final menu = data['menu'];
  if (menu is! List) return const [];
  final categories = <ReplayCategory>[];
  for (final entry in menu.whereType<Map<String, dynamic>>()) {
    final path = entry['categoryId'];
    final title = ceskatelevizeLabel(entry['title']);
    if (path is List && path.isNotEmpty && path.last is String && title != null) {
      categories.add(ReplayCategory(id: path.last as String, title: title));
    }
  }
  return categories;
}
