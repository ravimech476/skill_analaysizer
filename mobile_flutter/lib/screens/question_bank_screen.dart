import 'package:flutter/material.dart';

import '../api/models.dart';
import '../widgets/common.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Previous-year question bank — CRUD via MasterCrud.
class QuestionBankScreen extends StatelessWidget {
  const QuestionBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'question-bank',
      permission: 'question_bank',
      noun: 'question',
      fields: [
        MasterField('subject_id', 'Subject', type: MasterFieldType.reference, lookup: Lookups.subjects, required: true),
        MasterField('exam_type_id', 'Exam Type', type: MasterFieldType.reference, lookup: Lookups.examTypes),
        const MasterField('year', 'Year', type: MasterFieldType.integer, hint: 'e.g. 2024'),
        const MasterField('question', 'Question', required: true),
        const MasterField('marks', 'Marks', type: MasterFieldType.integer),
        const MasterField(
          'blooms_level',
          'Bloom\'s Level',
          type: MasterFieldType.select,
          options: ['remember', 'understand', 'apply', 'analyze', 'evaluate', 'create'],
        ),
        const MasterField('unit', 'Unit', hint: 'e.g. Unit 1'),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) {
    final parts = <String>[
      text(r['subject_name']),
      if (text(r['year']).isNotEmpty) text(r['year']),
      if (text(r['blooms_level']).isNotEmpty) pretty(text(r['blooms_level'])),
      if (asInt(r['marks']) > 0) '${asInt(r['marks'])}m',
    ];
    return (
      text(r['question']),
      parts.where((s) => s.isNotEmpty).join(' · '),
    );
  }
}
