import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';
import 'student_detail_screen.dart';

/// Classes, their incharges and the semester each is currently in.
class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String _search = '';
  int? _departmentId;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: session.can(['class.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Class'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(flex: 3, child: SearchBox(hint: 'Search classes', onChanged: (v) => setState(() => _search = v))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: RefPicker(
                    hint: 'Department',
                    load: Lookups.departments,
                    value: _departmentId,
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<ClassRow>>(
              refreshKey: '$_search|$_departmentId|$_reload',
              load: () => classesApi.list(search: _search, departmentId: _departmentId),
              builder: (context, classes, reload) {
                if (classes.isEmpty) return const EmptyView('No classes yet');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: classes
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(c.label,
                                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                    ),
                                    if (c.isCurrentYear) const Tag('Current year', color: Brand.accent),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${c.academicYearName} · ${c.currentSemesterName ?? 'no semester set'} · '
                                    '${c.studentCount} students\nIncharge: ${c.inchargeName ?? 'not assigned'}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: session.can(['class.update'])
                                    ? PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, size: 20),
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(value: 'students', child: Text('Students')),
                                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                          if (session.can(['class.delete']))
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete', style: TextStyle(color: Brand.error))),
                                        ],
                                        onSelected: (v) async {
                                          if (v == 'students') {
                                            push(context, _ClassStudents(klass: c));
                                          } else if (v == 'edit') {
                                            _edit(c);
                                          } else if (await confirm(context, 'Delete ${c.label}?',
                                              danger: true, okLabel: 'Delete')) {
                                            final ok = await runAction(context, () => classesApi.remove(c.id),
                                                success: 'Class deleted');
                                            if (ok) {
                                              Lookups.clear('classes');
                                              setState(() => _reload++);
                                            }
                                          }
                                        },
                                      )
                                    : const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
                                onTap: () => push(context, _ClassStudents(klass: c)),
                              ),
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

  Future<void> _edit(ClassRow? klass) async {
    final saved = await showFormSheet<bool>(
      context,
      klass == null ? 'New class' : 'Edit ${klass.label}',
      (ctx) => _ClassForm(klass: klass),
    );
    if (saved == true) {
      Lookups.clear('classes');
      setState(() => _reload++);
    }
  }
}

class _ClassForm extends StatefulWidget {
  const _ClassForm({this.klass});
  final ClassRow? klass;

  @override
  State<_ClassForm> createState() => _ClassFormState();
}

class _ClassFormState extends State<_ClassForm> {
  late int? _departmentId = widget.klass?.departmentId;
  late int? _academicYearId = widget.klass?.academicYearId;
  late int? _yearLevelId = widget.klass?.yearLevelId;
  late int? _semesterId = widget.klass?.currentSemesterId;
  late int? _inchargeId = widget.klass?.inchargeId;
  late final _section = TextEditingController(text: widget.klass?.section);
  bool _busy = false;

  @override
  void dispose() {
    _section.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            'Academic year',
            child: RefPicker(
              hint: 'Academic year',
              allowClear: false,
              load: Lookups.academicYears,
              value: _academicYearId,
              onChanged: (v) => setState(() => _academicYearId = v),
            ),
          ),
          Row(children: [
            Expanded(
              child: Field(
                'Year',
                child: RefPicker(
                  hint: 'Year',
                  allowClear: false,
                  load: Lookups.yearLevels,
                  value: _yearLevelId,
                  onChanged: (v) => setState(() => _yearLevelId = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Field('Section', child: TextField(controller: _section, textCapitalization: TextCapitalization.characters))),
          ]),
          Field(
            'Current semester',
            hint: 'Which semester this class is in right now',
            child: RefPicker(
              hint: 'Semester',
              load: Lookups.semesters,
              value: _semesterId,
              onChanged: (v) => setState(() => _semesterId = v),
            ),
          ),
          Field(
            'Class incharge',
            hint: 'One staff member can be incharge of one class per academic year',
            child: RefPicker(
              hint: 'Staff',
              load: Lookups.staff,
              value: _inchargeId,
              onChanged: (v) => setState(() => _inchargeId = v),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_departmentId == null || _academicYearId == null || _yearLevelId == null) {
                      toast(context, 'Department, academic year and year are required', error: true);
                      return;
                    }
                    setState(() => _busy = true);
                    final body = {
                      'department_id': _departmentId,
                      'academic_year_id': _academicYearId,
                      'year_level_id': _yearLevelId,
                      'section': _section.text.trim().toUpperCase(),
                      'class_incharge_id': _inchargeId,
                      'current_semester_id': _semesterId,
                    };
                    final ok = await runAction(
                      context,
                      () => widget.klass == null
                          ? classesApi.create(body)
                          : classesApi.update(widget.klass!.id, body),
                      success: widget.klass == null ? 'Class added' : 'Class updated',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: Text(widget.klass == null ? 'Add class' : 'Save changes'),
          ),
        ],
      );
}

class _ClassStudents extends StatelessWidget {
  const _ClassStudents({required this.klass});
  final ClassRow klass;

  @override
  Widget build(BuildContext context) => SubPage(
        title: klass.label,
        subtitle: '${klass.academicYearName} · ${klass.currentSemesterName ?? 'no semester set'}',
        child: AsyncView<List<Student>>(
          load: () async =>
              (await studentsApi.list(classId: klass.id, pageSize: 200)).rows.map(Student.new).toList(),
          builder: (context, students, reload) {
            if (students.isEmpty) return const EmptyView('No students in this class yet');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: students
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(s.name, style: const TextStyle(fontSize: 14)),
                            subtitle: Text('${s.registerNo} · CGPA ${s.cgpa.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12.5)),
                            trailing: s.backlogCount > 0
                                ? Tag('${s.backlogCount} BL', color: Brand.error)
                                : const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
                            onTap: () => push(context, StudentDetailScreen(studentId: s.id)),
                          ),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      );
}
