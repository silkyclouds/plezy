import '../../model/replay_title.dart';
import 'rtbf_bff.dart';

/// The path of a section that sells subscriptions and holds nothing playable here.
const _paidSection = '/premium';

final _safeBrowsePath = RegExp(r'^[A-Za-z0-9_\-/]+$');

/// Whether [categoryId] is a page path this provider handed out, so it cannot reach other BFF routes.
bool isRtbfCategoryId(String categoryId) => _safeBrowsePath.hasMatch(categoryId) && !categoryId.contains('..');

/// The sections of the website's category row. A category id is its page path without the leading slash,
/// such as `categorie/series-35` or `kids`, which is also the BFF page to open.
Future<List<ReplayCategory>> rtbfCategories(RtbfBff bff) async {
  final home = await bff.get('pages/home');
  final widgets = (home['data'] as Map?)?['widgets'];
  if (widgets is! List) return const [];
  final row = widgets.whereType<Map<String, dynamic>>().where((w) => w['type'] == 'CATEGORY_LIST').firstOrNull;
  final path = row?['contentPath'];
  if (path is! String) return const [];

  final content = ((await bff.get(path))['data'] as Map?)?['content'];
  if (content is! List) return const [];
  return [
    for (final card in content.whereType<Map<String, dynamic>>())
      if (card['resourceType'] == 'CATEGORY' && card['path'] is String && card['path'] != _paidSection)
        ReplayCategory(
          id: (card['path'] as String).replaceFirst('/', ''),
          title: (card['label'] as String? ?? '').trim(),
        ),
  ];
}
