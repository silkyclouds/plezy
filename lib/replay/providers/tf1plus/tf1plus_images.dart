/// TF1+ artwork URLs carry a signature per size, format and density, so they can only be used as the API
/// returned them. A variant is chosen when a title is mapped; later calls leave the URL untouched.
const tf1ImageHost = 'photos.tf1.fr';

bool isTf1Image(String reference) => Uri.tryParse(reference)?.host == tf1ImageHost;

String tf1ImageUrl(String reference, {int? width, int? height}) => reference;

/// Widths the app asks for, per kind of artwork.
abstract final class Tf1ImageWidth {
  static const poster = 500;
  static const backdrop = 1280;
  static const still = 640;
  static const logo = 450;
}

class _Variant {
  final String url;
  final int width;
  final int scale;

  _Variant(this.url, this.width, this.scale);

  int get effectiveWidth => width * scale;
}

final _sizeInPath = RegExp(r'photos\.tf1\.fr/(\d+)/(\d+)/');
final _scaleInName = RegExp(r'@(\d)x\.');

/// Picks the smallest variant at least [targetWidth] pixels wide, or the widest one when none is.
///
/// [image] is any of the shapes the API uses: `sources`, `sourcesWithScales`, or a bare `logo` list.
/// AVIF is skipped because the image decoder in use cannot read it everywhere.
String? tf1PickImage(Object? image, {required int targetWidth}) {
  final variants = _variants(image);
  if (variants.isEmpty) return null;
  variants.sort((a, b) {
    final byWidth = a.effectiveWidth.compareTo(b.effectiveWidth);
    return byWidth != 0 ? byWidth : a.scale.compareTo(b.scale);
  });
  return variants.firstWhere((v) => v.effectiveWidth >= targetWidth, orElse: () => variants.last).url;
}

/// Picks the video still from `decoration.images`, preferring the large thumbnail and ignoring the MP4 teaser.
String? tf1PickVideoImage(Object? images, {int targetWidth = Tf1ImageWidth.still}) {
  if (images is! List) return null;
  final byType = {
    for (final image in images.whereType<Map<String, dynamic>>())
      if (image['type'] is String) image['type'] as String: image,
  };
  return tf1PickImage(byType['THUMBNAIL_LARGE'] ?? byType['THUMBNAIL'], targetWidth: targetWidth);
}

List<_Variant> _variants(Object? image) {
  if (image is! Map) return [];
  final raw = image['sourcesWithScales'] ?? image['sources'] ?? image['logo'];
  if (raw is! List) return [];
  return [
    for (final entry in raw.whereType<Map>())
      if (entry['url'] case final String url when _isSupported(url, entry['type']))
        _Variant(url, _width(url, entry), _scale(url, entry)),
  ];
}

bool _isSupported(String url, Object? type) {
  final extension = (type is String ? type : url.split('.').last).toLowerCase();
  return extension != 'avif' && extension != 'mp4';
}

int _width(String url, Map entry) {
  final match = _sizeInPath.firstMatch(url);
  final width = int.tryParse(match?.group(1) ?? '') ?? int.tryParse('${entry['width']}') ?? 0;
  if (width > 0) return width;
  // Logos are sized by height only; height times two approximates the width of a wordmark.
  final height = int.tryParse(match?.group(2) ?? '') ?? int.tryParse('${entry['height']}') ?? 0;
  return height * 2;
}

int _scale(String url, Map entry) {
  final fromUrl = int.tryParse(_scaleInName.firstMatch(url)?.group(1) ?? '');
  return fromUrl ?? (entry['scale'] as num?)?.toInt() ?? 1;
}
