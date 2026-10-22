import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/logo_knockout.dart';

/// A [size] x [size] picture: white page with a filled square of [mark] (r, g, b) in the middle.
Uint8List _logo(int size, List<int> mark, {int alpha = 255}) {
  final data = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final inside = x >= size ~/ 3 && x < size * 2 ~/ 3 && y >= size ~/ 3 && y < size * 2 ~/ 3;
      final i = (y * size + x) * 4;
      final rgb = inside ? mark : const [255, 255, 255];
      data[i] = rgb[0];
      data[i + 1] = rgb[1];
      data[i + 2] = rgb[2];
      data[i + 3] = alpha;
    }
  }
  return data;
}

List<int> _pixel(Uint8List data, int size, int x, int y) {
  final i = (y * size + x) * 4;
  return [data[i], data[i + 1], data[i + 2], data[i + 3]];
}

void main() {
  const size = 30;

  test('the white page becomes clear and a dark neutral mark turns white and solid', () {
    final out = knockOutWhiteBackground(_logo(size, [10, 10, 10]), size, size)!;
    expect(_pixel(out, size, 1, 1)[3], 0);
    final mark = _pixel(out, size, 15, 15);
    expect(mark.sublist(0, 3), [255, 255, 255]);
    expect(mark[3], greaterThan(240));
  });

  test('a coloured mark keeps its colour', () {
    final out = knockOutWhiteBackground(_logo(size, [230, 120, 30]), size, size)!;
    final mark = _pixel(out, size, 15, 15);
    expect(mark[3], greaterThan(150));
    expect(mark[0], greaterThan(mark[2] + 100), reason: 'still orange, not white');
  });

  test('a picture that already has transparency is left alone', () {
    expect(knockOutWhiteBackground(_logo(size, [10, 10, 10], alpha: 120), size, size), isNull);
  });

  test('a picture whose border is not white is not a logo on a page', () {
    final photo = Uint8List(size * size * 4);
    for (var i = 0; i < photo.length; i += 4) {
      photo[i] = 40;
      photo[i + 1] = 60;
      photo[i + 2] = 90;
      photo[i + 3] = 255;
    }
    expect(knockOutWhiteBackground(photo, size, size), isNull);
  });
}
