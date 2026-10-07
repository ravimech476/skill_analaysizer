import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';

/// Exam types directory with bulk-import tab.
class ExamTypesScreen extends StatelessWidget {
  const ExamTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Exam Types', _examTypes()),
      if (session.can(['exam_type.create']))
        ('Import', ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            ImportUpload(
              title: 'Exam Types',
              hint: 'One row per exam type: code (required), name (required), max_marks (required), pass_percent (default 50), is_final (true/false), sort_order.',
              upload: (file, {required dryRun}) => bulkApi.examTypes(file, dryRun: dryRun),
            ),
          ],
        )),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: TabBar(tabs: tabs.map((t) => Tab(text: t.$1)).toList()),
        body: TabBarView(children: tabs.map((t) => t.$2).toList()),
      ),
    );
  }

  static Widget _examTypes() => MasterCrud(
        path: 'exam-types',
        permission: 'exam_type',
        noun: 'exam type',
        searchable: false,
        fields: const [
          MasterField('name', 'Name', required: true),
          MasterField('code', 'Code', type: MasterFieldType.upper, required: true),
          MasterField('max_marks', 'Maximum marks', type: MasterFieldType.number, required: true),
          MasterField('pass_percent', 'Pass percentage', type: MasterFieldType.number),
          MasterField('sort_order', 'Order', type: MasterFieldType.integer),
          MasterField('is_final', 'Final exam (graded, counts towards CGPA)', type: MasterFieldType.boolean),
        ],
        title: _examTitle,
        badges: _examBadges,
      );

  static (String, String?) _examTitle(MasterRow r) =>
      ('${r['code']} · ${r['name']}', 'out of ${r['max_marks']} · pass at ${r['pass_percent']}%');

  static List<Widget> _examBadges(MasterRow r) => [
        if (asBool(r['is_final'])) const Tag('Final', color: Brand.accent),
      ];
}
