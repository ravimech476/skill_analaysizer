import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Moving a class to the next semester, promoting a whole year, and the alumni list.
class YearEndScreen extends StatelessWidget {
  const YearEndScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      ('Semester', const _SemesterChange()),
      if (session.can(['promotion.create'])) ('Promotion', const _Promotion()),
      ('Alumni', const _Alumni()),
      ('Past runs', const _Runs()),
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
}

class _SemesterChange extends StatefulWidget {
  const _SemesterChange();

  @override
  State<_SemesterChange> createState() => _SemesterChangeState();
}

class _SemesterChangeState extends State<_SemesterChange> {
  final Set<int> _selected = {};
  int _reload = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final canRun = context.watch<Session>().can(['promotion.create']);
    return AsyncView<List<ClassRow>>(
      refreshKey: _reload,
      load: () => classesApi.list(),
      builder: (context, classes, reload) {
        final current = classes.where((c) => c.isCurrentYear).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NoteBanner(
              title: 'Move a class to its next semester',
              body: 'Each class carries its own current semester, which decides whose marks staff may enter.',
            ),
            const SizedBox(height: 10),
            if (current.isEmpty)
              const EmptyView('No classes in the current academic year')
            else
              ...current.map((c) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _selected.contains(c.id),
                      onChanged: canRun
                          ? (on) => setState(() => on == true ? _selected.add(c.id) : _selected.remove(c.id))
                          : null,
                      title: Text(c.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${c.currentSemesterName ?? 'No semester set'} · ${c.studentCount} students',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  )),
            if (canRun && _selected.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _change('next', reload),
                      child: Text('Move ${_selected.length} to next semester'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _change('previous', reload),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _change(String direction, Future<void> Function() reload) async {
    setState(() => _busy = true);
    await runAction(context, () async {
      final r = await lifecycleApi.semesterChange(_selected.toList(), direction);
      final changed = maps(r['changed']).length;
      final skipped = maps(r['skipped']);
      if (!mounted) return;
      if (skipped.isEmpty) {
        toast(context, '$changed class(es) moved');
      } else {
        toast(context, '$changed moved; ${skipped.length} skipped: ${skipped.first['reason']}', error: true);
      }
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _selected.clear();
        _reload++;
      });
    }
  }
}

class _Promotion extends StatefulWidget {
  const _Promotion();

  @override
  State<_Promotion> createState() => _PromotionState();
}

class _PromotionState extends State<_Promotion> {
  int? _fromYearId;
  int? _toYearId;
  Map<String, dynamic>? _preview;
  final Set<int> _detained = {};
  bool _carryIncharge = true;
  bool _setCurrent = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        const NoteBanner(
          title: 'Promote a whole academic year',
          body: 'Preview first: it shows every class, who moves up, who passes out and who you have marked detained.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Field(
                'From',
                child: RefPicker(
                  hint: 'Year',
                  allowClear: false,
                  load: Lookups.academicYears,
                  value: _fromYearId,
                  onChanged: (v) => setState(() {
                    _fromYearId = v;
                    _preview = null;
                  }),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Field(
                'To',
                child: RefPicker(
                  hint: 'Year',
                  allowClear: false,
                  load: Lookups.academicYears,
                  value: _toYearId,
                  onChanged: (v) => setState(() {
                    _toYearId = v;
                    _preview = null;
                  }),
                ),
              ),
            ),
          ],
        ),
        FilledButton(
          onPressed: _busy || _fromYearId == null || _toYearId == null
              ? null
              : () async {
                  setState(() => _busy = true);
                  await runAction(context, () async {
                    final p = await lifecycleApi.preview(_fromYearId!, _toYearId!);
                    if (mounted) setState(() => _preview = p);
                  });
                  if (mounted) setState(() => _busy = false);
                },
          child: const Text('Preview'),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 14),
          if (asBool(_preview!['already_run']))
            const NoteBanner(
              title: 'This promotion has already been run',
              body: 'Running it again would be rejected by the server.',
              color: Brand.warning,
            ),
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final totals = (_preview!['totals'] as Map).cast<String, dynamic>();
            return TileGrid(children: [
              StatTile(label: 'Classes', value: '${asInt(totals['classes'])}'),
              StatTile(label: 'To promote', value: '${asInt(totals['to_promote'])}', color: Brand.success),
              StatTile(label: 'To pass out', value: '${asInt(totals['to_pass_out'])}', color: Brand.info),
              StatTile(label: 'Detained', value: '${_detained.length}', color: Brand.warning),
            ]);
          }),
          const SizedBox(height: 12),
          ...maps(_preview!['classes']).map((c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    title: Text(text(c['label']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      text(c['action']) == 'pass_out'
                          ? 'Passes out · ${maps(c['students']).length} students'
                          : 'Moves to ${c['target_label']}${asBool(c['target_exists']) ? '' : ' (will be created)'}'
                              ' · ${maps(c['students']).length} students',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    children: maps(c['students'])
                        .map((s) => CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: _detained.contains(asInt(s['id'])),
                              title: Text(text(s['name']), style: const TextStyle(fontSize: 13.5)),
                              subtitle: Text(
                                '${s['register_no']} · CGPA ${asDouble(s['cgpa']).toStringAsFixed(2)}'
                                ' · ${asInt(s['backlog_count'])} backlog(s)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              secondary: const Text('detain', style: TextStyle(fontSize: 11, color: Brand.textSoft)),
                              onChanged: (on) => setState(() =>
                                  on == true ? _detained.add(asInt(s['id'])) : _detained.remove(asInt(s['id']))),
                            ))
                        .toList(),
                  ),
                ),
              )),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _carryIncharge,
            activeThumbColor: Brand.accent,
            title: const Text('Carry each class incharge forward', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Skipped when they are already incharge of another class',
                style: TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _carryIncharge = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _setCurrent,
            activeThumbColor: Brand.accent,
            title: const Text('Make the target year current', style: TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() => _setCurrent = v),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy || asBool(_preview!['already_run'])
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Run this promotion?',
                      body: 'Students move up a year, final-year students become alumni, and detained students stay.',
                      okLabel: 'Promote',
                    )) {
                      return;
                    }
                    setState(() => _busy = true);
                    await runAction(context, () async {
                      final r = await lifecycleApi.promote({
                        'from_year_id': _fromYearId,
                        'to_year_id': _toYearId,
                        'detained_student_ids': _detained.toList(),
                        'carry_incharge': _carryIncharge,
                        'set_current': _setCurrent,
                      });
                      Lookups.clear();
                      if (mounted) {
                        toast(context,
                            '${asInt(r['promoted'])} promoted · ${asInt(r['passed_out'])} passed out · ${asInt(r['detained'])} detained');
                        setState(() => _preview = null);
                      }
                    });
                    if (mounted) setState(() => _busy = false);
                  },
            child: const Text('Run promotion'),
          ),
        ],
      ],
    );
  }
}

