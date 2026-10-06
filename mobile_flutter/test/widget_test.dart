// Smoke tests for the pieces that do not need a server: the access registry that
// decides which screens a role sees, and the formatting helpers every screen uses.

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_analyzer/auth/access.dart';
import 'package:skills_analyzer/widgets/common.dart';

void main() {
  group('audienceOf', () {
    test('the most privileged role wins', () {
      expect(audienceOf(['admin', 'staff']), Audience.admin);
      expect(audienceOf(['staff', 'parent']), Audience.staff);
      expect(audienceOf(['hod']), Audience.staff);
      expect(audienceOf(['placement_officer']), Audience.staff);
      expect(audienceOf(['student']), Audience.student);
      expect(audienceOf(['parent']), Audience.parent);
    });

    test('an unknown role is treated as staff', () {
      expect(audienceOf(['something_new']), Audience.staff);
    });
  });

  group('features', () {
    test('labels adapt to the audience', () {
      final students = features.firstWhere((f) => f.key == 'students');
      expect(students.labelFor(Audience.staff), 'Students');
      expect(students.labelFor(Audience.student), 'My Profile');
      expect(students.labelFor(Audience.parent), 'My Children');
    });

    test('staff-only features are limited by audience', () {
      final classes = features.firstWhere((f) => f.key == 'classes');
      expect(classes.audiences, contains(Audience.staff));
      expect(classes.audiences, isNot(contains(Audience.student)));
    });

    test('every feature key appears in the menu groups or falls into More', () {
      final grouped = menuGroups.values.expand((keys) => keys).toSet();
      // Only keys that exist as features may be listed in a group.
      final keys = features.map((f) => f.key).toSet();
      expect(grouped.difference(keys), isEmpty);
    });

    test('the career and skill screens are available to students', () {
      for (final key in ['careers', 'skills', 'marks', 'placement']) {
        final f = features.firstWhere((x) => x.key == key);
        expect(f.audiences, anyOf(isNull, contains(Audience.student)), reason: key);
      }
    });
  });

  group('formatting', () {
    test('pretty turns a slug into words', () {
      expect(pretty('placement_officer'), 'Placement Officer');
      expect(pretty('ready'), 'Ready');
      expect(pretty(null), '');
    });

    test('lpa formats a package, and an unknown one reads as a dash', () {
      expect(lpa(6), '₹ 6 LPA');
      expect(lpa(6.5), '₹ 6.5 LPA');
      expect(lpa(null), '—');
    });

    test('fmtDate falls back to the raw value when it is not a date', () {
      expect(fmtDate(null), '—');
      expect(fmtDate('not a date'), 'not a date');
      expect(fmtDate('2026-10-03T00:00:00Z', 'yyyy'), '2026');
    });
  });
}
