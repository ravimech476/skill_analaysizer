import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'placement_screen.dart';

/// Staff rank students against a drive and shortlist from the result; students and
/// parents see the same comparison from their own side.
class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key, this.roleId});

  /// Opened from a drive, the role is already chosen.
  final int? roleId;

  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  int? _roleId;
  bool _eligibleOnly = false;
  bool _running = false;
  final Set<int> _selected = {};
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    _roleId = widget.roleId;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isStaff) return const _MyGap();

    return Column(
      children: [
        if (widget.roleId == null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<List<JobRole>>(
              future: placementApi.roles(),
              builder: (context, snap) => DropdownButtonFormField<int>(
                initialValue: _roleId,
                isExpanded: true,
                hint: const Text('Pick a drive to rank students against'),
                items: (snap.data ?? [])
                    .map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.companyName} · ${r.title} · ${lpa(r.packageLpa)}',
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _roleId = v;
                  _selected.clear();
                }),
              ),
            ),
          ),
        if (_roleId == null)
          const Expanded(
            child: EmptyView(
              'Pick a drive to rank students against its required skills and eligibility',
              icon: Icons.insights_outlined,
            ),
          )
        else
          Expanded(
            child: AsyncView<Ranking>(
              refreshKey: '$_roleId|$_reload',
              scrollable: false,
              load: () => placementApi.matches(_roleId!),
              builder: (context, ranking, reload) {
                final rows = ranking.matches.where((m) => !_eligibleOnly || m.isEligible).toList();
                final canShortlist = session.can(['placement.create']);
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        children: [
                          NoteBanner(
                            title: 'How the score works',
                            body: 'Skill match is the weighted share of each required skill the student has, measured '
                                'on their blended skill score. Academic is CGPA × 10. The split between the two is set '
                                'under Student Skills → Scoring.',
                          ),
                          const SizedBox(height: 10),
                          if (ranking.stale > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: NoteBanner(
                                title: '${ranking.stale} student${ranking.stale == 1 ? "'s" : "s'"} skills have changed',
                                body: 'Re-run the analyzer so the shortlist reflects the latest skills and marks.',
                                color: Brand.warning,
                                icon: Icons.history,
                              ),
                            ),
                          if (ranking.analyzedAt == null)
                            const EmptyView('Not analysed yet. Run the analyzer to rank students.')
                          else ...[
                            TileGrid(children: [
                              StatTile(label: 'Ranked', value: '${ranking.total}'),
                              StatTile(label: 'Eligible', value: '${ranking.eligible}', color: Brand.success),
                              StatTile(label: 'Selected', value: '${_selected.length}', color: Brand.accent),
                            ]),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Switch(
                                  value: _eligibleOnly,
                                  activeThumbColor: Brand.accent,
                                  onChanged: (v) => setState(() => _eligibleOnly = v),
                                ),
                                const Text('Eligible only', style: TextStyle(fontSize: 13)),
                                const Spacer(),
                                Text('Last run ${fmtDateTime(ranking.analyzedAt)}',
                                    style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...rows.asMap().entries.map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _MatchRow(
                                    position: e.key + 1,
                                    match: e.value,
                                    selectable: canShortlist && e.value.isEligible && e.value.applicationStatus == null,
                                    selected: _selected.contains(e.value.studentId),
                                    onToggle: (on) => setState(() =>
                                        on ? _selected.add(e.value.studentId) : _selected.remove(e.value.studentId)),
                                  ),
                                )),
                          ],
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          children: [
                            if (session.can(['skill_analyzer.create']))
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _running ? null : () => _run(reload),
                                  icon: _running
                                      ? const SizedBox(
                                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.bolt_outlined, size: 18),
                                  label: Text(ranking.analyzedAt == null ? 'Run analyzer' : 'Re-run'),
                                ),
                              ),
                            if (canShortlist && _selected.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _shortlist(reload),
                                  icon: const Icon(Icons.group_add_outlined, size: 18),
                                  label: Text('Shortlist ${_selected.length}'),
                                ),
                              ),
                            ],
                          ],
                        ),
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

  Future<void> _run(Future<void> Function() reload) async {
    setState(() => _running = true);
    final ok = await runAction(
      context,
      () async {
        final r = await placementApi.analyze(_roleId!);
        if (mounted) toast(context, 'Ranked ${r.total} students · ${r.eligible} eligible');
      },
    );
    if (mounted) {
      setState(() {
        _running = false;
        _selected.clear();
        if (ok) _reload++;
      });
    }
  }

  Future<void> _shortlist(Future<void> Function() reload) async {
    final ok = await runAction(
      context,
      () async {
        final r = await placementApi.shortlist(_roleId!, _selected.toList());
        final skipped = maps(r['skipped']);
        if (!mounted) return;
        if (skipped.isEmpty) {
          toast(context, 'Shortlisted ${asInt(r['added'])} student(s)');
        } else {
          toast(context, 'Shortlisted ${asInt(r['added'])}; skipped ${skipped.length}', error: true);
        }
      },
    );
    if (ok && mounted) {
      setState(() {
        _selected.clear();
        _reload++;
      });
    }
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.position,
    required this.match,
    required this.selectable,
    required this.selected,
    required this.onToggle,
  });

  final int position;
  final Match match;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) => Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.only(left: 6, right: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: selectable
                ? Checkbox(value: selected, onChanged: (v) => onToggle(v ?? false))
                : SizedBox(
                    width: 40,
                    child: Center(
                      child: Text('$position', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
                    ),
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(match.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                if (match.isStale)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Tag('stale', color: Brand.warning),
                  ),
                Text(match.finalScore.toStringAsFixed(match.finalScore % 1 == 0 ? 0 : 1),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                Text('${match.registerNo} · ${match.classLabel ?? match.departmentCode ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                Tag('CGPA ${match.cgpa.toStringAsFixed(2)}'),
                if (match.backlogCount > 0) Tag('${match.backlogCount} BL', color: Brand.error),
                Tag(match.isEligible ? 'Eligible' : 'Not eligible',
                    color: match.isEligible ? Brand.success : Brand.error),
                if (match.applicationStatus != null) StatusTag(match.applicationStatus),
              ]),
            ),
            children: [
              if (match.reasons.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: match.reasons
                        .map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.close, size: 13, color: Brand.error),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(r, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft))),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const Divider(height: 20),
              ],
              ...[...match.missing, ...match.matched].map((g) => MeterBar(
                    label: g.name,
                    progress: g.progress,
                    trailing: '${g.studentLevel}/${g.requiredLevel}',
                    emphasise: g.isMandatory,
                    met: g.met,
                    tooltip: 'Blended score ${g.studentScore} of the ${g.requiredScore} needed',
                  )),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Skill match ${match.skillScore.toStringAsFixed(0)}% · '
                    'academics ${match.academicScore.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
              ),
            ],
          ),
        ),
      );
}

/// A student's own reading of the analyzer: what each company needs and where they stand.
class _MyGap extends StatefulWidget {
  const _MyGap();

  @override
  State<_MyGap> createState() => _MyGapState();
}

class _MyGapState extends State<_MyGap> {
  int? _studentId;

  @override
  Widget build(BuildContext context) {
    final isParent = context.watch<Session>().audience.name == 'parent';
    return AsyncView<List<Student>>(
      scrollable: false,
      load: () async => (await studentsApi.list(pageSize: isParent ? 50 : 1)).rows.map(Student.new).toList(),
      builder: (context, children, reload) {
        if (children.isEmpty) return const EmptyView('No student profile is linked to your account yet.');
        final chosen = children.firstWhere((c) => c.id == _studentId, orElse: () => children.first);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'How your skills compare with what each company needs. Close the red ones to become eligible.',
                      style: TextStyle(fontSize: 12.5, color: Brand.textSoft),
                    ),
                  ),
                  if (children.length > 1) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: chosen.id,
                      isExpanded: true,
                      items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      onChanged: (v) => setState(() => _studentId = v),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: StudentOpportunitiesView(studentId: chosen.id, mode: 'gap')),
          ],
        );
      },
    );
  }
}
