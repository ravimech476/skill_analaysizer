import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';

/// Standalone companies management screen — CRUD plus bulk import.
class CompaniesScreen extends StatelessWidget {
  const CompaniesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Companies', _companies()),
      if (session.can(['company.create']))
        (
          'Import',
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              ImportUpload(
                title: 'companies',
                hint:
                    'One row per company: name, industry, contact person and optional website.',
                upload: (file, {required dryRun}) =>
                    bulkApi.companies(file, dryRun: dryRun),
              ),
            ],
          )
        ),
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

  static Widget _companies() => MasterCrud(
        path: 'companies',
        permission: 'company',
        noun: 'company',
        fields: const [
          MasterField('name', 'Company name', required: true),
          MasterField('industry', 'Industry'),
          MasterField('location', 'Location'),
          MasterField('website', 'Website'),
          MasterField('contact_person', 'Contact person'),
          MasterField('contact_email', 'Contact email'),
          MasterField('contact_mobile', 'Contact mobile'),
          MasterField('description', 'Notes'),
        ],
        title: _companyTitle,
        badges: _companyBadges,
      );

  static (String, String?) _companyTitle(MasterRow r) => (
        text(r['name']),
        [r['industry'], r['location']].whereType<String>().join(' · '),
      );

  static List<Widget> _companyBadges(MasterRow r) => [
        if (asInt(r['job_role_count']) > 0)
          Tag('${asInt(r['job_role_count'])} drives'),
      ];
}
