import '../../text/html_text.dart';
import 'stvr_images.dart';
import 'stvr_numbering.dart';
import 'stvr_time.dart';

/// One recording of the archive listing: a dated broadcast of a show.
class StvrRecord {
  final int id;
  final int series;
  final String name;
  final String subtitle;
  final String synopsis;
  final String description;
  final String? image;

  /// Air time and licence end as the broadcaster writes them, in Slovak local time. A licence end is empty when the
  /// recording has none.
  final String airLocal;
  final String licenseLocal;

  const StvrRecord({
    required this.id,
    required this.series,
    required this.name,
    required this.subtitle,
    required this.synopsis,
    required this.description,
    required this.image,
    required this.airLocal,
    required this.licenseLocal,
  });

  static StvrRecord? fromJson(Map<String, dynamic> json) {
    final id = _int(json['ID']);
    final series = _int(json['series']);
    final name = stvrTidy(json['name'] as String? ?? '');
    if (id == null || series == null || name.isEmpty) return null;
    return StvrRecord(
      id: id,
      series: series,
      name: name,
      subtitle: stvrTidy(json['subtitle'] as String? ?? ''),
      synopsis: htmlToText(json['synopsis'] as String?),
      description: htmlToText(json['description'] as String?),
      image: stvrAbsoluteImage(json['image'] as String?),
      airLocal: json['air'] as String? ?? '',
      licenseLocal: json['license'] as String? ?? '',
    );
  }

  /// The records of a listing page, without repeats.
  static List<StvrRecord> fromPage(Map<String, dynamic> page) {
    final raw = page['program'];
    if (raw is! List) return const [];
    final seen = <int>{};
    return [
      for (final item in raw.whereType<Map<String, dynamic>>())
        if (StvrRecord.fromJson(item) case final record? when seen.add(record.id)) record,
    ];
  }

  DateTime? get air => stvrParseLocalTime(airLocal);

  DateTime? get licenseEnd => stvrParseLocalTime(licenseLocal);

  /// The air date (`yyyy-mm-dd`) in Slovak local time, which is what the listing filters on.
  String get airDay => airLocal.length >= 10 ? airLocal.substring(0, 10) : '';

  StvrShowName get showName => stvrParseShowName(name);

  /// The number of recordings a listing page says the whole query matches.
  static int totalOf(Map<String, dynamic> page) => _int((page['paging'] as Map?)?['results']) ?? 0;

  static int? _int(Object? value) => switch (value) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };
}
