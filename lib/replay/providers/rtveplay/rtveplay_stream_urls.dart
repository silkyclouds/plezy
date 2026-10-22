import 'dart:convert';
import 'dart:typed_data';

const _pngSignatureLength = 8;
const _chunkOverhead = 12;
const _hashSeparator = '#';
const _qualitySeparator = '%%';

/// Reads the stream list RTVE serves as a base64 PNG whose text chunks hold the addresses in a fixed scrambled form.
///
/// Every `tEXt` chunk carries `alphabet#digits`: the alphabet keeps one character in a rotating pattern, and the
/// digits are pairs (tens, units) that index into it, with a changing number of filler digits between the pairs.
/// This is an obfuscation of public addresses, not encryption: nothing is decrypted that a player could not read.
List<Uri> rtveDecodeStreamUrls(String body) {
  final Uint8List png;
  try {
    png = base64.decode(base64.normalize(body.replaceAll(RegExp(r'\s'), '')));
  } on FormatException {
    return const [];
  }
  final urls = <Uri>[];
  for (final text in _textChunks(png)) {
    final url = _unscramble(text);
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) urls.add(uri);
  }
  return urls;
}

Iterable<String> _textChunks(Uint8List png) sync* {
  final data = ByteData.sublistView(png);
  var position = _pngSignatureLength;
  while (position + _chunkOverhead <= png.length) {
    final length = data.getUint32(position);
    final type = String.fromCharCodes(png, position + 4, position + 8);
    final start = position + 8;
    if (type == 'IEND' || start + length > png.length) return;
    if (type == 'tEXt') {
      final raw = png.sublist(start, start + length).where((byte) => byte != 0);
      yield String.fromCharCodes(raw);
    }
    position = start + length + 4;
  }
}

String? _unscramble(String text) {
  final cut = text.indexOf(_hashSeparator);
  if (cut < 0) return null;
  final alphabet = _alphabet(text.substring(0, cut));
  final rest = text.substring(cut + 1);
  final quality = rest.lastIndexOf(_qualitySeparator);
  final digits = quality < 0 ? rest : rest.substring(quality + _qualitySeparator.length);
  return _address(alphabet, digits);
}

String _alphabet(String scrambled) {
  final kept = StringBuffer();
  var step = 0;
  var skip = 0;
  for (final char in scrambled.split('')) {
    if (skip == 0) {
      kept.write(char);
      step = (step + 1) % 4;
      skip = step;
    } else {
      skip--;
    }
  }
  return kept.toString();
}

String? _address(String alphabet, String digits) {
  final out = StringBuffer();
  var position = 0;
  var gap = 3;
  var round = 1;
  while (position < digits.length) {
    final tens = int.tryParse(digits[position]);
    position += 1 + gap;
    if (position >= digits.length) break;
    final units = int.tryParse(digits[position]);
    position++;
    if (tens == null || units == null || tens * 10 + units >= alphabet.length) return null;
    out.write(alphabet[tens * 10 + units]);
    gap = (round + 3) % 4;
    round++;
  }
  return out.isEmpty ? null : out.toString();
}
