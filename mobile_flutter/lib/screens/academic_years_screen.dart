import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';

/// Academic years directory with bulk-import tab.
class AcademicYearsScreen extends StatelessWidget {
  const AcademicYearsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Academic Years', _years()),
      if (session.can(['academic_year.create']))
        ('Import', ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            ImportUpload(
              title: 'Academic Years',
              hint: 'One row per year: name (required, e.g. 2026-27), start_date (YYYY-MM-DD), end_date (YYYY-MM-DD), is_current (true/false).',
              upload: (file, {required dryRun}) => bulkApi.academicYears(file, dryRun: dryRun),
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

  static Widget _years() => MasterCrud(
        path: 'academic-years',
        permission: 'academic_year',
        noun: 'academic year',
        searchable: false,
        fields: const [
          MasterField('name', 'Name', required: true, hint: 'e.g. 2026-27'),
          MasterField('start_date', 'Start date', required: true, hint: 'YYYY-MM-DD'),
          MasterField('end_date', 'End date', required: true, hint: 'YYYY-MM-DD'),
          MasterField('is_current', 'Current year', type: MasterFieldType.boolean),
        ],
        title: _yearTitle,
        badges: _yearBadges,
      );

  static (String, String?) _yearTitle(MasterRow r) =>
      (text(r['name']), '${fmtDate(text(r['start_date']))} – ${fmtDate(text(r['end_date']))}');

  static List<Widget> _yearBadges(MasterRow r) => [
        if (asBool(r['is_current'])) const Tag('Current', color: Brand.accent),
      ];
}