class _Alumni extends StatelessWidget {
  const _Alumni();

  @override
  Widget build(BuildContext context) => AsyncView<List<Student>>(
        load: () async =>
            (await studentsApi.list(lifecycle: 'passed_out', pageSize: 100)).rows.map(Student.new).toList(),
        builder: (context, students, reload) {
          if (students.isEmpty) return const EmptyView('No alumni yet');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: students
                .map((s) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(s.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                          '${s.registerNo} · ${s.batch}'
                          '${s.passedOutYear == null ? '' : ' · passed out ${s.passedOutYear}'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        trailing: Tag('CGPA ${s.cgpa.toStringAsFixed(2)}'),
                      ),
                    ))
                .toList(),
          );
        },
      );
}

class _Runs extends StatelessWidget {
  const _Runs();

  @override
  Widget build(BuildContext context) => AsyncView<List<Map<String, dynamic>>>(
        load: lifecycleApi.runs,
        builder: (context, runs, reload) {
          if (runs.isEmpty) return const EmptyView('No promotions have been run yet');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: runs
                .map((r) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${r['from_year']} → ${r['to_year']}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${asInt(r['promoted_count'])} promoted · ${asInt(r['detained_count'])} detained · '
                          '${asInt(r['passed_out_count'])} passed out · ${asInt(r['classes_created'])} classes created\n'
                          'by ${r['created_by_name'] ?? 'unknown'} on ${fmtDate(text(r['created_at']))}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        isThreeLine: true,
                      ),
                    ))
                .toList(),
          );
        },
      );
}
