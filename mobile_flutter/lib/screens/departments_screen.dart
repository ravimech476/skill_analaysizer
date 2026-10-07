import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Standalone departments management screen — CRUD plus bulk import.
class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Departments', _departments()),
      if (session.can(['department.create']))
        ('Import', ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            ImportUpload(
              title: 'departments',
              hint: 'One row per department: code, name and optional HOD employee code.',
              upload: (file, {required dryRun}) => bulkApi.departments(file, dryRun: dryRun),
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

  static Widget _departments() => MasterCrud(
        path: 'departments',
        permission: 'department',
        noun: 'department',
        fields: [
          const MasterField('name', 'Department name', required: true),
          const MasterField('code', 'Code', type: MasterFieldType.upper, required: true),
          MasterField('hod_id', 'Head of department', type: MasterFieldType.reference, lookup: Lookups.staff),
        ],
        title: _departmentTitle,
        badges: _departmentBadges,
      );

  static (String, String?) _departmentTitle(MasterRow r) =>
      ('${r['code']} · ${r['name']}', r['hod_name'] == null ? 'No HOD assigned' : 'HOD: ${r['hod_name']}');

  static List<Widget> _departmentBadges(MasterRow r) => [
        Tag('${asInt(r['student_count'])} students'),
      ];
}
