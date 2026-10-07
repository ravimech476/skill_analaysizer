import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/import_upload.dart';
import '../widgets/pickers.dart';
import 'student_detail_screen.dart';

export 'student_detail_screen.dart' show StudentDetailScreen;

/// Staff see a searchable roster; a student sees their own profile and a parent
/// sees their children, which is the same list with a different shape.
class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final showImport = session.isStaff && session.can(['bulk_upload.create']);
    if (!showImport) return const _StudentsList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const TabBar(tabs: [Tab(text: 'List'), Tab(text: 'Import')]),
        body: TabBarView(
          children: [
            const _StudentsList(),
            _StudentsImport(),
          ],
        ),
      ),
    );
  }
}

class _StudentsImport extends StatefulWidget {
  @override
  State<_StudentsImport> createState() => _StudentsImportState();
}

class _StudentsImportState extends State<_StudentsImport> {
  bool _createClasses = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        ImportUpload(
          title: 'students',
          hint: 'One row per student: register number, name, department code, class and optional parent details.',
          upload: (file, {required dryRun}) =>
              bulkApi.students(file, dryRun: dryRun, createMissingClasses: _createClasses),
          extraControls: (busy) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _createClasses,
            activeThumbColor: Brand.accent,
            title: const Text('Create missing classes', style: TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() => _createClasses = v),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Import Student Skills', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        ImportUpload(
          title: 'Student Skills',
          hint: 'One row per student+skill: register_no, skill_name, proficiency (1-5).',
          upload: (file, {required dryRun}) => bulkApi.skills(file, dryRun: dryRun),
        ),
      ],
    );
  }
}

class _StudentsList extends StatefulWidget {
  const _StudentsList();

  @override
  State<_StudentsList> createState() => _StudentsListState();
}

class _StudentsListState extends State<_StudentsList> {
  String _search = '';
  int? _departmentId;
  int? _classId;
  String? _lifecycle;
  int _page = 1;

