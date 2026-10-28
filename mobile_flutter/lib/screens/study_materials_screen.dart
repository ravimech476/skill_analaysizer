import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/document_library.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Study materials per subject: a list with attached files, and an Excel import.
class StudyMaterialsScreen extends StatelessWidget {
  const StudyMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Study materials', _list(session)),
      if (session.can(['study_material.create']))
        (
          'Import',
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              ImportUpload(
                title: 'study materials',
                hint: 'One row per material: subject code, title, type and an optional link. '
                    'Files are attached afterwards from the list.',
                upload: (file, {required dryRun}) => bulkApi.studyMaterials(file, dryRun: dryRun),
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

  static FileLink? _file(MasterRow r) => FileLink.from(r['file']);


  Widget _list(Session session) {
    final canEdit = session.can(['study_material.update']);
    final canIndex = session.can(['kb.manage']);
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
        const MasterField('url', 'URL / Link', hint: 'To upload a file instead, save the material and use "Attach file" in its menu'),
      ],
      title: _title,
      badges: (r) => [
        if (_file(r) != null) const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.attach_file, size: 18, color: Brand.accent)),
      ],
      rowActions: (r) => documentRowActions(r, path: 'study-materials', category: 'study_material', canEdit: canEdit, canIndex: canIndex),
      toolbar: session.can(['study_material.create']) && canEdit
          ? (context, reload) => UploadDocumentsButton(
                title: 'Upload study materials',
                masterPath: 'study-materials',
                category: 'study_material',
                fields: [
                  UploadField.reference('subject_id', 'Subject', lookup: Lookups.subjects, required: true),
                  const UploadField.select('material_type', 'Type',
                      options: ['notes', 'question_paper', 'slides', 'reference', 'video', 'link'], required: true, initial: 'notes'),
                ],
                onDone: reload,
              )
          : null,
    );
  }

  static (String, String?) _title(MasterRow r) {
    final file = _file(r);
    return (
      text(r['title']),
      [
        pretty(text(r['material_type'])),
        if (text(r['subject_name']).isNotEmpty) text(r['subject_name']),
        if (file != null) file.name,
      ].join(' · '),
    );
  }
}
