import 'package:flutter/material.dart';

import '../api/models.dart';
import '../widgets/common.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Study materials per subject — CRUD via MasterCrud.
class StudyMaterialsScreen extends StatelessWidget {
  const StudyMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'study-materials',
      permission: 'study_material',
      noun: 'material',
      fields: [
        MasterField('subject_id', 'Subject', type: MasterFieldType.reference, lookup: Lookups.subjects, required: true),
        const MasterField('title', 'Title', required: true),
        const MasterField(
          'material_type',
          'Type',
          type: MasterFieldType.select,
          options: ['notes', 'question_paper', 'slides', 'reference', 'video', 'link'],
        ),
        const MasterField('description', 'Description'),
        const MasterField('url', 'URL / Link'),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) => (
        text(r['title']),
        pretty(text(r['material_type'])),
      );
}