  Object get _key => '$_search|$_departmentId|$_classId|$_lifecycle|$_page';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isStaff = session.isStaff;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isStaff && session.can(['student.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () async {
                if (await showStudentForm(context)) setState(() => _page = 1);
              },
              icon: const Icon(Icons.add),
              label: const Text('Student'),
            )
          : null,
      body: _body(session, isStaff),
    );
  }

  Widget _body(Session session, bool isStaff) {
    return Column(
      children: [
        if (isStaff)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                SearchBox(
                  hint: 'Name or register number',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RefPicker(
                        hint: 'Department',
                        load: Lookups.departments,
                        value: _departmentId,
                        onChanged: (v) => setState(() {
                          _departmentId = v;
                          _page = 1;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RefPicker(
                        hint: 'Class',
                        load: Lookups.classes,
                        value: _classId,
                        onChanged: (v) => setState(() {
                          _classId = v;
                          _page = 1;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChipFilter<String?>(
                    value: _lifecycle,
                    options: const [
                      (null, 'Everyone'),
                      ('studying', 'Studying'),
                      ('passed_out', 'Alumni'),
                      ('discontinued', 'Discontinued'),
                    ],
                    onChanged: (v) => setState(() {
                      _lifecycle = v;
                      _page = 1;
                    }),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: AsyncView<Paged<Map<String, dynamic>>>(
            refreshKey: _key,
            scrollable: false,
            load: () => studentsApi.list(
              search: _search,
              departmentId: _departmentId,
              classId: _classId,
              lifecycle: _lifecycle,
              page: _page,
              pageSize: isStaff ? 25 : 50,
            ),
            builder: (context, page, reload) {
              if (page.rows.isEmpty) {
                return ListView(children: [
                  EmptyView(isStaff
                      ? 'No students matched'
                      : session.audience == Audience.parent
                          ? 'No children are linked to your account yet.'
                          : 'Your student profile has not been set up yet.')
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: page.rows.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (i == page.rows.length) {
                    return _Pager(
                      page: page,
                      onPage: (p) => setState(() => _page = p),
                      label: isStaff ? '${page.total} students' : '',
                    );
                  }
                  final s = Student(page.rows[i]);
                  return _StudentCard(
                    student: s,
                    onTap: () async {
                      await push(context, StudentDetailScreen(studentId: s.id));
                      reload();
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.student, required this.onTap});
  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Avatar(name: student.name, photo: student.photo, radius: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(student.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          ),
                          if (student.lifecycle != 'studying') StatusTag(student.lifecycle),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(student.subtitle, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                      const SizedBox(height: 7),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        Tag('CGPA ${student.cgpa.toStringAsFixed(2)}',
                            color: student.cgpa >= 7 ? Brand.success : Brand.textSoft),
                        if (student.backlogCount > 0) Tag('${student.backlogCount} BL', color: Brand.error),
                        if (!student.isActive) const Tag('Inactive', color: Brand.warning),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
              ],
            ),
          ),
        ),
      );
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.onPage, this.label = ''});
  final Paged<Map<String, dynamic>> page;
  final ValueChanged<int> onPage;
  final String label;

  @override
  Widget build(BuildContext context) {
    final lastPage = (page.total / page.pageSize).ceil().clamp(1, 9999);
    if (lastPage <= 1 && label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.isEmpty ? '' : label, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
          if (lastPage > 1)
            Row(
              children: [
                IconButton(
                  onPressed: page.page > 1 ? () => onPage(page.page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${page.page} / $lastPage', style: const TextStyle(fontSize: 13)),
                IconButton(
                  onPressed: page.page < lastPage ? () => onPage(page.page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Create or edit a student, including the parents linked to them.
Future<bool> showStudentForm(BuildContext context, {Student? student}) async {
  final saved = await showFormSheet<bool>(
    context,
    student == null ? 'New student' : 'Edit ${student.name}',
    (ctx) => _StudentForm(student: student),
  );
  return saved ?? false;
}

class _StudentForm extends StatefulWidget {
  const _StudentForm({this.student});
  final Student? student;

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  late final _name = TextEditingController(text: widget.student?.name);
  late final _registerNo = TextEditingController(text: widget.student?.registerNo);
  late final _mobile = TextEditingController(text: widget.student?.mobile);
  late final _email = TextEditingController(text: widget.student?.email);
  late final _dob = TextEditingController(text: widget.student?.dob);
  late final _batch = TextEditingController(text: widget.student?.batch);
  late final _blood = TextEditingController(text: widget.student?.bloodGroup);
  late final _address = TextEditingController(text: widget.student?.address);
  late final _password = TextEditingController();
  late final _admissionYear =
      TextEditingController(text: '${widget.student?.admissionYear ?? DateTime.now().year}');

  late int? _departmentId = widget.student?.departmentId;
  late int? _classId = widget.student?.classId;
  late String? _gender = widget.student?.gender;

  // Parents are only collected when creating; afterwards they are managed on the detail screen.
  final List<Map<String, String>> _parents = [];

  // Skills: list of {name, proficiency} maps; autocomplete options loaded on init.
  final List<Map<String, dynamic>> _skills = [];
  List<String> _allSkillNames = [];

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSkillNames();
    if (widget.student != null) _loadStudentSkills();
  }

  Future<void> _loadSkillNames() async {
    try {
      final refs = await Lookups.skills();
      if (mounted) setState(() => _allSkillNames = refs.map((r) => r.label).toList());
    } catch (_) {
      // Skill autocomplete is best-effort; the form works without it.
    }
  }

  Future<void> _loadStudentSkills() async {
    try {
      final skills = await skillsApi.of(widget.student!.id);
      if (mounted) {
        setState(() {
          _skills.addAll(skills.map((s) => <String, dynamic>{
                'name': s.name,
                'proficiency': s.proficiency,
              }));
        });
      }
    } catch (_) {
      // If the student has no skills yet, that is fine.
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _registerNo, _mobile, _email, _dob, _batch, _blood, _address, _password, _admissionYear]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _registerNo.text.trim().isEmpty || _departmentId == null) {
      toast(context, 'Name, register number and department are required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'register_no': _registerNo.text.trim(),
      'department_id': _departmentId,
      'admission_year': int.tryParse(_admissionYear.text.trim()) ?? DateTime.now().year,
      'class_id': _classId,
      'mobile': _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'gender': _gender,
      'dob': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
      'blood_group': _blood.text.trim().isEmpty ? null : _blood.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      if (_batch.text.trim().isNotEmpty) 'batch': _batch.text.trim(),
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (widget.student == null && _parents.isNotEmpty)
        'parents': _parents
            .where((p) => (p['name'] ?? '').isNotEmpty && (p['mobile'] ?? '').isNotEmpty)
            .map((p) => {'name': p['name'], 'mobile': p['mobile'], 'relation': p['relation'] ?? 'father'})
            .toList(),
      'skills': _skills
          .where((s) => (s['name']?.toString().trim() ?? '').isNotEmpty)
          .map((s) => {'name': s['name'], 'proficiency': s['proficiency'] ?? 3})
          .toList(),
    };
    try {
      if (widget.student == null) {
        await studentsApi.create(body);
      } else {
        await studentsApi.update(widget.student!.id, body);
      }
      if (mounted) {
        Navigator.pop(context, true);
        toast(context, widget.student == null ? 'Student added' : 'Student updated');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Field('Full name', child: TextField(controller: _name)),
        Field('Register number', child: TextField(controller: _registerNo, textCapitalization: TextCapitalization.characters)),
        Field(
          'Department',
          child: RefPicker(
            hint: 'Department',
            allowClear: false,
            load: Lookups.departments,
            value: _departmentId,
            onChanged: (v) => setState(() => _departmentId = v),
          ),
        ),
        Field(
          'Class',
          hint: 'Optional — a student can be admitted before a class is assigned',
          child: RefPicker(
            hint: 'Class',
            load: Lookups.classes,
            value: _classId,
            onChanged: (v) => setState(() => _classId = v),
          ),
        ),
        Row(children: [
          Expanded(
            child: Field('Admission year', child: TextField(controller: _admissionYear, keyboardType: TextInputType.number)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Field('Batch', hint: 'Defaults from the admission year', child: TextField(controller: _batch)),
          ),
        ]),
        Row(children: [
          Expanded(child: Field('Mobile', child: TextField(controller: _mobile, keyboardType: TextInputType.phone))),
          const SizedBox(width: 12),
          Expanded(
            child: Field(
              'Gender',
              child: EnumPicker(
                value: _gender,
                options: const ['male', 'female', 'other'],
                allowClear: true,
                clearLabel: 'Not set',
                onChanged: (v) => setState(() => _gender = v),
              ),
            ),
          ),
        ]),
        Field('Email', child: TextField(controller: _email, keyboardType: TextInputType.emailAddress)),
        Field('Date of birth', hint: 'YYYY-MM-DD', child: TextField(controller: _dob)),
        Row(children: [
          Expanded(child: Field('Blood group', child: TextField(controller: _blood))),
          const SizedBox(width: 12),
          Expanded(
            child: Field(
              'Password',
              hint: widget.student == null ? 'Optional' : 'Leave blank to keep',
              child: TextField(controller: _password, obscureText: true),
            ),
          ),
        ]),
        Field('Address', child: TextField(controller: _address, maxLines: 2)),
        if (widget.student == null) ...[
          const Divider(height: 28),
          Row(
            children: [
              const Expanded(
                child: Text('Parents', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _parents.add({'relation': 'father'})),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const Text(
            'A parent is matched by mobile number, so siblings share one account.',
            style: TextStyle(fontSize: 12, color: Brand.muted),
          ),
          const SizedBox(height: 10),
          ..._parents.asMap().entries.map((e) {
            final i = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Name'),
                      onChanged: (v) => _parents[i]['name'] = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: 'Mobile'),
                      onChanged: (v) => _parents[i]['mobile'] = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: EnumPicker(
                      value: _parents[i]['relation'],
                      options: const ['father', 'mother', 'guardian'],
                      onChanged: (v) => setState(() => _parents[i]['relation'] = v ?? 'father'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _parents.removeAt(i)),
                  ),
                ],
              ),
            );
          }),
        ],
        const Divider(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text('Skills', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _skills.add({'name': '', 'proficiency': 3})),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const Text(
          'Type a skill name or pick from the list. New names are created automatically.',
          style: TextStyle(fontSize: 12, color: Brand.muted),
        ),
        const SizedBox(height: 10),
        ..._skills.asMap().entries.map((entry) {
          final i = entry.key;
          final sk = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    initialValue: TextEditingValue(text: sk['name'] ?? ''),
                    optionsBuilder: (v) {
                      if (v.text.isEmpty) return _allSkillNames;
                      final lower = v.text.toLowerCase();
                      return _allSkillNames.where((s) => s.toLowerCase().contains(lower));
                    },
                    onSelected: (v) => _skills[i]['name'] = v,
                    fieldViewBuilder: (ctx, ctrl, fn, onSubmit) {
                      if (ctrl.text.isEmpty && (sk['name'] ?? '').isNotEmpty) {
                        ctrl.text = sk['name'];
                      }
                      return TextField(
                        controller: ctrl,
                        focusNode: fn,
                        decoration: const InputDecoration(hintText: 'Type or pick skill', isDense: true),
                        onChanged: (v) => _skills[i]['name'] = v,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: (sk['proficiency'] as int?) ?? 3,
                  items: List.generate(5, (j) => DropdownMenuItem(value: j + 1, child: Text('${j + 1}'))),
                  onChanged: (v) => setState(() => _skills[i]['proficiency'] = v),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _skills.removeAt(i)),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.student == null ? 'Add student' : 'Save changes'),
        ),
      ],
    );
  }
}
