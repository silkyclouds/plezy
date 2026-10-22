/// UR serves every picture in a fixed ladder of sizes, named by a suffix on the file. Only 16:9 and square exist.
const _landscape = [
  (64, '_u'),
  (128, '_t'),
  (160, '_s'),
  (240, '_sm'),
  (320, ''),
  (480, '_ml'),
  (640, '_l'),
  (960, '_xl'),
  (1280, '_hd'),
];
const _square = [(75, '_sq'), (360, '_sql')];

const urImageHost = 'https://assets.ur.se/id/';

final _imagePattern = RegExp(r'^(https://assets\.ur\.se/id/\d+/images/1)(_[a-z]+)?\.jpg$');

bool isUrImage(String reference) => _imagePattern.hasMatch(reference);

/// The widest 16:9 picture of an item, the reference the catalogue hands to the app.
String urBackdropReference(String id, Object? images) => _fromLadder(images, '1280x720', id, '_hd');

/// The square picture of an item. UR has no portrait art, and a square crops better into a poster than 16:9.
String urPosterReference(String id, Object? images) => _fromLadder(images, '360x360', id, '_sql');

String _fromLadder(Object? images, String key, String id, String suffix) {
  final listed = images is Map ? images[key] : null;
  if (listed is String && isUrImage(listed)) return listed;
  return '$urImageHost$id/images/1$suffix.jpg';
}

/// Rewrites a reference to the smallest picture of its shape that covers [width] (or [height] when only that is known).
String urImageUrl(String reference, {int? width, int? height}) {
  final match = _imagePattern.firstMatch(reference);
  if (match == null) return reference;
  final isSquare = const {'_sq', '_sql'}.contains(match.group(2));
  final ladder = isSquare ? _square : _landscape;
  final wanted = width ?? (height == null ? 640 : (isSquare ? height : (height * 16 / 9).ceil()));
  final size = ladder.firstWhere((s) => s.$1 >= wanted, orElse: () => ladder.last);
  return '${match.group(1)}${size.$2}.jpg';
}
