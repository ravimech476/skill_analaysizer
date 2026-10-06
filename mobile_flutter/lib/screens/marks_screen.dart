import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Staff enter and review marks; students and parents read the history.
class MarksScreen extends StatelessWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isStaff) return const _MyMarks();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const TabBar(tabs: [Tab(text: 'Enter marks'), Tab(text: 'Class results')]),
        body: const TabBarView(children: [_EntryTargets(), _ResultSheetTab()]),
      ),
    );
  }
}

// ---------------------------------------------------------------- staff: entry

class _EntryTargets extends StatelessWidget {
  const _EntryTargets();

  @override
  Widget build(BuildContext context) => AsyncView<List<MarkTarget>>(
        load: marksApi.mySubjects,
        builder: (context, targets, reload) {
          if (targets.isEmpty) {
            return const EmptyView(
              'Nothing allocated to you this semester.\nAn admin or HOD assigns subjects under Academic Setup.',
              icon: Icons.menu_book_outlined,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Subjects you may enter marks for, in the current academic year.',
                style: TextStyle(fontSize: 12.5, color: Brand.textSoft),
              ),
              const SizedBox(height: 10),
              ...targets.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        title: Text('${t.subjectCode} · ${t.subjectName}',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        subtitle: Text('${t.classLabel} · Semester ${t.semNo} · as ${pretty(t.reason)}',
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
                        onTap: () => push(context, MarkEntryScreen(target: t)),
                      ),
                    ),
                  )),
            ],
          );
        },
      );
}

/// The mark entry grid for one class × subject × exam × attempt.
class MarkEntryScreen extends StatefulWidget {
  const MarkEntryScreen({super.key, required this.target});
  final MarkTarget target;

  @override
  State<MarkEntryScreen> createState() => _MarkEntryScreenState();
}

class _MarkEntryScreenState extends State<MarkEntryScreen> {
  int? _examTypeId;
  int _attempt = 1;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _absent = {};
  bool _saving = false;
  final _viewKey = GlobalKey<AsyncViewState<EntrySheet>>();

  Map<String, dynamic> get _key => {
        'class_id': widget.target.classId,
        'semester_id': widget.target.semesterId,
        'subject_id': widget.target.subjectId,
        'exam_type_id': _examTypeId,
        'attempt_no': _attempt,
      };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(EntrySheet sheet) {
    for (final r in sheet.rows) {
      final value = r.marks == null ? '' : (r.marks! % 1 == 0 ? r.marks!.toInt().toString() : r.marks.toString());
      final existing = _controllers[r.studentId];
      if (existing == null) {
        _controllers[r.studentId] = TextEditingController(text: value);
      } else if (existing.text != value && !existing.selection.isValid) {
        existing.text = value;
      }
      _absent.putIfAbsent(r.studentId, () => r.isAbsent);
    }
  }

