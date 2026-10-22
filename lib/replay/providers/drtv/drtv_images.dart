import 'dart:math';

const _imageHost = 'https://prod95-static.dr-massive.com/';
const _defaultWidth = 640;
const _quality = 75;

bool isDrtvImage(String reference) => reference.startsWith(_imageHost);

final _format = RegExp(r"Format='[a-zA-Z]+'");
final _qualityParam = RegExp(r'Quality=\d+');
final _widthParam = RegExp(r'Width=(\d+)');
final _heightParam = RegExp(r'Height=(\d+)');

/// Rewrites the query of a DR image URL to a small JPEG.
///
/// The catalogue links PNGs of several megabytes. The server accepts any size, so the original's aspect ratio is kept:
/// the picture covers the requested box, and never exceeds the original's pixels.
String drtvImageUrl(String reference, {int? width, int? height}) {
  final originalWidth = _number(_widthParam, reference);
  final originalHeight = _number(_heightParam, reference);
  var url = reference.replaceFirst(_format, "Format='jpg'").replaceFirst(_qualityParam, 'Quality=$_quality');
  if (originalWidth == null || originalHeight == null || originalHeight == 0) return url;

  final ratio = originalWidth / originalHeight;
  var targetWidth = switch ((width, height)) {
    (final w?, final h?) => max(w, (h * ratio).round()),
    (final w?, null) => w,
    (null, final h?) => (h * ratio).round(),
    _ => _defaultWidth,
  };
  var targetHeight = (targetWidth / ratio).round();
  if (targetWidth > originalWidth) {
    targetWidth = originalWidth;
    targetHeight = originalHeight;
  }
  url = url.replaceFirst(_widthParam, 'Width=$targetWidth').replaceFirst(_heightParam, 'Height=$targetHeight');
  return url;
}

int? _number(RegExp pattern, String text) {
  final match = pattern.firstMatch(text);
  return match == null ? null : int.tryParse(match.group(1)!);
}
