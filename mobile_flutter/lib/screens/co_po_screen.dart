import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// CO/PO Mapping — three tabs: Program Outcomes, Course Outcomes, CO-PO Mapping.
class CoPoScreen extends StatelessWidget {
  const CoPoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Brand.accent,
            unselectedLabelColor: Brand.textSoft,
            indicatorColor: Brand.accent,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'PO'),
              Tab(text: 'CO'),
              Tab(text: 'Mapping'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _ProgramOutcomesTab(),
                _CourseOutcomesTab(),
                _CoPoMappingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramOutcomesTab extends StatelessWidget {
  const _ProgramOutcomesTab();

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'program-outcomes',
      permission: 'course_outcome',
      noun: 'program outcome',
      fields: [
        const MasterField('code', 'Code', required: true, hint: 'e.g. PO1'),
        const MasterField('description', 'Description', required: true),
        MasterField('department_id', 'Department', type: MasterFieldType.reference, lookup: Lookups.departments),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) => (
        '${text(r['code'])} — ${text(r['description'])}',
        text(r['department_name']),
      );
}

class _CourseOutcomesTab extends StatelessWidget {
  const _CourseOutcomesTab();

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'course-outcomes',
      permission: 'course_outcome',
      noun: 'course outcome',
      fields: [
        const MasterField('code', 'Code', required: true, hint: 'e.g. CO1'),
        const MasterField('description', 'Description', required: true),
        MasterField('subject_id', 'Subject', type: MasterFieldType.reference, lookup: Lookups.subjects, required: true),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) => (
        '${text(r['code'])} — ${text(r['description'])}',
        text(r['subject_name']),
      );
}

class _CoPoMappingTab extends StatelessWidget {
  const _CoPoMappingTab();

  @override
  Widget build(BuildContext context) {
    return MasterCrud(
      path: 'co-po-mappings',
      permission: 'course_outcome',
      noun: 'mapping',
      fields: [
        MasterField('course_outcome_id', 'Course Outcome', type: MasterFieldType.reference, lookup: Lookups.courseOutcomes, required: true),
        MasterField('program_outcome_id', 'Program Outcome', type: MasterFieldType.reference, lookup: Lookups.programOutcomes, required: true),
        const MasterField(
          'correlation_level',
          'Correlation Level',
          type: MasterFieldType.select,
          options: ['1', '2', '3'],
          required: true,
          hint: '1 = Low, 2 = Medium, 3 = High',
        ),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) => (
        '${text(r['course_outcome_code'], 'CO')} → ${text(r['program_outcome_code'], 'PO')}',
        'Level ${text(r['correlation_level'])}',
      );
}