  Future<void> _save(EntrySheet sheet) async {
    final entries = sheet.rows.map((r) {
      final absent = _absent[r.studentId] ?? false;
      final raw = _controllers[r.studentId]?.text.trim() ?? '';
      return {
        'student_id': r.studentId,
        'is_absent': absent,
        'marks_obtained': absent || raw.isEmpty ? null : double.tryParse(raw),
      };
    }).toList();

    final bad = entries.where((e) =>
        e['is_absent'] == false &&
        (_controllers[e['student_id']]?.text.trim().isNotEmpty ?? false) &&
        e['marks_obtained'] == null);
    if (bad.isNotEmpty) {
      toast(context, 'Some marks are not numbers', error: true);
      return;
    }

    setState(() => _saving = true);
    final ok = await runAction(context, () => marksApi.save(_key, entries), success: 'Marks saved');
    if (mounted) setState(() => _saving = false);
    if (ok) _viewKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    return SubPage(
      title: '${t.subjectCode} · ${t.classLabel}',
      subtitle: t.subjectName,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: RefPicker(
                    hint: 'Exam',
                    allowClear: false,
                    load: Lookups.examTypes,
                    value: _examTypeId,
                    onChanged: (v) => setState(() {
                      _examTypeId = v;
                      _controllers.clear();
                      _absent.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    initialValue: _attempt,
                    items: [1, 2, 3]
                        .map((a) => DropdownMenuItem(value: a, child: Text(a == 1 ? 'Attempt 1' : 'Arrear $a')))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _attempt = v ?? 1;
                      _controllers.clear();
                      _absent.clear();
                    }),
                  ),
                ),
              ],
            ),
          ),
          if (_examTypeId == null)
            const Expanded(child: EmptyView('Pick an exam to enter or review marks'))
          else
            Expanded(
              child: AsyncView<EntrySheet>(
                key: _viewKey,
                refreshKey: '$_examTypeId|$_attempt',
                scrollable: false,
                load: () => marksApi.entry(_key),
                builder: (context, sheet, reload) {
                  _seed(sheet);
                  final stats = sheet.stats;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${sheet.examName} · out of ${sheet.maxMarks.toInt()}'
                                '${sheet.isFinal ? ' · graded' : ''}',
                                style: const TextStyle(fontSize: 12.5, color: Brand.textSoft),
                              ),
                            ),
                            if (stats.isNotEmpty)
                              Text(
                                '${asInt(stats['entered'])} entered · ${asDouble(stats['pass_percent']).toStringAsFixed(0)}% pass',
                                style: const TextStyle(fontSize: 12.5, color: Brand.textSoft),
                              ),
                          ],
                        ),
                      ),
                      if (!sheet.canEdit)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: NoteBanner(
                            title: 'Read only',
                            body: 'Only the subject staff, the class incharge, the HOD or an admin may enter these marks.',
                            color: Brand.warning,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: sheet.rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 14),
                          itemBuilder: (context, i) {
                            final r = sheet.rows[i];
                            final absent = _absent[r.studentId] ?? false;
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(r.name, style: const TextStyle(fontSize: 14)),
                                      Text(
                                        '${r.registerNo}${r.inClass ? '' : ' · arrear'}',
                                        style: const TextStyle(fontSize: 11.5, color: Brand.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (r.grade != null) ...[Tag(r.grade!, color: statusColor(r.result)), const SizedBox(width: 8)],
                                SizedBox(
                                  width: 74,
                                  child: TextField(
                                    controller: _controllers[r.studentId],
                                    enabled: sheet.canEdit && !absent,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      hintText: absent ? 'AB' : '—',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Absent',
                                  child: Checkbox(
                                    value: absent,
                                    onChanged: sheet.canEdit
                                        ? (v) => setState(() {
                                              _absent[r.studentId] = v ?? false;
                                              if (v == true) _controllers[r.studentId]?.clear();
                                            })
                                        : null,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (sheet.canEdit)
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: FilledButton(
                              onPressed: _saving ? null : () => _save(sheet),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Save marks'),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- staff: result sheet

class _ResultSheetTab extends StatefulWidget {
  const _ResultSheetTab();

  @override
  State<_ResultSheetTab> createState() => _ResultSheetTabState();
}

class _ResultSheetTabState extends State<_ResultSheetTab> {
  int? _classId;
  int? _semesterId;
  int? _examTypeId;

  @override
  Widget build(BuildContext context) {
    final ready = _classId != null && _semesterId != null && _examTypeId != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              RefPicker(
                hint: 'Class',
                allowClear: false,
                load: Lookups.classes,
                value: _classId,
                onChanged: (v) => setState(() => _classId = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RefPicker(
                      hint: 'Semester',
                      allowClear: false,
                      load: Lookups.semesters,
                      value: _semesterId,
                      onChanged: (v) => setState(() => _semesterId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RefPicker(
                      hint: 'Exam',
                      allowClear: false,
                      load: Lookups.examTypes,
                      value: _examTypeId,
                      onChanged: (v) => setState(() => _examTypeId = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!ready)
          const Expanded(child: EmptyView('Pick a class, semester and exam to see the result sheet'))
        else
          Expanded(
            child: AsyncView<Map<String, dynamic>>(
              refreshKey: '$_classId|$_semesterId|$_examTypeId',
              load: () => marksApi.sheet({
                'class_id': _classId,
                'semester_id': _semesterId,
                'exam_type_id': _examTypeId,
                'attempt_no': 1,
              }),
              builder: (context, sheet, reload) {
                final subjects = maps(sheet['subjects']);
                final rows = maps(sheet['rows']);
                if (rows.isEmpty) return const EmptyView('No marks entered for this exam yet');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionCard(
                      title: '${sheet['class_label']} · ${sheet['exam_name']}',
                      subtitle: '${rows.length} students · ${subjects.length} subjects',
                      child: Column(
                        children: subjects.map((s) {
                          final stats = (s['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('${s['code']} · ${s['name']}', style: const TextStyle(fontSize: 13.5)),
                            subtitle: Text(
                              'avg ${asDouble(stats['average']).toStringAsFixed(1)} · '
                              'highest ${asDouble(stats['highest']).toStringAsFixed(0)} · '
                              '${asInt(stats['failed'])} failed',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Tag('${asDouble(stats['pass_percent']).toStringAsFixed(0)}%',
                                color: asDouble(stats['pass_percent']) >= 60 ? Brand.success : Brand.warning),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SectionCard(
                      title: 'Students',
                      child: Column(
                        children: rows.map((r) {
                          final failed = asInt(r['failed']);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(text(r['name']), style: const TextStyle(fontSize: 13.5)),
                            subtitle: Text(text(r['register_no']), style: const TextStyle(fontSize: 12)),
                            trailing: failed == 0
                                ? const Tag('All clear', color: Brand.success)
                                : Tag('$failed failed', color: Brand.error),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- student / parent

class _MyMarks extends StatefulWidget {
  const _MyMarks();

  @override
  State<_MyMarks> createState() => _MyMarksState();
}

class _MyMarksState extends State<_MyMarks> {
  int? _studentId;

  @override
  Widget build(BuildContext context) {
    final isParent = !context.watch<Session>().isStaff && context.read<Session>().audience.name == 'parent';
    return AsyncView<List<Student>>(
      scrollable: false,
      load: () async =>
          (await studentsApi.list(pageSize: isParent ? 50 : 1)).rows.map(Student.new).toList(),
      builder: (context, children, reload) {
        if (children.isEmpty) return const EmptyView('No student profile is linked to your account yet.');
        final chosen = children.firstWhere((c) => c.id == _studentId, orElse: () => children.first);
        return Column(
          children: [
            if (children.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<int>(
                  initialValue: chosen.id,
                  isExpanded: true,
                  items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => _studentId = v),
                ),
              ),
            Expanded(child: MarkHistoryView(studentId: chosen.id)),
          ],
        );
      },
    );
  }
}

/// Semester-by-semester marks, used both in the Marks screen and the student detail tabs.
class MarkHistoryView extends StatelessWidget {
  const MarkHistoryView({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context) => AsyncView<MarkHistory>(
        load: () => marksApi.history(studentId),
        builder: (context, history, reload) {
          if (history.semesters.isEmpty) return const EmptyView('No marks recorded yet');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileGrid(children: [
                StatTile(label: 'CGPA', value: history.cgpa.toStringAsFixed(2), color: Brand.accent),
                StatTile(
                  label: 'Backlogs',
                  value: '${history.backlogCount}',
                  color: history.backlogCount > 0 ? Brand.error : Brand.success,
                ),
                StatTile(label: 'Semesters', value: '${history.semesters.length}'),
              ]),
              const SizedBox(height: 12),
              ...history.semesters.map((sem) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SemesterCard(sem: sem),
                  )),
            ],
          );
        },
      );
}

class _SemesterCard extends StatelessWidget {
  const _SemesterCard({required this.sem});
  final Map<String, dynamic> sem;

  @override
  Widget build(BuildContext context) {
    final subjects = maps(sem['subjects']);
    final sgpa = asDoubleOrNull(sem['sgpa']);
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: Text('Semester ${asInt(sem['sem_no'])} · ${text(sem['name'])}',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${text(sem['academic_year'])}${sem['class_label'] == null ? '' : ' · ${sem['class_label']}'}',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(sgpa == null ? '—' : 'SGPA ${sgpa.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.accent)),
              if (asInt(sem['backlogs']) > 0)
                Text('${asInt(sem['backlogs'])} backlog(s)',
                    style: const TextStyle(fontSize: 11, color: Brand.error)),
            ],
          ),
          children: subjects.map((s) {
            final exams = maps(s['exams']);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${s['code']} · ${s['name']}',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      if (s['final_grade'] != null)
                        Tag(text(s['final_grade']), color: statusColor(text(s['final_result']))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: exams.map((e) {
                      final marks = asDoubleOrNull(e['marks']);
                      return Tag(
                        '${e['exam_code']}: ${marks == null ? 'AB' : marks.toStringAsFixed(marks % 1 == 0 ? 0 : 1)}'
                        '/${asDouble(e['max_marks']).toStringAsFixed(0)}',
                        color: statusColor(text(e['result'])),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
