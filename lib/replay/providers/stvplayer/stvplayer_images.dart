const _host = 'https://player.api.stv.tv/v1/images/';

/// Widths worth asking for, so neighbouring requests share a cached file. The server crops to any size.
const _widths = [320, 480, 640, 960, 1280, 1920];
const _defaultWidth = 640;
const _widescreen = 9 / 16;

bool isStvPlayerImage(String reference) => reference.startsWith(_host);

/// The artwork reference for the first image of [type] in [images], or null when there is none.
///
/// [images] is the `images` list of a programme or episode, or the single image object of a category. The reference
/// is the resizer URL with `[width]` and `[height]` left open, followed by the picture's own size as a fragment so a
/// width-only request keeps its proportions (a title logo must not be cropped to 16:9).
String? stvPlayerImageReference(Object? images, {String type = 'mainImage', bool anyImage = false}) {
  final candidates = switch (images) {
    final List<dynamic> list => list.whereType<Map<dynamic, dynamic>>().toList(),
    final Map<dynamic, dynamic> single => [single],
    _ => const <Map<dynamic, dynamic>>[],
  };
  final typed = candidates.where((i) => i['imageType'] == type);
  final hit = typed.isNotEmpty ? typed.first : (anyImage ? candidates.firstOrNull : null);
  final id = hit?['id'];
  if (hit == null || id == null) return null;
  final width = hit['width'];
  final height = hit['height'];
  final size = width is num && height is num && width > 0 && height > 0 ? '#${width.toInt()}x${height.toInt()}' : '';
  return '$_host$id/rendition/?redirect=true&width=[width]&height=[height]$size';
}

/// Fills a reference with the smallest standard width that covers [width], and the matching height.
String stvPlayerImageUrl(String reference, {int? width, int? height}) {
  if (!isStvPlayerImage(reference)) return reference;
  final fragment = reference.indexOf('#');
  final template = fragment < 0 ? reference : reference.substring(0, fragment);
  final ratio = fragment < 0 ? _widescreen : _heightPerWidth(reference.substring(fragment + 1));

  final requestedWidth = width ?? (height == null ? _defaultWidth : (height / ratio).round());
  final snapped = _widths.firstWhere((w) => w >= requestedWidth, orElse: () => _widths.last);
  final cropRatio = width != null && height != null ? height / width : ratio;
  return template.replaceAll('[width]', '$snapped').replaceAll('[height]', '${(snapped * cropRatio).round()}');
}

double _heightPerWidth(String size) {
  final parts = size.split('x');
  final w = int.tryParse(parts.first);
  final h = parts.length == 2 ? int.tryParse(parts.last) : null;
  return w == null || h == null || w == 0 ? _widescreen : h / w;
}
