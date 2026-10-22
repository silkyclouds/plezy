import 'package:intl/intl.dart';

/// "12 oct. 2026": the day a title left or will join the catalogue, with its year.
String replayDateWithYear(DateTime date, {required String intlLocale}) =>
    DateFormat.yMMMd(intlLocale).format(date.toLocal());

/// "30 oct.": a day that is close enough for the year to be obvious.
String replayDateWithoutYear(DateTime date, {required String intlLocale}) =>
    DateFormat.MMMd(intlLocale).format(date.toLocal());

/// French writes 20 h 55 and 22 h; other languages use the locale's own time format.
String replayTimeOfDay(DateTime date, {required String language, required String intlLocale}) {
  final local = date.toLocal();
  if (language != 'fr') return DateFormat.jm(intlLocale).format(local);
  return local.minute == 0 ? '${local.hour} h' : '${local.hour} h ${local.minute.toString().padLeft(2, '0')}';
}
