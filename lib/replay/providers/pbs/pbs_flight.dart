import 'dart:convert';

const _chunkStart = 'self.__next_f.push([1,';

/// The quoted strings of the push calls, quotes included. A scan rather than a pattern: the strings run to hundreds
/// of kilobytes.
Iterable<String> _chunks(String html) sync* {
  var from = 0;
  while (true) {
    final call = html.indexOf(_chunkStart, from);
    if (call < 0) return;
    final open = call + _chunkStart.length;
    if (open >= html.length || html.codeUnitAt(open) != 0x22) {
      from = open;
      continue;
    }
    var i = open + 1;
    while (i < html.length && html.codeUnitAt(i) != 0x22) {
      i += html.codeUnitAt(i) == 0x5C ? 2 : 1;
    }
    if (i >= html.length) return;
    yield html.substring(open, i + 1);
    from = i + 1;
  }
}

/// The JSON values carried by a pbs.org page, one per data line, in the order they appear.
///
/// The site ships its page data inside the HTML as `self.__next_f.push([1,"..."])` chunks. That format is private
/// to the website and can change with any deploy, so everything here skips what it does not understand instead of
/// failing.
List<Object?> pbsFlightValues(String html) {
  final stream = StringBuffer();
  for (final chunk in _chunks(html)) {
    try {
      stream.write(jsonDecode(chunk) as String);
    } on FormatException {
      continue;
    }
  }
  final values = <Object?>[];
  for (final line in stream.toString().split('\n')) {
    final cut = line.indexOf(':');
    if (cut < 1 || cut > 6) continue;
    final body = line.substring(cut + 1);
    if (!body.startsWith('[') && !body.startsWith('{')) continue;
    try {
      values.add(jsonDecode(body));
    } on FormatException {
      continue;
    }
  }
  return values;
}

/// Calls [visit] for every JSON object under [node]. [elementKey] is the React key of the component the object
/// is the properties of, which gives the order in which the page lays its rows out.
void pbsWalk(Object? node, void Function(Map<String, dynamic> object, String? elementKey) visit, [String? elementKey]) {
  if (node is Map<String, dynamic>) {
    visit(node, elementKey);
    for (final value in node.values) {
      pbsWalk(value, visit);
    }
  } else if (node is List) {
    final isElement = node.length == 4 && node[0] == r'$' && node[2] is String;
    for (var i = 0; i < node.length; i++) {
      pbsWalk(node[i], visit, isElement && i == 3 ? node[2] as String : null);
    }
  }
}

/// Every object of the page whose `item_type` is [itemType] and that carries a content id, so stub objects
/// that only repeat a slug and a title are left out.
List<Map<String, dynamic>> pbsItems(List<Object?> values, String itemType) {
  final found = <Map<String, dynamic>>[];
  for (final value in values) {
    pbsWalk(value, (object, _) {
      if (object['item_type'] == itemType && object['cid'] is String) found.add(object);
    });
  }
  return found;
}
