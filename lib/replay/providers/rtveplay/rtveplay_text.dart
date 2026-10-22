import '../../text/html_text.dart';

const _entities = {
  'aacute': 'á',
  'eacute': 'é',
  'iacute': 'í',
  'oacute': 'ó',
  'uacute': 'ú',
  'Aacute': 'Á',
  'Eacute': 'É',
  'Iacute': 'Í',
  'Oacute': 'Ó',
  'Uacute': 'Ú',
  'agrave': 'à',
  'egrave': 'è',
  'ograve': 'ò',
  'ntilde': 'ñ',
  'Ntilde': 'Ñ',
  'uuml': 'ü',
  'Uuml': 'Ü',
  'ccedil': 'ç',
  'Ccedil': 'Ç',
  'iexcl': '¡',
  'iquest': '¿',
  'ordm': 'º',
  'ordf': 'ª',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'middot': '·',
  'euro': '€',
  'copy': '©',
};

final _entity = RegExp(r'&(#\d+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);');
final _years = RegExp(r'(\d{1,2})\s+años');

/// Plain text of an HTML synopsis. RTVE writes accents as named entities (`&iquest;`, `&aacute;`) that the shared
/// reducer leaves alone.
String rtvePlainText(String? html) => htmlToText(html).replaceAllMapped(_entity, (m) {
  final name = m.group(1)!;
  if (name.startsWith('#')) {
    final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
    final code = int.tryParse(name.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
    return code == null || code > 0x10FFFF ? m.group(0)! : String.fromCharCode(code);
  }
  return _entities[name] ?? m.group(0)!;
});

/// The long description when there is one, else the short one.
String? rtveSummary(Object? description, Object? shortDescription) {
  for (final raw in [description, shortDescription]) {
    final text = rtvePlainText(raw is String ? raw : null);
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// Names RTVE joins with a bar (`Ana Duato | Imanol Arias`).
List<String> rtveNames(Object? joined) {
  if (joined is! String) return const [];
  return [
    for (final name in joined.split('|'))
      if (name.trim().isNotEmpty) name.trim(),
  ];
}

/// "TP" for programmes open to everyone, "12+" for "No recomendable para menores de 12 años", else null.
String? rtveContentRating(Object? ageRange) {
  if (ageRange is! String) return null;
  final lower = ageRange.toLowerCase();
  if (lower.contains('todos los públicos')) return 'TP';
  final years = _years.firstMatch(lower)?.group(1);
  return years == null ? null : '$years+';
}

String? rtveNonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
