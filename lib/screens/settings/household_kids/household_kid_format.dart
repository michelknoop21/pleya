import '../../../i18n/strings.g.dart';
import '../../../profiles/household_kids_store.dart';

/// "6 jaar", "3 maanden" under two years, "Telt niet meer mee" from 18.
String householdAgeLabel(HouseholdKid kid, DateTime now) {
  final h = t.assistant.household;
  final months = kid.monthsAt(now);
  if (months == null || months == 0) return h.ageNewborn;
  if (months < 24) return h.ageMonths(n: months);
  final years = kid.ageAt(now);
  return years == null ? h.ageIgnored : h.ageYears(n: years);
}

/// "maart 2020" for a stored `YYYY-MM`.
String householdMonthLabel(String birthMonth) {
  final y = int.tryParse(birthMonth.substring(0, 4));
  final m = int.tryParse(birthMonth.substring(5, 7));
  if (y == null || m == null || m < 1 || m > 12) return birthMonth;
  return '${t.assistant.household.months[m - 1]} $y';
}

String householdBirthMonth(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';

/// The oldest first, as the list shows them (by birth month ascending).
List<HouseholdKid> householdKidsOldestFirst(List<HouseholdKid> kids) =>
    [...kids]..sort((a, b) => a.birthMonth.compareTo(b.birthMonth));

/// The first selectable year: a child older than 17 never matters.
int householdFirstYear(DateTime now) => now.year - 17;

/// A fresh id for a new child.
String newHouseholdKidId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
