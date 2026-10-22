/// Invisible direction marks that ZDF puts in descriptions: left-to-right, right-to-left and the embedding controls.
final _invisible = RegExp('[${String.fromCharCodes([0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e])}]');

String? zdfText(Object? value) {
  if (value is! String) return null;
  final cleaned = value.replaceAll(_invisible, '').trim();
  return cleaned.isEmpty ? null : cleaned;
}
