import 'package:unorm_dart/unorm_dart.dart' as unorm;

const _entities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
  '&hellip;': '...',
  '&rsquo;': '’',
  '&lsquo;': '‘',
  '&laquo;': '«',
  '&raquo;': '»',
  '&ndash;': '–',
  '&mdash;': '—',
};

// Windows-1252 punctuation that the stations' editors paste in as C1 control characters.
const _c1Punctuation = {0x91: '‘', 0x92: '’', 0x93: '“', 0x94: '”', 0x95: '•', 0x96: '–', 0x97: '—'};

final _numericEntity = RegExp(r'&#(x[0-9a-fA-F]+|\d+);');
final _tag = RegExp(r'<[^>]*>');
final _spaces = RegExp(r'\s+');
final _c1Controls = RegExp('[\u0091-\u0097]');
final _combiningMarks = RegExp(r'[̀-ͯ]');
final _notAlphanumeric = RegExp(r'[^a-z0-9]+');

/// Decodes the named and numeric character references that appear in the stations' markup.
String decodeEntities(String text) {
  var decoded = text.replaceAllMapped(_numericEntity, (m) {
    final raw = m.group(1)!;
    final code = raw.startsWith('x') ? int.tryParse(raw.substring(1), radix: 16) : int.tryParse(raw);
    return code == null || code > 0x10ffff ? m.group(0)! : String.fromCharCode(code);
  });
  _entities.forEach((entity, char) => decoded = decoded.replaceAll(entity, char));
  return decoded;
}

/// Plain, single-spaced text from a fragment of HTML.
String htmlFragmentText(String fragment) => tidyText(decodeEntities(fragment.replaceAll(_tag, ' ')));

/// Collapses whitespace and replaces C1 control characters by the punctuation they stood for.
String tidyText(String text) {
  final fixed = text.replaceAllMapped(_c1Controls, (m) => _c1Punctuation[m.group(0)!.codeUnitAt(0)] ?? '');
  return fixed.replaceAll(_spaces, ' ').trim();
}

/// The text, or null when it has no letter or digit in it (the sites use "." or a blank as a placeholder).
String? meaningfulText(String? text) {
  if (text == null) return null;
  final tidy = tidyText(text);
  return tidy.contains(RegExp(r'[\p{L}\p{N}]', unicode: true)) ? tidy : null;
}

/// Lowercase ASCII words separated by single spaces, so that search ignores case, accents and punctuation.
String foldForSearch(String text) {
  final stripped = unorm.nfd(text.toLowerCase()).replaceAll(_combiningMarks, '');
  return stripped.replaceAll(_notAlphanumeric, ' ').trim();
}
