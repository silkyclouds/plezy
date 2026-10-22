/// Parses the ISO 8601 timestamps of the catalogue ("2026-08-15T02:00+02:00") into UTC, or null.
DateTime? svtDate(Object? iso) => iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
