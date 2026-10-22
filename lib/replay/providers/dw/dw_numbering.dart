/// DW numbers nothing: a season is the calendar year of a video's content date and an episode is the day of that
/// year. Numbers follow broadcast order and can be computed from a single video, so a video opened on its own
/// agrees with the season list it belongs to.
DateTime dwYearStart(int year) => DateTime.utc(year);

/// 1 for January 1st through 365 or 366, counted in UTC.
int dwDayOfYear(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day).difference(DateTime.utc(utc.year)).inDays + 1;
}
