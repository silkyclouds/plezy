import 'dart:convert';

import 'ardmediathek_json.dart';

// Alternate versions of a programme are listed next to it as separate items: the audio-described copy, the one
// with a sign-language interpreter and the original-language one. They are the same programme to the viewer.
final _versionSuffix = RegExp(
  r'\((?:Audiodeskription|mit Gebärdensprache|Originalversion[^)]*|Originalfassung[^)]*|Hörfassung)\)\s*$',
  caseSensitive: false,
);
final _versionIdTails = ['/audiodeskription', '/gebaerdensprache'];

/// Whether [teaser] is an audio-described, sign-language or original-language copy of another item.
bool ardIsAlternateVersion(Map<String, dynamic> teaser) {
  final title = ardText(teaser['longTitle']) ?? ardText(teaser['mediumTitle']) ?? ardText(teaser['shortTitle']);
  if (title != null && _versionSuffix.hasMatch(title)) return true;
  final id = ardText(teaser['id']);
  if (id == null) return false;
  final crid = _decode(id);
  return crid != null && _versionIdTails.any(crid.endsWith);
}

// Ids are the unpadded base64url form of a crid.
String? _decode(String id) {
  try {
    return utf8.decode(base64Url.decode(base64Url.normalize(id)), allowMalformed: true);
  } on FormatException {
    return null;
  }
}
