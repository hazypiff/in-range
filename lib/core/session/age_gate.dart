/// Exact, testable 18+ validation shared by auth and profile flows.
class AgeGate {
  AgeGate._();

  static const int minimumAge = 18;

  static DateTime parseIsoDate(String input) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(input.trim());
    if (match == null) {
      throw const FormatException('Enter date of birth as YYYY-MM-DD');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw const FormatException('Enter a valid date of birth');
    }
    return date;
  }

  static bool isAdult(DateTime birthDate, {DateTime? onDate}) {
    final today = _dateOnly(onDate ?? DateTime.now());
    final dob = _dateOnly(birthDate);
    if (dob.isAfter(today) || dob.year < 1900) return false;
    final eighteenth = DateTime(dob.year + minimumAge, dob.month, dob.day);
    return !today.isBefore(eighteenth);
  }

  static int age(DateTime birthDate, {DateTime? onDate}) {
    final today = _dateOnly(onDate ?? DateTime.now());
    var years = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      years--;
    }
    return years;
  }

  static String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
