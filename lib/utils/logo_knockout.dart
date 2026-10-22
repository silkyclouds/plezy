import 'dart:math' as math;
import 'dart:typed_data';

/// Turns a logo that arrives as an opaque picture on a white page into a mark on a transparent background.
///
/// Some broadcasters publish their programme logos as JPEG on white, which sits on the dark interface as a white box.
/// Each pixel is split into the colour it would have on a transparent background and the amount of that colour
/// ("colour to alpha": white becomes clear, black stays solid). A mark that is dark and neutral would vanish on the
/// dark interface, so it is recoloured white; coloured marks keep their colours.
///
/// [rgba] is straight (non-premultiplied) RGBA. Returns null when the picture is not such a logo: it already has
/// transparency, or its border is not white.
Uint8List? knockOutWhiteBackground(Uint8List rgba, int width, int height) {
  if (width < 2 || height < 2 || rgba.length < width * height * 4) return null;
  if (_hasTransparency(rgba) || !_borderIsWhite(rgba, width, height)) return null;

  final out = Uint8List(rgba.length);
  var weight = 0.0;
  var darkness = 0.0;
  var chroma = 0.0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final alpha = 1 - math.min(r, math.min(g, b)) / 255;
    if (alpha < 0.03) continue; // stays fully transparent
    final inverse = 255 * (1 - alpha);
    out[i] = _channel((r - inverse) / alpha);
    out[i + 1] = _channel((g - inverse) / alpha);
    out[i + 2] = _channel((b - inverse) / alpha);
    out[i + 3] = (alpha * 255).round();
    weight += alpha;
    darkness += alpha * (1 - (0.299 * out[i] + 0.587 * out[i + 1] + 0.114 * out[i + 2]) / 255);
    chroma +=
        alpha *
        (math.max(out[i], math.max(out[i + 1], out[i + 2])) - math.min(out[i], math.min(out[i + 1], out[i + 2])));
  }
  if (weight == 0) return null;
  final isDarkAndNeutral = darkness / weight > 0.6 && chroma / weight < 40;
  if (isDarkAndNeutral) {
    for (var i = 0; i < out.length; i += 4) {
      if (out[i + 3] == 0) continue;
      out[i] = out[i + 1] = out[i + 2] = 255;
    }
  }
  return out;
}

int _channel(double value) => value.isNaN ? 0 : value.round().clamp(0, 255);

bool _hasTransparency(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] < 250) return true;
  }
  return false;
}

/// True when the outer ring of pixels is white, as the page of a logo on white is.
bool _borderIsWhite(Uint8List rgba, int width, int height) {
  bool white(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] >= 235 && rgba[i + 1] >= 235 && rgba[i + 2] >= 235;
  }

  var checked = 0;
  var whites = 0;
  void probe(int x, int y) {
    checked++;
    if (white(x, y)) whites++;
  }

  for (var x = 0; x < width; x += math.max(1, width ~/ 40)) {
    probe(x, 0);
    probe(x, height - 1);
  }
  for (var y = 0; y < height; y += math.max(1, height ~/ 40)) {
    probe(0, y);
    probe(width - 1, y);
  }
  return checked > 0 && whites / checked > 0.97;
}
