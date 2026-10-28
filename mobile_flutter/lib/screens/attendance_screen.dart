import 'package:flutter/material.dart';

import '../api/models.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Subject-wise attendance records — CRUD via MasterCrud.
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'attendance',
      permission: 'attendance',
      noun: 'record',
      fields: [
        MasterField('student_id', 'Student', type: MasterFieldType.reference, lookup: Lookups.students, required: true),
        MasterField('class_id', 'Class', type: MasterFieldType.reference, lookup: Lookups.classes, required: true),
        MasterField('subject_id', 'Subject', type: MasterFieldType.reference, lookup: Lookups.subjects, required: true),
        const MasterField('total_classes', 'Total Classes', type: MasterFieldType.integer, required: true),
        const MasterField('classes_attended', 'Attended', type: MasterFieldType.integer, required: true),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) {
    final attended = asInt(r['classes_attended']);
    final total = asInt(r['total_classes']);
    final pct = total > 0 ? (attended / total * 100).toStringAsFixed(0) : '0';
    return (
      text(r['student_name'], 'Student #${text(r['student_id'])}'),
      '${text(r['subject_name'], 'Subject')} · $attended/$total ($pct%)',
    );
  }
}
