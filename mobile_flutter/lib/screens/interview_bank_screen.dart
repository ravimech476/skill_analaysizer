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

const _types = ['mixed', 'technical', 'aptitude', 'hr', 'coding', 'group_discussion', 'case_study'];

/// Interview Bank: company interview documents (questions and answers as PDF or Word files) for everyone,
/// plus the one-by-one question list and its Excel import for staff.
class InterviewBankScreen extends StatelessWidget {
  const InterviewBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final staff = session.can(['interview.create']);
    final tabs = <(String, Widget)>[
      ('Documents', _documents(session)),
      if (staff) ('Questions', _questions()),
      if (staff)
        (
          'Import questions',
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              ImportUpload(
                title: 'interview questions',
                hint: 'One row per question: company (optional), category, question, answer and difficulty. '
                    'Questions that already exist are skipped.',
                upload: (file, {required dryRun}) => bulkApi.interviewQuestions(file, dryRun: dryRun),
              ),
            ],
          )
        ),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: TabBar(tabs: tabs.map((t) => Tab(text: t.$1)).toList(), isScrollable: tabs.length > 2),
        body: TabBarView(children: tabs.map((t) => t.$2).toList()),
      ),
    );
  }

  static Widget _documents(Session session) {
    final canEdit = session.can(['interview.update']);
    final canIndex = session.can(['kb.manage']);
    return MasterCrud(
      path: 'interview-documents',
      permission: 'interview',
      noun: 'document',
      fields: [
        MasterField('company_id', 'Company', type: MasterFieldType.reference, lookup: Lookups.companies, required: true),
        const MasterField('title', 'Title', required: true, hint: 'e.g. TCS NQT interview questions and answers 2025'),
        const MasterField('doc_type', 'Type', type: MasterFieldType.select, options: _types),
        const MasterField('role', 'Role or drive', hint: 'Optional, e.g. Ninja'),
        const MasterField('year', 'Year', type: MasterFieldType.integer, hint: 'e.g. 2025'),
        const MasterField('description', 'Description'),
        const MasterField('tags', 'Tags', hint: 'Comma separated'),
      ],
      title: (r) => (
        text(r['title']),
        [
          text(r['company_name']),
          pretty(text(r['doc_type'])),
          if (text(r['year']).isNotEmpty) text(r['year']),
          if (FileLink.from(r['file']) != null) FileLink.from(r['file'])!.name,
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      badges: (r) => [
        if (FileLink.from(r['file']) != null)
          const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.attach_file, size: 18, color: Brand.accent)),
      ],
      rowActions: (r) => documentRowActions(r, path: 'interview-documents', category: 'interview_document', canEdit: canEdit, canIndex: canIndex),
      toolbar: session.can(['interview.create']) && canEdit
          ? (context, reload) => UploadDocumentsButton(
                title: 'Upload interview documents',
                masterPath: 'interview-documents',
                category: 'interview_document',
                fields: [
                  UploadField.reference('company_id', 'Company', lookup: Lookups.companies, required: true),
                  const UploadField.select('doc_type', 'Type', options: _types, required: true, initial: 'mixed'),
                  const UploadField.integer('year', 'Year (optional)'),
                ],
                onDone: reload,
              )
          : null,
    );
  }

  static Widget _questions() => MasterCrud(
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

  static (String, String?) _title(MasterRow r) => (
        text(r['question']),
        [pretty(text(r['category'])), pretty(text(r['difficulty']))].where((s) => s.isNotEmpty).join(' · '),
      );
}
