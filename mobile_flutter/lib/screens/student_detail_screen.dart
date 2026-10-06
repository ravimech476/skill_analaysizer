import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/pickers.dart';
import 'careers_screen.dart';
import 'marks_screen.dart';
import 'placement_screen.dart';
import 'skills_screen.dart';
import 'students_screen.dart';

/// Everything about one student, in the tabs the web app uses: profile, marks,
/// skills, careers, placement, documents and history.
class StudentDetailScreen extends StatefulWidget {
  const StudentDetailScreen({super.key, required this.studentId});
  final int studentId;

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AsyncView<Student>(
      refreshKey: _reload,
      scrollable: false,
      load: () => studentsApi.get(widget.studentId),
      builder: (context, student, reload) {
        final tabs = <(String, Widget)>[
          ('Profile', _ProfileTab(student: student, onChanged: () => setState(() => _reload++))),
          if (session.can(['marks.view'])) ('Marks', MarkHistoryView(studentId: student.id)),
          if (session.can(['student_skill.view'])) ('Skills', StudentSkillsView(studentId: student.id)),
          if (session.can(['career.view'])) ('Careers', CareerMatchesView(studentId: student.id)),
          if (session.can(['placement.view', 'job_role.view']))
            ('Placement', StudentOpportunitiesView(studentId: student.id, mode: 'drives')),
          ('Documents', _DocumentsTab(student: student)),
          if (session.can(['promotion.view'])) ('History', _HistoryTab(studentId: student.id)),
        ];

        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            backgroundColor: Brand.layout,
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.name, overflow: TextOverflow.ellipsis),
                  Text(student.subtitle,
                      style: const TextStyle(fontSize: 12, color: Brand.textSoft, fontWeight: FontWeight.w400)),
                ],
              ),
              actions: [
                if (session.can(['student.update']))
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      if (await showStudentForm(context, student: student)) setState(() => _reload++);
                    },
                  ),
                if (session.can(['promotion.create'])) _lifecycleMenu(context, student),
              ],
              bottom: TabBar(tabs: tabs.map((t) => Tab(text: t.$1)).toList()),
            ),
            body: TabBarView(children: tabs.map((t) => t.$2).toList()),
          ),
        );
      },
    );
  }

  Widget _lifecycleMenu(BuildContext context, Student student) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) => [
          if (student.lifecycle == 'studying')
            const PopupMenuItem(value: 'discontinue', child: Text('Mark as discontinued')),
          if (student.lifecycle != 'studying') const PopupMenuItem(value: 'readmit', child: Text('Re-admit')),
        ],
        onSelected: (action) async {
          final remarks = await _askRemarks(context, action == 'discontinue' ? 'Discontinue student' : 'Re-admit student');
          if (remarks == null) return;
          int? classId;
          if (action == 'readmit') {
            classId = await showDialog<int>(
              context: context,
              builder: (ctx) => _ClassPickDialog(),
            );
            if (classId == null) return;
          }
          final ok = await runAction(
            context,
            () => lifecycleApi.studentAction(student.id, {
              'action': action,
              if (classId != null) 'class_id': classId,
              if (remarks.isNotEmpty) 'remarks': remarks,
            }),
            success: action == 'discontinue' ? 'Marked as discontinued' : 'Re-admitted',
          );
          if (ok) setState(() => _reload++);
        },
      );
}

Future<String?> _askRemarks(BuildContext context, String title) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Remarks (optional)'),
        maxLines: 2,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirm')),
      ],
    ),
  );
}

class _ClassPickDialog extends StatefulWidget {
  @override
  State<_ClassPickDialog> createState() => _ClassPickDialogState();
}

