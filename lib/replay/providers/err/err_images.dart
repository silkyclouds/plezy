/// ERR pre-renders each picture at fixed sizes, and every size has its own address. An artwork reference therefore
/// lists the usable sizes as `WxH=url` pairs, and [errImageUrl] picks the one that fits.
const errImagePrefix = 'err-photo:';

bool isErrImage(String reference) => reference.startsWith(errImagePrefix);

/// Photo sets in the order they are tried for a landscape picture and for a portrait one.
const _landscapeSets = ['horizontalPhotos', 'photos', 'horizontalPoster', 'heroImage'];
const _portraitSets = ['verticalPhotos'];

/// Most sizes kept per reference, to keep the stored string short.
const _maxSizes = 5;

/// Artwork reference for the 16:9 picture of [item], or null when it has none.
String? errBackdropReference(Map<String, dynamic> item) => _reference(item, _landscapeSets, portrait: false);

/// Artwork reference for the 2:3 picture of [item], or null when it has none.
String? errPosterReference(Map<String, dynamic> item) => _reference(item, _portraitSets, portrait: true);

String? _reference(Map<String, dynamic> item, List<String> setNames, {required bool portrait}) {
  for (final name in setNames) {
    final sizes = _sizesOf(item[name], portrait: portrait);
    if (sizes.isEmpty) continue;
    return '$errImagePrefix${_spread(sizes).map((s) => '${s.w}x${s.h}=${s.url}').join(' ')}';
  }
  return null;
}

/// The crops of the first photo of a set that have the wanted orientation, narrowest first.
List<({int w, int h, String url})> _sizesOf(Object? set, {required bool portrait}) {
  if (set is! List || set.isEmpty || set.first is! Map) return const [];
  final types = (set.first as Map)['photoTypes'];
  if (types is! Map) return const [];
  final sizes = <({int w, int h, String url})>[];
  for (final crop in types.values.whereType<Map>()) {
    final w = (crop['w'] as num?)?.toInt() ?? 0;
    final h = (crop['h'] as num?)?.toInt() ?? 0;
    final url = crop['url'] as String?;
    if (url == null || w < 150 || h < 150) continue;
    final fits = portrait ? h / w >= 1.3 : w / h >= 1.5;
    if (fits && sizes.every((s) => s.w != w)) sizes.add((w: w, h: h, url: url));
  }
  sizes.sort((a, b) => a.w.compareTo(b.w));
  return sizes;
}

/// At most [_maxSizes] sizes spread from the smallest to the largest.
List<({int w, int h, String url})> _spread(List<({int w, int h, String url})> sizes) {
  if (sizes.length <= _maxSizes) return sizes;
  final last = sizes.length - 1;
  return [for (var i = 0; i < _maxSizes; i++) sizes[(i * last / (_maxSizes - 1)).round()]];
}

final _listedSize = RegExp(r'^(\d+)x\d+=(.+)$');

/// The smallest listed crop at least [width] wide, or the largest one.
String errImageUrl(String reference, {int? width, int? height}) {
  if (!isErrImage(reference)) return reference;
  final wanted = width ?? 600;
  String? best;
  for (final pair in reference.substring(errImagePrefix.length).split(' ')) {
    final match = _listedSize.firstMatch(pair);
    if (match == null) continue;
    best = match.group(2);
    if (int.parse(match.group(1)!) >= wanted) break;
  }
  return best ?? reference;
}
