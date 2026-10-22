/// Every NRK picture is `https://gfx.nrk.no/{hash}` and the width is part of the hash, so a size cannot be asked for.
/// An artwork reference therefore carries the hash of each width: `https://gfx.nrk.no/{first}#300:{hash},600:{hash}`.
const nrkImageHost = 'https://gfx.nrk.no/';

const _defaultWidth = 960;

bool isNrkImage(String reference) => reference.startsWith(nrkImageHost);

/// Builds an artwork reference from any of the shapes NRK uses, or returns null when there is no usable picture.
///
/// Accepted: a list of `{url, width}` (catalogue), a map holding `webImages` as `{uri, width}` (pages) or
/// `{imageUrl, pixelWidth}` (search and A-Z index).
String? nrkImageRef(Object? images) {
  final list = images is Map ? images['webImages'] : images;
  if (list is! List) return null;
  final byWidth = <int, String>{};
  for (final raw in list.whereType<Map>()) {
    final url = raw['url'] ?? raw['uri'] ?? raw['imageUrl'];
    final width = ((raw['width'] ?? raw['pixelWidth']) as num?)?.toInt();
    if (url is String && width != null && url.startsWith(nrkImageHost) && url.length > nrkImageHost.length) {
      byWidth[width] = url.substring(nrkImageHost.length);
    }
  }
  if (byWidth.isEmpty) return null;
  final widths = byWidth.keys.toList()..sort();
  final entries = [for (final w in widths) '$w:${byWidth[w]}'];
  return '$nrkImageHost${byWidth[widths.first]}#${entries.join(',')}';
}

/// The picture of [reference] that is the smallest one at least [width] wide, or the widest there is.
String nrkImageUrl(String reference, {int? width}) {
  final cut = reference.indexOf('#');
  if (cut < 0) return reference;
  final wanted = width ?? _defaultWidth;
  String? chosen;
  for (final entry in reference.substring(cut + 1).split(',')) {
    final colon = entry.indexOf(':');
    if (colon <= 0) continue;
    final entryWidth = int.tryParse(entry.substring(0, colon));
    if (entryWidth == null) continue;
    chosen = entry.substring(colon + 1);
    if (entryWidth >= wanted) break;
  }
  return chosen == null ? reference.substring(0, cut) : '$nrkImageHost$chosen';
}