class _ClassPickDialogState extends State<_ClassPickDialog> {
  int? _classId;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Re-admit into which class?'),
        content: RefPicker(
          hint: 'Class',
          allowClear: false,
          load: Lookups.classes,
          value: _classId,
          onChanged: (v) => setState(() => _classId = v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _classId == null ? null : () => Navigator.pop(context, _classId),
            child: const Text('Re-admit'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- profile

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.student, required this.onChanged});
  final Student student;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final canManage = session.isStaff || session.user?.id == student.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Avatar(name: student.name, photo: student.photo, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(student.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('${student.registerNo} · ${student.username}',
                          style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Tag('CGPA ${student.cgpa.toStringAsFixed(2)}', color: Brand.accent),
                        if (student.backlogCount > 0) Tag('${student.backlogCount} backlog(s)', color: Brand.error),
                        StatusTag(student.lifecycle),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (canManage) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Photo',
            child: FileSlot(
              category: 'profile_photo',
              current: student.photo,
              onChanged: (fileId, _) async {
                await filesApi.setUserPhoto(student.id, fileId);
                onChanged();
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        SectionCard(
          title: 'Details',
          child: Column(
            children: [
              DetailRow('Department', student.departmentName),
              DetailRow('Class', student.classLabel),
              DetailRow('Class incharge', student.inchargeName),
              DetailRow('Batch', student.batch),
              DetailRow('Admission year', '${student.admissionYear}'),
              DetailRow('Mobile', student.mobile),
              DetailRow('Email', student.email),
              DetailRow('Date of birth', student.dob == null ? null : fmtDate(student.dob)),
              DetailRow('Gender', pretty(student.gender)),
              DetailRow('Blood group', student.bloodGroup),
              DetailRow('Address', student.address),
              if (student.passedOutYear != null) DetailRow('Passed out', '${student.passedOutYear}'),
              if (student.statusRemarks != null) DetailRow('Remarks', student.statusRemarks),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Resume',
          child: FileSlot(
            category: 'resume',
            current: student.resume,
            canEdit: canManage,
            onChanged: (fileId, _) async {
              await filesApi.setResume(student.id, fileId);
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 10),
        _ParentsCard(student: student, onChanged: onChanged),
      ],
    );
  }
}

class _ParentsCard extends StatelessWidget {
  const _ParentsCard({required this.student, required this.onChanged});
  final Student student;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['student.update']);
    return SectionCard(
      title: 'Parents',
      trailing: canEdit
          ? TextButton.icon(
              onPressed: () async {
                final added = await showFormSheet<bool>(context, 'Link a parent', (ctx) => _ParentForm(student: student));
                if (added == true) onChanged();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Link'),
            )
          : null,
      child: student.parents.isEmpty
          ? const Text('No parents linked yet', style: TextStyle(fontSize: 13, color: Brand.muted))
          : Column(
              children: student.parents
                  .map((p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(name: p.name, radius: 17),
                        title: Text(p.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${pretty(p.relation)}${p.isPrimary ? ' · primary' : ''} · ${p.mobile ?? p.username}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        trailing: canEdit
                            ? IconButton(
                                icon: const Icon(Icons.link_off, size: 18, color: Brand.error),
                                onPressed: () async {
                                  if (!await confirm(context, 'Unlink ${p.name}?', danger: true, okLabel: 'Unlink')) {
                                    return;
                                  }
                                  final ok = await runAction(
                                    context,
                                    () => studentsApi.removeParent(student.id, p.id),
                                    success: 'Parent unlinked',
                                  );
                                  if (ok) onChanged();
                                },
                              )
                            : null,
                      ))
                  .toList(),
            ),
    );
  }
}

class _ParentForm extends StatefulWidget {
  const _ParentForm({required this.student});
  final Student student;

  @override
  State<_ParentForm> createState() => _ParentFormState();
}

class _ParentFormState extends State<_ParentForm> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  String _relation = 'father';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A parent already registered with this mobile number is linked rather than created again, '
            'so siblings share one login.',
            style: TextStyle(fontSize: 12.5, color: Brand.textSoft),
          ),
          const SizedBox(height: 14),
          Field('Name', child: TextField(controller: _name)),
          Field('Mobile', child: TextField(controller: _mobile, keyboardType: TextInputType.phone)),
          Field('Email', child: TextField(controller: _email, keyboardType: TextInputType.emailAddress)),
          Field(
            'Relation',
            child: EnumPicker(
              value: _relation,
              options: const ['father', 'mother', 'guardian'],
              onChanged: (v) => setState(() => _relation = v ?? 'father'),
            ),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runAction(
                      context,
                      () => studentsApi.addParent(widget.student.id, {
                        'name': _name.text.trim(),
                        'mobile': _mobile.text.trim(),
                        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
                        'relation': _relation,
                      }),
                      success: 'Parent linked',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: const Text('Link parent'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- documents

class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab({required this.student});
  final Student student;

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final canVerify = session.can(['document.verify']);
    final canAdd = session.isStaff || session.user?.id == widget.student.id;

    return AsyncView<Map<String, dynamic>>(
      refreshKey: _reload,
      load: () => documentsApi.of(widget.student.id),
      builder: (context, data, reload) {
        final docs = maps(data['documents']).map(StudentDocument.new).toList();
        final types = ((data['types'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canAdd)
              SectionCard(
                title: 'Upload a document',
                subtitle: 'Mark sheets, certificates and ID proofs. Staff uploads are verified automatically.',
                child: FilledButton.icon(
                  onPressed: () async {
                    final added = await showFormSheet<bool>(
                      context,
                      'Upload a document',
                      (ctx) => _DocumentForm(studentId: widget.student.id, types: types),
                    );
                    if (added == true) setState(() => _reload++);
                  },
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Choose a file'),
                ),
              ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const EmptyView('No documents uploaded yet')
            else
              ...docs.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DocumentCard(
                      doc: d,
                      canVerify: canVerify,
                      onChanged: () => setState(() => _reload++),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc, required this.canVerify, required this.onChanged});
  final StudentDocument doc;
  final bool canVerify;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(doc.title.isEmpty ? doc.docTypeLabel : doc.title,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  StatusTag(doc.status),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${doc.docTypeLabel} · uploaded by ${doc.uploadedBy ?? 'unknown'} on ${fmtDate(doc.createdAt)}',
                style: const TextStyle(fontSize: 12, color: Brand.textSoft),
              ),
              if (doc.remarks != null) ...[
                const SizedBox(height: 4),
                Text('Remarks: ${doc.remarks}', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
              ],
              if (doc.file != null) ...[
                const SizedBox(height: 10),
                FileTile(link: doc.file!, dense: true),
              ],
              if (canVerify && doc.status == 'pending') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Brand.success, minimumSize: const Size(0, 38)),
                        onPressed: () async {
                          final ok = await runAction(
                            context,
                            () => documentsApi.review(doc.studentId, doc.id, 'verified'),
                            success: 'Verified',
                          );
                          if (ok) onChanged();
                        },
                        child: const Text('Verify'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Brand.error, minimumSize: const Size(0, 38)),
                        onPressed: () async {
                          final remarks = await _askRemarks(context, 'Reject this document');
                          if (remarks == null) return;
                          final ok = await runAction(
                            context,
                            () => documentsApi.review(doc.studentId, doc.id, 'rejected', remarks: remarks),
                            success: 'Rejected',
                          );
                          if (ok) onChanged();
                        },
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _DocumentForm extends StatefulWidget {
  const _DocumentForm({required this.studentId, required this.types});
  final int studentId;
  final Map<String, String> types;

  @override
  State<_DocumentForm> createState() => _DocumentFormState();
}

class _DocumentFormState extends State<_DocumentForm> {
  final _title = TextEditingController();
  String? _type;
  FileLink? _file;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typeKeys = widget.types.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field(
          'Document type',
          child: DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            hint: const Text('Select'),
            items: typeKeys
                .map((k) => DropdownMenuItem(value: k, child: Text(widget.types[k] ?? pretty(k))))
                .toList(),
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        Field('Title', hint: 'Optional — defaults to the document type', child: TextField(controller: _title)),
        Field(
          'File',
          child: FileSlot(
            category: 'student_document',
            current: _file,
            onChanged: (fileId, link) async => setState(() => _file = link),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy || _type == null || _file == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await runAction(
                    context,
                    () => documentsApi.add(widget.studentId, _type!, _title.text.trim(), _file!.id!),
                    success: 'Document uploaded',
                  );
                  if (mounted) setState(() => _busy = false);
                  if (ok && mounted) Navigator.pop(context, true);
                },
          child: const Text('Save document'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- history

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context) => AsyncView<List<Map<String, dynamic>>>(
        load: () => lifecycleApi.history(studentId),
        builder: (context, rows, reload) {
          if (rows.isEmpty) return const EmptyView('No enrolment history recorded yet');
          return SectionCard(
            title: 'Where this student studied',
            child: Column(
              children: rows
                  .map((r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['class_label']} · ${r['semester']}', style: const TextStyle(fontSize: 14)),
                        subtitle: Text('${r['academic_year']} · updated ${fmtDate(text(r['updated_at']))}',
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: StatusTag(text(r['status'])),
                      ))
                  .toList(),
            ),
          );
        },
      );
}
