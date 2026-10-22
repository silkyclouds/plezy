const _site = 'https://www.stvr.sk';
const stvrImagePrefix = '$_site/media/';

bool isStvrImage(String reference) => reference.startsWith(stvrImagePrefix);

/// Makes a thumbnail path absolute and secure. The server takes no size parameter and does not serve the larger
/// variant for every file, so the reference is never rewritten into another size.
String? stvrAbsoluteImage(String? raw) {
  final path = raw?.trim();
  if (path == null || path.isEmpty || path.contains('placeholder')) return null;
  if (path.startsWith('//')) return 'https:$path';
  if (path.startsWith('/')) return '$_site$path';
  return path.startsWith('http://') ? 'https://${path.substring('http://'.length)}' : path;
}
