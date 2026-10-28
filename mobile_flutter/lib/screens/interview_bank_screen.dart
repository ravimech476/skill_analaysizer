import 'package:flutter/material.dart';

import '../api/models.dart';
import '../widgets/common.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Company-wise interview question bank — CRUD via MasterCrud.
class InterviewBankScreen extends StatelessWidget {
  const InterviewBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'interview-questions',
      permission: 'interview',
      noun: 'question',
      fields: [
        MasterField('company_id', 'Company', type: MasterFieldType.reference, lookup: Lookups.companies),
        const MasterField(
          'category',
          'Category',
          type: MasterFieldType.select,
          options: ['technical', 'aptitude', 'hr', 'coding', 'group_discussion', 'case_study'],
        ),
        const MasterField('question', 'Question', required: true),
        const MasterField('answer', 'Answer'),
        const MasterField(
          'difficulty',
          'Difficulty',
          type: MasterFieldType.select,
          options: ['easy', 'medium', 'hard'],
        ),
        const MasterField('tags', 'Tags', hint: 'Comma separated'),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) => (
        text(r['question']),
        [pretty(text(r['category'])), pretty(text(r['difficulty']))].where((s) => s.isNotEmpty).join(' · '),
      );
}
