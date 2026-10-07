import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../widgets/common.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';

/// Standalone skill catalogue screen — manage the master list of skills.
class SkillMasterScreen extends StatelessWidget {
  const SkillMasterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Skills', _skills()),
      if (session.can(['skill.create']))
        ('Import', ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            ImportUpload(
              title: 'Skills',
              hint: 'One row per skill: name (required), category (programming/framework/database/tool/technical/soft_skill/domain, default technical).',
              upload: bulkApi.skillMaster,
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

  static Widget _skills() => MasterCrud(
        path: 'skills',
        permission: 'skill',
        noun: 'skill',
        fields: const [
          MasterField('name', 'Skill name', required: true),
          MasterField(
            'category',
            'Category',
            type: MasterFieldType.select,
            required: true,
            options: ['programming', 'framework', 'database', 'tool', 'technical', 'soft_skill', 'domain'],
          ),
        ],
        title: _skillTitle,
        badges: _skillBadges,
      );

  static (String, String?) _skillTitle(MasterRow r) => (text(r['name']), pretty(text(r['category'])));

  static List<Widget> _skillBadges(MasterRow r) => [
        if (asInt(r['student_count']) > 0) Tag('${asInt(r['student_count'])} students'),
      ];
}
