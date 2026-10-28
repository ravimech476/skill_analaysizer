import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/document_library.dart';
import '../widgets/import_upload.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';
import 'blooms_review_screen.dart';

const _levels = [
  'remember',
  'understand',
  'apply',
  'analyze',
  'evaluate',
  'create',
];

/// Previous-year question bank — CRUD via MasterCrud, with AI suggestions for the Bloom's level.
class QuestionBankScreen extends StatelessWidget {
  const QuestionBankScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Question papers', _papers(session)),
      if (session.can(['question_bank.create'])) ('Questions', _list(context)),
      if (session.can(['question_bank.create']))
        (
          'Import questions',
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              ImportUpload(
                title: 'questions',
                hint: 'One row per question: subject code, question, marks, year and exam type. '
                    'Leave the Bloom\'s level empty to set it from the question\'s action verb.',
                upload: (file, {required dryRun}) => bulkApi.questionBank(file, dryRun: dryRun),
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

  static const _paperTypes = ['question_paper', 'model_paper', 'important_questions', 'answer_key'];

  /// Question papers: one row per paper (a PDF or Word file) with its subject, exam, year and marks.
  Widget _papers(Session session) {
    final canEdit = session.can(['question_bank.update']);
    final canIndex = session.can(['kb.manage']);
    return MasterCrud(
      path: 'question-papers',
      permission: 'question_bank',
      noun: 'paper',
      fields: [
        MasterField('subject_id', 'Subject', type: MasterFieldType.reference, lookup: Lookups.subjects, required: true),
        const MasterField('title', 'Title', required: true, hint: 'e.g. Data Structures end semester, Nov 2024'),
        const MasterField('doc_type', 'Document type', type: MasterFieldType.select, options: _paperTypes),
        MasterField('exam_type_id', 'Exam type', type: MasterFieldType.reference, lookup: Lookups.examTypes),
        const MasterField('year', 'Year', type: MasterFieldType.integer, hint: 'e.g. 2024'),
        const MasterField('semester', 'Semester', hint: 'e.g. Semester 4'),
        const MasterField('unit', 'Unit', hint: 'Optional'),
        const MasterField('max_marks', 'Max marks', type: MasterFieldType.integer),
        const MasterField('description', 'Description'),
      ],
      title: (r) => (
        text(r['title']),
        [
          text(r['subject_name']),
          text(r['exam_type_name']),
          if (text(r['year']).isNotEmpty) text(r['year']),
          if (FileLink.from(r['file']) != null) FileLink.from(r['file'])!.name,
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      badges: (r) => [
        if (FileLink.from(r['file']) != null)
          const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.attach_file, size: 18, color: Brand.accent)),
      ],
      rowActions: (r) => documentRowActions(r, path: 'question-papers', category: 'question_paper', canEdit: canEdit, canIndex: canIndex),
      toolbar: session.can(['question_bank.create']) && canEdit
          ? (context, reload) => UploadDocumentsButton(
                title: 'Upload question papers',
                masterPath: 'question-papers',
                category: 'question_paper',
                fields: [
                  UploadField.reference('subject_id', 'Subject', lookup: Lookups.subjects, required: true),
                  const UploadField.select('doc_type', 'Document type', options: _paperTypes, required: true, initial: 'question_paper'),
                  UploadField.reference('exam_type_id', 'Exam type (optional)', lookup: Lookups.examTypes),
                  const UploadField.integer('year', 'Year (optional)'),
                  const UploadField.text('semester', 'Semester (optional)'),
                ],
                onDone: reload,
              )
          : null,
    );
  }

  Widget _list(BuildContext context) {
    final canReview = context.watch<Session>().can(['question_bank.update']);
    return MasterCrud(
      path: 'question-bank',
      permission: 'question_bank',
      noun: 'question',
      toolbar: canReview
          ? (context, reload) => OutlinedButton.icon(
              onPressed: () async {
                final changed = await push<bool>(
                  context,
                  const SubPage(
                    title: 'Review Bloom\'s levels',
                    child: BloomsReviewScreen(),
                  ),
                );
                if (changed == true) reload();
              },
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Review Bloom\'s levels'),
            )
          : null,
      fields: [
        MasterField(
          'subject_id',
          'Subject',
          type: MasterFieldType.reference,
          lookup: Lookups.subjects,
          required: true,
        ),
        MasterField(
          'exam_type_id',
          'Exam Type',
          type: MasterFieldType.reference,
          lookup: Lookups.examTypes,
        ),
        const MasterField(
          'year',
          'Year',
          type: MasterFieldType.integer,
          hint: 'e.g. 2024',
        ),
        const MasterField('question', 'Question', required: true),
        const MasterField('marks', 'Marks', type: MasterFieldType.integer),
        MasterField(
          'blooms_level',
          'Bloom\'s Level',
          type: MasterFieldType.select,
          options: _levels,
          after: (form) => _SuggestLevel(form: form),
        ),
        const MasterField('unit', 'Unit', hint: 'e.g. Unit 1'),
      ],
      title: _title,
    );
  }

  static (String, String?) _title(MasterRow r) {
    final parts = <String>[
      text(r['subject_name']),
      if (text(r['year']).isNotEmpty) text(r['year']),
      if (text(r['blooms_level']).isNotEmpty) pretty(text(r['blooms_level'])),
      if (asInt(r['marks']) > 0) '${asInt(r['marks'])}m',
    ];
    return (text(r['question']), parts.where((s) => s.isNotEmpty).join(' · '));
  }
}

/// Under the Bloom's field of the question form: asks the AI and lets staff drop the answer into the field.
class _SuggestLevel extends StatefulWidget {
  const _SuggestLevel({required this.form});
  final MasterFormAccess form;

  @override
  State<_SuggestLevel> createState() => _SuggestLevelState();
}

class _SuggestLevelState extends State<_SuggestLevel> {
  bool _busy = false;
  BloomSuggestion? _result;
  String? _error;

  Future<void> _suggest() async {
    final question = widget.form.textOf('question').trim();
    if (question.isEmpty) {
      setState(() {
        _result = null;
        _error = 'Type the question first';
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final marks = int.tryParse(widget.form.textOf('marks').trim()) ?? 0;
      final r = await bloomsApi.suggest(question, marks);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _suggest,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lightbulb_outline, size: 18),
              label: const Text('Suggest level with AI'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(color: Brand.error, fontSize: 12.5),
              ),
            ),
          if (r != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (r.confidence == 'low' ? Brand.warning : Brand.info)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [BloomTag(r.level), ConfidenceTag(r.confidence)],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.reason,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Brand.textSoft,
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () {
                      widget.form.setValue('blooms_level', r.level);
                      setState(() => _result = null);
                    },
                    child: Text('Use “${pretty(r.level)}”'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
