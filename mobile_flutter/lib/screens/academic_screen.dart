import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// The academic setup: departments, academic years, subjects, exam types, grades,
/// the curriculum and who teaches what.
class AcademicScreen extends StatelessWidget {
  const AcademicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Departments', _departments()),
      ('Years', _years()),
      ('Subjects', _subjects()),
      ('Exams', _exams()),
      ('Grades', _grades()),
      ('Curriculum', const _Curriculum()),
      if (session.can(['subject_allocation.view'])) ('Who teaches', const _Allocations()),
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

  static Widget _exams() => MasterCrud(
        path: 'exam-types',
        permission: 'exam_type',
        noun: 'exam type',
        searchable: false,
        fields: const [
          MasterField('name', 'Name', required: true),
          MasterField('code', 'Code', type: MasterFieldType.upper, required: true),
          MasterField('max_marks', 'Maximum marks', type: MasterFieldType.number, required: true),
          MasterField('pass_percent', 'Pass percentage', type: MasterFieldType.number),
          MasterField('sort_order', 'Order', type: MasterFieldType.integer),
          MasterField('is_final', 'Final exam (graded, counts towards CGPA)', type: MasterFieldType.boolean),
        ],
        title: _examTitle,
        badges: _examBadges,
      );

  static (String, String?) _examTitle(MasterRow r) =>
      ('${r['code']} · ${r['name']}', 'out of ${r['max_marks']} · pass at ${r['pass_percent']}%');

  static List<Widget> _examBadges(MasterRow r) => [
        if (asBool(r['is_final'])) const Tag('Final', color: Brand.accent),
      ];

  static Widget _grades() => MasterCrud(
        path: 'grade-scales',
        permission: 'exam_type',
        noun: 'grade',
        searchable: false,
        subtitle: 'How a percentage becomes a grade and a grade point on final exams.',
        fields: const [
          MasterField('grade', 'Grade', type: MasterFieldType.upper, required: true),
          MasterField('min_percent', 'From percentage', type: MasterFieldType.number, required: true),
          MasterField('grade_point', 'Grade point', type: MasterFieldType.number, required: true),
          MasterField('is_pass', 'Counts as a pass', type: MasterFieldType.boolean),
        ],
        title: _gradeTitle,
      );

  static (String, String?) _gradeTitle(MasterRow r) =>
      (text(r['grade']), 'from ${r['min_percent']}% · ${r['grade_point']} points${asBool(r['is_pass']) ? '' : ' · fail'}');
}

// ---------------------------------------------------------------- curriculum

class _Curriculum extends StatefulWidget {
  const _Curriculum();

  @override
  State<_Curriculum> createState() => _CurriculumState();
}

class _CurriculumState extends State<_Curriculum> {
  int? _departmentId;
  int? _semesterId;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['subject.create']);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: RefPicker(
                  hint: 'Department',
                  allowClear: false,
                  load: Lookups.departments,
                  value: _departmentId,
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RefPicker(
                  hint: 'Semester',
                  load: Lookups.semesters,
                  value: _semesterId,
                  onChanged: (v) => setState(() => _semesterId = v),
                ),
              ),
            ],
          ),
        ),
        if (_departmentId == null)
          const Expanded(child: EmptyView('Pick a department to see the subjects it teaches'))
        else
          Expanded(
            child: AsyncView<List<Map<String, dynamic>>>(
              refreshKey: '$_departmentId|$_semesterId|$_reload',
              load: () => curriculumApi.list(_departmentId!, _semesterId),
              builder: (context, rows, reload) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final added = await showFormSheet<bool>(
                            context,
                            'Add subjects to the curriculum',
                            (ctx) => _CurriculumForm(departmentId: _departmentId!, semesterId: _semesterId),
                          );
                          if (added == true) setState(() => _reload++);
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add subjects'),
                      ),
                    ),
                  if (rows.isEmpty)
                    const EmptyView('Nothing in this curriculum yet')
                  else
                    ...rows.map((r) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text('${r['subject_code']} · ${r['subject_name']}',
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              'Semester ${asInt(r['sem_no'])} · ${r['credits']} credits · ${pretty(text(r['subject_type']))}'
                              '${text(r['regulation']).isEmpty ? '' : ' · ${r['regulation']}'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            trailing: canEdit
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18, color: Brand.error),
                                    onPressed: () async {
                                      final ok = await runAction(
                                        context,
                                        () => curriculumApi.remove(asInt(r['id'])),
                                        success: 'Removed from the curriculum',
                                      );
                                      if (ok) setState(() => _reload++);
                                    },
                                  )
                                : null,
                          ),
                        )),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CurriculumForm extends StatefulWidget {
  const _CurriculumForm({required this.departmentId, this.semesterId});
  final int departmentId;
  final int? semesterId;

  @override
  State<_CurriculumForm> createState() => _CurriculumFormState();
}

