import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/settings_service.dart';

/// One child of the household, as a parent entered it: a name (never sent to
/// the model) and the birth month as `YYYY-MM`.
class HouseholdKid {
  const HouseholdKid({required this.id, required this.name, required this.birthMonth});
  final String id;
  final String name;
  final String birthMonth;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'birthMonth': birthMonth};

  static HouseholdKid? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'], month = json['birthMonth'];
    if (id is! String || name is! String || month is! String || _month.firstMatch(month) == null) return null;
    return HouseholdKid(id: id, name: name, birthMonth: month);
  }

  static final _month = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

  /// Whole months since the birth month in [now]; null for a future month.
  int? monthsAt(DateTime now) {
    final m = _month.firstMatch(birthMonth);
    if (m == null) return null;
    final diff = (now.year - int.parse(m[1]!)) * 12 + now.month - int.parse(m[2]!);
    return diff < 0 ? null : diff;
  }

  /// Whole years of age in [now], strict: the birthday counts from the month
  /// after the birth month. Null for a birth month in the future or a child
  /// of 18 or older, so neither ever sets the gate.
  int? ageAt(DateTime now) {
    final m = _month.firstMatch(birthMonth);
    if (m == null) return null;
    final diff = (now.year - int.parse(m[1]!)) * 12 + now.month - int.parse(m[2]!);
    if (diff < 0) return null;
    final age = diff == 0 ? 0 : (diff - 1) ~/ 12;
    return age >= 18 ? null : age;
  }
}

/// The age that gates titles when a question is about the children: the
/// youngest of [kids] (only those in [ids] when given) that has a valid age.
int? householdGateAge(List<HouseholdKid> kids, DateTime now, {Set<String> ids = const {}}) {
  final ages = [
    for (final k in kids)
      if (ids.isEmpty || ids.contains(k.id)) ?k.ageAt(now),
  ];
  return ages.isEmpty ? null : ages.reduce((a, b) => a < b ? a : b);
}

/// The household's children, under one global key. Local to this device and
/// never synced or exported (device-local runtime cache). Every profile reads
/// it for the age gate; only a profile that is not a children's profile may
/// change it.
class HouseholdKidsStore {
  static const _pref = StringPref('household_kids');

  /// At most this many children; [save] refuses more.
  static const maxKids = 8;

  /// Bumps after every save, so a screen that shows the children re-reads.
  static final changes = ValueNotifier<int>(0);

  Future<List<HouseholdKid>> read() async {
    final raw = (await SettingsService.getInstance()).read(_pref);
    if (raw.isEmpty) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) ?HouseholdKid.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  /// Saves [kids]; refused (false) on a children's profile or above [maxKids].
  Future<bool> save(List<HouseholdKid> kids, {required bool kidsProfile}) async {
    if (kidsProfile || kids.length > maxKids) return false;
    await (await SettingsService.getInstance()).write(_pref, jsonEncode([for (final k in kids) k.toJson()]));
    changes.value++;
    return true;
  }
}
