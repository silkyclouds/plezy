const _imageHost = 'image.pbs.org';
const _maxWidth = 1920;

bool isPbsImage(String reference) => Uri.tryParse(reference)?.host == _imageHost;

/// The image server scales to any `resize=WxH` box, so the original address gets the size the screen asks for.
String pbsImageUrl(String reference, {int? width, int? height}) {
  final uri = Uri.tryParse(reference);
  if (uri == null || width == null || height == null || width <= 0 || height <= 0) return reference;
  final fitted = width > _maxWidth ? _maxWidth : width;
  final scaled = (height * fitted / width).round();
  return uri.replace(queryParameters: {...uri.queryParameters, 'resize': '${fitted}x$scaled'}).toString();
}
