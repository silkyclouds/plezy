const aljazeeraSiteHost = 'https://www.aljazeera.com';
const _uploads = '$aljazeeraSiteHost/wp-content/';

/// Frames Brightcove renders for a video. They are fixed-size files and are used as they are.
const _brightcoveImages = 'https://cf-images.eu-west-1.prod.boltdns.net/';

const _defaultWidth = 770;
const _maxWidth = 1920;

bool isAljazeeraImage(String reference) => reference.startsWith(_uploads) || reference.startsWith(_brightcoveImages);

/// The absolute address of an upload path from the catalogue, or null when it is not an upload.
String? aljazeeraUploadUrl(Object? sourceUrl) {
  if (sourceUrl is! String || !sourceUrl.startsWith('/wp-content/')) return null;
  return '$aljazeeraSiteHost$sourceUrl';
}

/// Asks the site to crop and scale an upload to [width] x [height]. The bare path is a multi-megabyte original.
///
/// A missing side is derived for a 16:9 frame, which is how every episode picture is shown.
String aljazeeraImageUrl(String reference, {int? width, int? height}) {
  if (reference.startsWith(_brightcoveImages)) return reference;
  final base = reference.split('?').first;
  final wanted = _bounded(width ?? (height == null ? _defaultWidth : (height * 16 / 9).round()));
  final high = _bounded(height ?? (wanted * 9 / 16).round());
  return Uri.parse(base).replace(queryParameters: {'resize': '$wanted,$high', 'quality': '80'}).toString();
}

int _bounded(int size) => size < 1 ? 1 : (size > _maxWidth ? _maxWidth : size);
