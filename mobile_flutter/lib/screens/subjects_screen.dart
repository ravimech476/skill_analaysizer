import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';

/// Subjects directory with bulk-import tab.
class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Subjects', _subjects()),
      if (session.can(['subject.create']))
        ('Import', ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            ImportUpload(
              title: 'subjects',
              hint: 'One row per subject: code, name, credits and optional department code.',
              upload: (file, {required dryRun}) => bulkApi.subjects(file, dryRun: dryRun),
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

  static Widget _subjects() => MasterCrud(
        path: 'subjects',
        permission: 'subject',
        noun: 'subject',
        fields: const [
          MasterField('code', 'Code', type: MasterFieldType.upper, required: true),
          MasterField('name', 'Subject name', required: true),
          MasterField('credits', 'Credits', type: MasterFieldType.number),
          MasterField('subject_type', 'Type',
              type: MasterFieldType.select, options: ['theory', 'lab', 'elective', 'project']),
        ],
        title: _subjectTitle,
      );

  static (String, String?) _subjectTitle(MasterRow r) =>
      ('${r['code']} · ${r['name']}', '${pretty(text(r['subject_type']))} · ${r['credits']} credits');
}
