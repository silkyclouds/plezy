/// Image host of the iPlayer catalogue. References keep the `{recipe}` placeholder until a size is known.
const bbcImagePrefix = 'https://ichef.bbci.co.uk/images/ic/';

/// The image server only answers a fixed list of sizes; anything else is a 403.
const _landscape = [(192, 108), (320, 180), (480, 270), (512, 288), (640, 360), (960, 540), (1200, 675), (1280, 720)];
const _portrait = [(192, 288), (304, 456), (400, 600), (464, 696), (640, 960)];

bool isBbcImage(String reference) => reference.startsWith(bbcImagePrefix);

/// Fills the `{recipe}` placeholder with the smallest allowed size that covers [width].
String bbcImageUrl(String template, {int? width, int? height}) {
  final portrait = width != null && height != null && height > width;
  final sizes = portrait ? _portrait : _landscape;
  final wanted = width ?? 640;
  final size = sizes.firstWhere((s) => s.$1 >= wanted, orElse: () => sizes.last);
  return template.replaceAll('{recipe}', '${size.$1}x${size.$2}');
}
