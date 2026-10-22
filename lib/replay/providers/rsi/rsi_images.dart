import '../srg/srg_images.dart';

const _originHost = 'https://il.rsi.ch/rsi-api/resize/image/v2/';

/// Widths worth asking the image server for, so neighbouring requests share a cached file.
const _widths = [160, 320, 448, 640, 960, 1280, 1920];

// Only pictures stored under a numeric id can be scaled; the static ones under `public/` cannot.
final _scalable = RegExp(r'/v2/[A-Z_]+/\d+$');

bool isRsiImage(String reference) => reference.startsWith(_originHost) || isSrgFallbackImage(reference);

/// Appends the width segment the RSI image server understands to a scalable picture.
String rsiImageUrl(String reference, {int? width, int? height}) {
  if (!reference.startsWith(_originHost) || !_scalable.hasMatch(reference)) return reference;
  final portrait = width != null && height != null && height > width;
  return '$reference/scale/width/${srgWidthBucket(_widths, width ?? (portrait ? 320 : 640))}';
}

/// Artwork of RSI Play.
class RsiImages implements SrgImageResizer {
  const RsiImages();

  @override
  bool owns(String reference) => isRsiImage(reference);

  @override
  String url(String reference, {int? width, int? height}) => rsiImageUrl(reference, width: width, height: height);
}
