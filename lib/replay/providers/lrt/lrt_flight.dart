import 'dart:convert';

const _pushStart = 'self.__next_f.push([1,';

/// The text the site's Next.js page streams to the browser, with the string escapes of each `push` call removed.
///
/// Pieces are cut at arbitrary points, so objects only exist after they are joined. A piece that is not a valid string
/// literal is skipped instead of failing the page.
String lrtFlightText(String html) {
  final out = StringBuffer();
  var from = 0;
  while (true) {
    final start = html.indexOf(_pushStart, from);
    if (start < 0) break;
    final open = html.indexOf('"', start + _pushStart.length);
    if (open < 0) break;
    final close = _closingQuote(html, open);
    if (close < 0) break;
    from = close + 1;
    try {
      final piece = jsonDecode(html.substring(open, close + 1));
      if (piece is String) out.write(piece);
    } on FormatException {
      continue;
    }
  }
  return out.toString();
}

/// The first JSON object that follows an occurrence of [key] in [text] and that [accept] approves of.
///
/// Braces inside strings do not count, and an occurrence whose object is cut off or malformed is passed over.
Map<String, dynamic>? lrtFlightObject(String text, String key, {bool Function(Map<String, dynamic>)? accept}) {
  var from = 0;
  while (true) {
    final at = text.indexOf(key, from);
    if (at < 0) return null;
    from = at + key.length;
    final open = _skipSpaces(text, from);
    if (open >= text.length || text[open] != '{') continue;
    final close = _closingBrace(text, open);
    if (close < 0) continue;
    try {
      final value = jsonDecode(text.substring(open, close + 1));
      if (value is Map<String, dynamic> && (accept == null || accept(value))) return value;
    } on FormatException {
      continue;
    }
  }
}

int _skipSpaces(String text, int from) {
  var i = from;
  while (i < text.length && (text[i] == ' ' || text[i] == '\n')) {
    i++;
  }
  return i;
}

/// Index of the quote that ends the string literal opened at [open], or -1.
int _closingQuote(String text, int open) {
  var i = open + 1;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x5C) {
      i += 2;
      continue;
    }
    if (c == 0x22) return i;
    i++;
  }
  return -1;
}

int _closingBrace(String text, int open) {
  var depth = 0;
  var inString = false;
  for (var i = open; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (c == 0x5C) {
        i++;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }
    if (c == 0x22) {
      inString = true;
    } else if (c == 0x7B) {
      depth++;
    } else if (c == 0x7D && --depth == 0) {
      return i;
    }
  }
  return -1;
}
