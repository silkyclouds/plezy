import 'dart:math' as math;

const _assetHost = 'www.zdf.de';
const _epgHost = 'epg-image.zdf.de';

/// The crops of the asset family on `www.zdf.de/assets` that are 16:9, smallest first.
const _assetSizes = [(768, 432), (1280, 720), (2400, 1350)];

/// The 16:9 crops that exist for the asset family on `epg-image.zdf.de`, smallest first.
const _epgSizes = [(276, 155), (384, 216), (768, 432), (1280, 720), (1920, 1080)];

final _assetSuffix = RegExp(r'~(\d+)x(\d+)(\?|$)');
final _epgLayout = RegExp(r'layout=(\d+)x(\d+)');

typedef _Crop = ({String url, int width, int height});

/// Which picture a title needs.
enum ZdfPicture { backdrop, poster, logo }

/// Picks the crop of [maps] that suits [picture]. Each map is a `teaserBild`, `image` or `logo` object keyed by width;
/// the maps are tried in order and the first one holding a fitting shape wins. The key says nothing about the shape,
/// so the entry's own width and height decide.
String? zdfPickImage(Iterable<Object?> maps, ZdfPicture picture) {
  _Crop? fallback;
  for (final map in maps) {
    final crops = _crops(map);
    final best = _best(crops, picture);
    if (best == null) continue;
    if (_fits(best, picture)) return best.url;
    fallback ??= best;
  }
  return fallback?.url;
}

/// Rewrites the size of a 16:9 reference to the smallest crop that covers [width]. ZDF answers an unlisted size with a
/// 404, so anything that is not a 16:9 crop of a known family is returned as it is.
String zdfImageUrl(String reference, {int? width}) {
  if (width == null) return reference;
  final uri = Uri.tryParse(reference);
  if (uri == null) return reference;
  if (uri.host == _assetHost && uri.path.startsWith('/assets/')) {
    return _resizeSuffix(reference, width) ?? reference;
  }
  if (uri.host == _epgHost) return _resizeLayout(reference, width) ?? reference;
  return reference;
}

bool isZdfImage(String reference) {
  final host = Uri.tryParse(reference)?.host;
  return host == _assetHost || host == _epgHost;
}

String? _resizeSuffix(String reference, int width) {
  final match = _assetSuffix.firstMatch(reference);
  if (match == null || !_isWide(int.parse(match.group(1)!), int.parse(match.group(2)!))) return null;
  final size = _smallestCovering(_assetSizes, width);
  return reference.replaceRange(match.start, match.end, '~${size.$1}x${size.$2}${match.group(3)}');
}

String? _resizeLayout(String reference, int width) {
  final match = _epgLayout.firstMatch(reference);
  if (match == null || !_isWide(int.parse(match.group(1)!), int.parse(match.group(2)!))) return null;
  final size = _smallestCovering(_epgSizes, width);
  return reference.replaceRange(match.start, match.end, 'layout=${size.$1}x${size.$2}');
}

(int, int) _smallestCovering(List<(int, int)> sizes, int width) =>
    sizes.firstWhere((s) => s.$1 >= width, orElse: () => sizes.last);

bool _isWide(int width, int height) => (width / height - 16 / 9).abs() < 0.02;

List<_Crop> _crops(Object? map) {
  if (map is! Map) return const [];
  return [
    for (final entry in map.values)
      if (entry is Map && entry['url'] is String && entry['width'] is num && entry['height'] is num)
        (url: entry['url'] as String, width: (entry['width'] as num).toInt(), height: (entry['height'] as num).toInt()),
  ];
}

_Crop? _best(List<_Crop> crops, ZdfPicture picture) {
  if (crops.isEmpty) return null;
  return switch (picture) {
    ZdfPicture.backdrop => _closest(crops, 16 / 9, preferredWidth: 1280),
    ZdfPicture.poster => _closest([...crops.where((c) => c.height > c.width)], 2 / 3, minWidth: 500),
    ZdfPicture.logo => _widest(crops),
  };
}

bool _fits(_Crop crop, ZdfPicture picture) {
  final ratio = crop.width / crop.height;
  return switch (picture) {
    ZdfPicture.backdrop => ratio >= 1.6 && ratio <= 1.95,
    ZdfPicture.poster => ratio >= 0.5 && ratio <= 1.0 && crop.width >= 500,
    ZdfPicture.logo => true,
  };
}

/// The crop whose shape is nearest [ratio]; among equally near ones the one nearest [preferredWidth], else the
/// narrowest that is at least [minWidth] wide.
_Crop? _closest(List<_Crop> crops, double ratio, {int? preferredWidth, int minWidth = 0}) {
  if (crops.isEmpty) return null;
  final wide = crops.where((c) => c.width >= minWidth).toList();
  final pool = wide.isEmpty ? crops : wide;
  double distance(_Crop c) => (math.log(c.width / c.height / ratio).abs() * 20).round() / 20;
  int rank(_Crop c) => preferredWidth == null ? c.width : (c.width - preferredWidth).abs();
  return ([...pool]..sort((a, b) {
        final byShape = distance(a).compareTo(distance(b));
        return byShape != 0 ? byShape : rank(a).compareTo(rank(b));
      }))
      .first;
}

_Crop _widest(List<_Crop> crops) => ([...crops]..sort((a, b) => b.width.compareTo(a.width))).first;
