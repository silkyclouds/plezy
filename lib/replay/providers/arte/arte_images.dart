/// ARTE's image resizer only answers a fixed list of sizes; any other size is a 400.
const _landscape = [(340, 192), (400, 225), (720, 405), (940, 530), (1280, 720), (1600, 900), (1920, 1080)];
const _portrait = [(265, 397), (300, 450), (500, 750)];

const arteImageHost = 'https://api-cdn.arte.tv/img/';

bool isArteImage(String reference) => reference.startsWith(arteImageHost);

/// Fills the `__SIZE__` placeholder with the smallest allowed size that covers [width] x [height].
String arteImageUrl(String template, {int? width, int? height}) {
  final portrait = width != null && height != null && height > width;
  final sizes = portrait ? _portrait : _landscape;
  final wanted = width ?? 720;
  final size = sizes.firstWhere((s) => s.$1 >= wanted, orElse: () => sizes.last);
  return template.replaceAll('__SIZE__', '${size.$1}x${size.$2}');
}
