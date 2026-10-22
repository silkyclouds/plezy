const france24ImageHost = 'https://s.france24.com/media/display/';

bool isFrance24Image(String reference) => reference.startsWith(france24ImageHost);

/// The resizer answers 404 to any width outside this list.
const _widths = [
  90,
  100,
  200,
  240,
  250,
  320,
  360,
  400,
  480,
  500,
  600,
  640,
  720,
  800,
  960,
  1024,
  1080,
  1200,
  1280,
  1920,
];

/// Crops the resizer offers, as `(name, width / height)`.
const _ratios = [('16x9', 16 / 9), ('3x2', 3 / 2), ('4x3', 4 / 3), ('1x1', 1.0), ('3x4', 3 / 4), ('2x3', 2 / 3)];

const _defaultWidth = 640;
final _sizeSegment = RegExp(r'^(w:\d+|p:\d+x\d+)$');

/// The unresized picture of an `images` object, or null when it has none on the artwork host.
///
/// The original has no size segment, so one reference serves the poster, backdrop and thumbnail uses.
String? france24OriginalImage(Object? images) {
  if (images is! Map) return null;
  final formats = images['formats'];
  if (formats is! List) return null;
  final entries = formats.whereType<Map<String, dynamic>>().toList();
  final original = entries.where((f) => f['code'] == 'original').firstOrNull ?? entries.firstOrNull;
  final url = original?['url'];
  return url is String && isFrance24Image(url) ? url : null;
}

/// Builds the URL of [reference] cropped and scaled for a [width] x [height] box.
///
/// Vector pictures cannot be resized and are returned as they are.
String france24ImageUrl(String reference, {int? width, int? height}) {
  final uri = Uri.parse(reference);
  final base = [
    for (final s in uri.pathSegments)
      if (!_sizeSegment.hasMatch(s)) s,
  ];
  if (base.last.toLowerCase().endsWith('.svg')) return uri.replace(pathSegments: base).toString();

  final ratio = _closestRatio(width, height);
  final wanted = width ?? (height == null ? _defaultWidth : (height * ratio.$2).round());
  final size = _widths.firstWhere((w) => w >= wanted, orElse: () => _widths.last);
  final segments = [...base.take(base.length - 1), 'w:$size', 'p:${ratio.$1}', base.last];
  return uri.replace(pathSegments: segments).toString();
}

(String, double) _closestRatio(int? width, int? height) {
  if (width == null || height == null || height == 0) return _ratios.first;
  final wanted = width / height;
  return _ratios.reduce((best, r) => (r.$2 - wanted).abs() < (best.$2 - wanted).abs() ? r : best);
}