class _CurriculumFormState extends State<_CurriculumForm> {
  late int? _semesterId = widget.semesterId;
  final Set<int> _subjectIds = {};
  final _regulation = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _regulation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            'Semester',
            child: RefPicker(
              hint: 'Semester',
              allowClear: false,
              load: Lookups.semesters,
              value: _semesterId,
              onChanged: (v) => setState(() => _semesterId = v),
            ),
          ),
          Field('Regulation', hint: 'Optional', child: TextField(controller: _regulation)),
          Field(
            'Subjects',
            child: FutureBuilder<List<Ref>>(
              future: Lookups.subjects(),
              builder: (context, snap) {
                if (!snap.hasData) return const Loader(padding: 16);
                return Column(
                  children: snap.data!
                      .map((s) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _subjectIds.contains(s.id),
                            title: Text(s.label, style: const TextStyle(fontSize: 13.5)),
                            onChanged: (on) => setState(
                                () => on == true ? _subjectIds.add(s.id) : _subjectIds.remove(s.id)),
                          ))
                      .toList(),
                );
              },
            ),
          ),
          FilledButton(
            onPressed: _busy || _semesterId == null || _subjectIds.isEmpty
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runAction(
                      context,
                      () => curriculumApi.add(widget.departmentId, _semesterId!, _subjectIds.toList(),
                          regulation: _regulation.text.trim()),
                      success: 'Subjects added',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: Text('Add ${_subjectIds.length} subject(s)'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- allocations

class _Allocations extends StatefulWidget {
  const _Allocations();

  @override
  State<_Allocations> createState() => _AllocationsState();
}

class _AllocationsState extends State<_Allocations> {
  int? _classId;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['subject_allocation.create']);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () async {
                final saved = await showFormSheet<bool>(
                    context, 'Allocate a subject', (ctx) => _AllocationForm(classId: _classId));
                if (saved == true) setState(() => _reload++);
              },
              icon: const Icon(Icons.add),
              label: const Text('Allocate'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: RefPicker(
              hint: 'Filter by class',
              load: Lookups.classes,
              value: _classId,
              onChanged: (v) => setState(() => _classId = v),
            ),
          ),
          Expanded(
            child: AsyncView<List<Map<String, dynamic>>>(
              refreshKey: '$_classId|$_reload',
              load: () => allocationsApi.list(classId: _classId),
              builder: (context, rows, reload) {
                if (rows.isEmpty) {
                  return ListView(children: const [
                    EmptyView('No subject allocations yet.\nAllocating a subject lets that staff member enter its marks.')
                  ]);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows
                      .map((r) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text('${r['subject_code']} · ${r['subject_name']}',
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(
                                '${r['staff_name']} · ${r['class_label']} · Semester ${asInt(r['sem_no'])}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              trailing: canEdit
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 18, color: Brand.error),
                                      onPressed: () async {
                                        final ok = await runAction(
                                          context,
                                          () => allocationsApi.remove(asInt(r['id'])),
                                          success: 'Allocation removed',
                                        );
                                        if (ok) setState(() => _reload++);
                                      },
                                    )
                                  : null,
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationForm extends StatefulWidget {
  const _AllocationForm({this.classId});
  final int? classId;

  @override
  State<_AllocationForm> createState() => _AllocationFormState();
}

class _AllocationFormState extends State<_AllocationForm> {
  late int? _classId = widget.classId;
  int? _staffId;
  int? _subjectId;
  int? _semesterId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The allocated staff member, the class incharge, the HOD and admins may enter marks for this subject.',
            style: TextStyle(fontSize: 12.5, color: Brand.textSoft),
          ),
          const SizedBox(height: 14),
          Field(
            'Staff',
            child: RefPicker(
                hint: 'Staff', allowClear: false, load: Lookups.staff, value: _staffId, onChanged: (v) => setState(() => _staffId = v)),
          ),
          Field(
            'Class',
            child: RefPicker(
                hint: 'Class', allowClear: false, load: Lookups.classes, value: _classId, onChanged: (v) => setState(() => _classId = v)),
          ),
          Field(
            'Subject',
            child: RefPicker(
                hint: 'Subject', allowClear: false, load: Lookups.subjects, value: _subjectId, onChanged: (v) => setState(() => _subjectId = v)),
          ),
          Field(
            'Semester',
            hint: "Defaults to the class's current semester",
            child: RefPicker(
                hint: 'Semester', load: Lookups.semesters, value: _semesterId, onChanged: (v) => setState(() => _semesterId = v)),
          ),
          FilledButton(
            onPressed: _busy || _staffId == null || _classId == null || _subjectId == null
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runAction(
                      context,
                      () => allocationsApi.create({
                        'staff_id': _staffId,
                        'class_id': _classId,
                        'subject_id': _subjectId,
                        if (_semesterId != null) 'semester_id': _semesterId,
                      }),
                      success: 'Subject allocated',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: const Text('Allocate'),
          ),
        ],
      );
}
