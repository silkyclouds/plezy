import 'lrt_models.dart';
import 'lrt_refs.dart';

final _link = RegExp(r'<a\b[^>]*tag-list-block__link[^>]*>(.*?)</a>', dotAll: true);
final _href = RegExp(r'''href="([^"]*)"''');
final _titleAttribute = RegExp(r'''title="([^"]*)"''');
final _tags = RegExp(r'<[^>]+>');
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

const _named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '};

/// Programmes of the A to Z index page, in the page's order. Links that do not point at a programme are ignored.
List<LrtProgramme> parseLrtProgrammeIndex(Object? html) {
  if (html is! String) return const [];
  final seen = <String>{};
  final programmes = <LrtProgramme>[];
  for (final match in _link.allMatches(html)) {
    final tag = match.group(0)!;
    final slug = lrtShowSlugOf(_href.firstMatch(tag)?.group(1));
    final title = _title(tag, match.group(1) ?? '');
    if (slug == null || title.isEmpty || !seen.add(slug)) continue;
    programmes.add(LrtProgramme(slug: slug, title: title));
  }
  return programmes;
}

String _title(String tag, String inner) {
  final attribute = _titleAttribute.firstMatch(tag)?.group(1);
  final raw = attribute != null && attribute.trim().isNotEmpty ? attribute : inner.replaceAll(_tags, '');
  return _unescape(raw).trim();
}

String _unescape(String text) => text.replaceAllMapped(_entity, (m) {
  final name = m.group(1)!;
  if (name.startsWith('#')) {
    final code = name.startsWith('#x') ? int.tryParse(name.substring(2), radix: 16) : int.tryParse(name.substring(1));
    return code == null || code <= 0 || code > 0x10FFFF ? m.group(0)! : String.fromCharCode(code);
  }
  return _named[name] ?? m.group(0)!;
});
