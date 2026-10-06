import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';

/// Readiness buckets, worded as the server computes them.
const _readiness = {
  'ready': ('Ready', Brand.success, 'Every core skill is met and the CGPA is in range'),
  'close': ('Close', Brand.warning, 'More than half of what is needed is in place'),
  'explore': ('Explore', Brand.textSoft, 'A longer way off — worth exploring'),
};

class CareersScreen extends StatelessWidget {
  const CareersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();

    if (!session.isStaff) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: TabBar(
            tabs: [
              Tab(text: session.audience.name == 'parent' ? 'Matched to them' : 'Matched to me'),
              const Tab(text: 'All careers'),
            ],
          ),
          body: const TabBarView(children: [_MyCareers(), _CareerCatalogue(readOnly: true)]),
        ),
      );
    }

    final tabs = <(String, Widget)>[
      ('Student matches', const _StaffMatches()),
      ('Catalogue', const _CareerCatalogue()),
      if (session.can(['career.create', 'career.update'])) ('Courses', const _CoursesMaster()),
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

// ---------------------------------------------------------------- matches

class _MyCareers extends StatefulWidget {
  const _MyCareers();

  @override
  State<_MyCareers> createState() => _MyCareersState();
}

class _MyCareersState extends State<_MyCareers> {
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
            Expanded(child: CareerMatchesView(studentId: chosen.id, canRate: !isParent)),
          ],
        );
      },
    );
  }
}

class _StaffMatches extends StatefulWidget {
  const _StaffMatches();

  @override
  State<_StaffMatches> createState() => _StaffMatchesState();
}

class _StaffMatchesState extends State<_StaffMatches> {
  Student? _student;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickStudent(context);
              if (picked != null) setState(() => _student = picked);
            },
            icon: const Icon(Icons.person_search_outlined, size: 18),
            label: Text(_student == null ? 'Choose a student' : '${_student!.name} · ${_student!.registerNo}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
          ),
        ),
        if (_student == null)
          const Expanded(
            child: EmptyView(
              'Pick a student to see which careers fit, what is missing and what they could study',
              icon: Icons.explore_outlined,
            ),
          )
        else
          Expanded(child: CareerMatchesView(studentId: _student!.id, canRun: true)),
      ],
    );
  }
}

/// A student's ranked careers. `canRun` adds the staff recompute; `canRate` the rating.
class CareerMatchesView extends StatefulWidget {
  const CareerMatchesView({super.key, required this.studentId, this.canRun = false, this.canRate = false});
  final int studentId;
  final bool canRun;
  final bool canRate;

  @override
  State<CareerMatchesView> createState() => _CareerMatchesViewState();
}

class _CareerMatchesViewState extends State<CareerMatchesView> {
  String _filter = 'all';
  int _reload = 0;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return AsyncView<CareerMatches>(
      refreshKey: '${widget.studentId}|$_reload',
      load: () => careersApi.matches(widget.studentId),
      builder: (context, data, reload) {
        if (data.total == 0) return const EmptyView('No careers in the catalogue yet');
        final rows = data.matches.where((m) => _filter == 'all' || m.readiness == _filter).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final key in ['ready', 'close', 'explore'])
                  Tag('${data.counts[key] ?? 0} ${_readiness[key]!.$1.toLowerCase()}', color: _readiness[key]!.$2),
                if (data.computedAt != null)
                  Text('worked out ${fmtDateTime(data.computedAt)}',
                      style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
              ],
            ),
            const SizedBox(height: 10),
            if (data.isStale)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NoteBanner(
                  title: 'Skills have changed since this was worked out',
                  body: 'Recompute to take the latest skills, certificates and marks into account.',
                  color: Brand.warning,
                  icon: Icons.history,
                  action: TextButton(
                    onPressed: _running ? null : () => _refresh(),
                    child: const Text('Update'),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ChipFilter<String>(
                    value: _filter,
                    options: const [
                      ('all', 'All'),
                      ('ready', 'Ready'),
                      ('close', 'Close'),
                      ('explore', 'Explore'),
                    ],
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Work them out again',
                  onPressed: _running ? null : _refresh,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (rows.isEmpty)
              const EmptyView('Nothing in this group yet')
            else
              ...rows.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MatchCard(
                      match: m,
                      onRate: widget.canRate
                          ? (rating) async {
                              final ok = await runAction(
                                context,
                                () => careersApi.feedback(widget.studentId, m.careerId, rating),
                                success: 'Thanks — your rating helps us suggest better',
                              );
                              if (ok) setState(() => _reload++);
                            }
                          : null,
                    ),
                  )),
          ],
        );
      },
    );
  }

  Future<void> _refresh() async {
    setState(() => _running = true);
    await runAction(
      context,
      () async => widget.canRun
          ? careersApi.run(widget.studentId)
          : careersApi.matches(widget.studentId, refresh: true),
      success: 'Career matches updated',
    );
    if (mounted) {
      setState(() {
        _running = false;
        _reload++;
      });
    }
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, this.onRate});
  final CareerMatch match;
  final ValueChanged<int>? onRate;

  @override
  Widget build(BuildContext context) {
    final r = _readiness[match.readiness] ?? _readiness['explore']!;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Text('#${match.rank}', style: const TextStyle(fontSize: 12.5, color: Brand.muted)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(match.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
              Text(match.finalScore.toStringAsFixed(match.finalScore % 1 == 0 ? 0 : 1),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Text(' /100', style: TextStyle(fontSize: 11, color: Brand.muted)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Tooltip(message: r.$3, child: Tag(r.$1, color: r.$2)),
                  if (match.domain != null) Tag(match.domain!),
                  if (match.avgPackage != null) Tag('typically ${lpa(match.avgPackage)}'),
                ]),
                const SizedBox(height: 6),
                Text(match.explanation, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                const SizedBox(height: 4),
                Text(
                  'skills ${match.skillScore.toStringAsFixed(0)}% · academics ${match.academicScore.toStringAsFixed(0)}%'
                  ' · ${match.strengths.length} of ${match.strengths.length + match.gaps.length} requirements met',
                  style: const TextStyle(fontSize: 11.5, color: Brand.muted),
                ),
              ],
            ),
          ),
          children: [
            ...[...match.gaps, ...match.strengths].map((s) => MeterBar(
                  label: s.name,
                  progress: s.progress,
                  trailing: '${s.level}/${s.requiredLevel}',
                  emphasise: s.isCore,
                  met: s.gap == 0,
                  tooltip: 'Blended score ${s.score} of the ${s.requiredScore} needed',
                )),
            if (match.gaps.any((g) => g.courses.isNotEmpty)) ...[
              const Divider(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('What to study next',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.textSoft)),
              ),
              const SizedBox(height: 6),
              ...match.gaps.where((g) => g.courses.isNotEmpty).map((g) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: g.courses
                              .map((c) => ActionChip(
                                    label: Text(
                                      '${c.title}${c.provider == null ? '' : ' · ${c.provider}'}'
                                      '${c.hours == null ? '' : ' · ${c.hours}h'}',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    onPressed: c.url == null ? null : () => openLink(context, c.url!),
                                    backgroundColor: Brand.accentSoft,
                                    side: const BorderSide(color: Brand.border),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '* core requirement. Levels come from the blended skill score — what staff recorded, verified '
                'certificates, assessments and subject marks together.',
                style: TextStyle(fontSize: 11, color: Brand.muted),
              ),
            ),
            if (onRate != null) ...[
              const Divider(height: 22),
              Row(
                children: [
                  const Text('Is this useful?', style: TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                  const SizedBox(width: 10),
                  Stars(match.rating ?? 0, size: 22, onChanged: onRate),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- catalogue

class _CareerCatalogue extends StatefulWidget {
  const _CareerCatalogue({this.readOnly = false});
  final bool readOnly;

  @override
  State<_CareerCatalogue> createState() => _CareerCatalogueState();
}

class _CareerCatalogueState extends State<_CareerCatalogue> {
  String _search = '';
  String? _domain;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final canCreate = !widget.readOnly && session.can(['career.create']);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Career'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(flex: 3, child: SearchBox(hint: 'Search careers', onChanged: (v) => setState(() => _search = v))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FutureBuilder<List<String>>(
                    future: careersApi.domains(),
                    builder: (context, snap) => DropdownButtonFormField<String>(
                      initialValue: _domain,
                      isExpanded: true,
                      hint: const Text('Domain', style: TextStyle(fontSize: 13)),
                      items: [
                        const DropdownMenuItem<String>(value: null, child: Text('All')),
                        ...(snap.data ?? []).map((d) =>
                            DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (v) => setState(() => _domain = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Career>>(
              refreshKey: '$_search|$_domain|$_reload',
              load: () => careersApi.list(search: _search, domain: _domain),
              builder: (context, careers, reload) {
                if (careers.isEmpty) return const EmptyView('No careers matched');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: careers
                      .map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _CareerCard(
                              career: c,
                              canEdit: !widget.readOnly && session.can(['career.update']),
                              canDelete: !widget.readOnly && session.can(['career.delete']),
                              onEdit: () => _edit(c),
                              onDelete: () => _delete(c),
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

  Future<void> _edit(Career? career) async {
    final saved = await showFormSheet<bool>(
      context,
      career == null ? 'New career' : 'Edit ${career.name}',
      (ctx) => _CareerForm(career: career),
    );
    if (saved == true) setState(() => _reload++);
  }

  Future<void> _delete(Career c) async {
    if (!await confirm(context, 'Delete ${c.name}?', danger: true, okLabel: 'Delete')) return;
    final ok = await runAction(context, () => careersApi.remove(c.id), success: 'Career deleted');
    if (ok) setState(() => _reload++);
  }
}

class _CareerCard extends StatelessWidget {
  const _CareerCard({
    required this.career,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final Career career;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(career.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${career.code}${career.domain == null ? '' : ' · ${career.domain}'} · '
                'typically ${lpa(career.avgPackage)} · CGPA ${career.minCgpa}+',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            children: [
              if (career.description != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(career.description!, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: career.skills
                      .map((s) => Tag('${s.name} L${s.requiredLevel}${s.isCore ? ' *' : ''}',
                          color: s.isCore ? Brand.accent : null))
                      .toList(),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${career.courseCount} course${career.courseCount == 1 ? '' : 's'} listed for these skills',
                    style: const TextStyle(fontSize: 12, color: Brand.muted)),
              ),
              if (canEdit || canDelete) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (canEdit)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                          child: const Text('Edit'),
                        ),
                      ),
                    if (canEdit && canDelete) const SizedBox(width: 8),
                    if (canDelete)
                      IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Brand.error)),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _CareerForm extends StatefulWidget {
  const _CareerForm({this.career});
  final Career? career;

  @override
  State<_CareerForm> createState() => _CareerFormState();
}

class _CareerFormState extends State<_CareerForm> {
  late final _code = TextEditingController(text: widget.career?.code);
  late final _name = TextEditingController(text: widget.career?.name);
  late final _domain = TextEditingController(text: widget.career?.domain);
  late final _description = TextEditingController(text: widget.career?.description);
  late final _package = TextEditingController(text: widget.career?.avgPackage?.toString());
  late final _minCgpa = TextEditingController(text: '${widget.career?.minCgpa ?? 0}');
  late final List<Map<String, dynamic>> _skills = (widget.career?.skills ?? [])
      .map((s) => {
            'skill_id': s.skillId,
            'required_level': s.requiredLevel,
            'weight': s.weight,
            'is_core': s.isCore,
          })
      .toList();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _domain, _description, _package, _minCgpa]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Field('Code',
                    child: TextField(controller: _code, textCapitalization: TextCapitalization.characters)),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: Field('Name', child: TextField(controller: _name))),
            ],
          ),
          Field('Domain', hint: 'e.g. IT / Software', child: TextField(controller: _domain)),
          Row(
            children: [
              Expanded(
                child: Field('Typical package (LPA)',
                    child: TextField(controller: _package, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Field('Minimum CGPA',
                    child: TextField(controller: _minCgpa, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              ),
            ],
          ),
          Field('What the job involves', child: TextField(controller: _description, maxLines: 3)),
          const Divider(height: 24),
          const Text('Skills it needs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'A core skill must be met before a student counts as ready. Weight decides how much a skill moves the match score.',
            style: TextStyle(fontSize: 12, color: Brand.muted),
          ),
          const SizedBox(height: 12),
          ..._skills.asMap().entries.map((e) {
            final i = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RefPicker(
                          hint: 'Skill',
                          allowClear: false,
                          load: Lookups.skills,
                          value: asIntOrNull(_skills[i]['skill_id']),
                          onChanged: (v) => setState(() => _skills[i]['skill_id'] = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _skills.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: asInt(_skills[i]['required_level'], 3),
                          items: [1, 2, 3, 4, 5]
                              .map((l) => DropdownMenuItem(value: l, child: Text('Level $l')))
                              .toList(),
                          onChanged: (v) => setState(() => _skills[i]['required_level'] = v ?? 3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 86,
                        child: TextFormField(
                          initialValue: '${_skills[i]['weight'] ?? 1}',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'weight'),
                          onChanged: (v) => _skills[i]['weight'] = double.tryParse(v) ?? 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          const Text('core', style: TextStyle(fontSize: 11, color: Brand.textSoft)),
                          Switch(
                            value: _skills[i]['is_core'] == true,
                            activeThumbColor: Brand.accent,
                            onChanged: (v) => setState(() => _skills[i]['is_core'] = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => setState(() =>
                _skills.add({'skill_id': null, 'required_level': 3, 'weight': 1.0, 'is_core': false})),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a skill'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.career == null ? 'Add career' : 'Save changes'),
          ),
        ],
      );

  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      toast(context, 'Code and name are required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'code': _code.text.trim().toUpperCase(),
      'name': _name.text.trim(),
      'domain': _domain.text.trim().isEmpty ? null : _domain.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'avg_package': double.tryParse(_package.text.trim()),
      'min_cgpa': double.tryParse(_minCgpa.text.trim()) ?? 0,
      'skills': _skills
          .where((s) => s['skill_id'] != null)
          .map((s) => {
                'skill_id': s['skill_id'],
                'required_level': s['required_level'],
                'weight': s['weight'] ?? 1,
                'is_core': s['is_core'] == true,
              })
          .toList(),
    };
    final ok = await runAction(
      context,
      () => widget.career == null ? careersApi.create(body) : careersApi.update(widget.career!.id, body),
      success: widget.career == null ? 'Career added' : 'Career updated',
    );
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }
}

class _CoursesMaster extends StatelessWidget {
  const _CoursesMaster();

  @override
  Widget build(BuildContext context) => MasterCrud(
        path: 'courses',
        permission: 'career',
        noun: 'course',
        subtitle: 'What a student can study to close a skill gap. These appear under every career that needs the skill.',
        fields: [
          MasterField('skill_id', 'Skill it teaches',
              type: MasterFieldType.reference, required: true, lookup: Lookups.skills),
          const MasterField('title', 'Course title', required: true),
          const MasterField('provider', 'Provider', hint: 'NPTEL, Coursera, in-house…'),
          const MasterField('url', 'Link'),
          const MasterField('level', 'Level it takes you to', type: MasterFieldType.integer),
          const MasterField('duration_hours', 'Hours', type: MasterFieldType.integer),
          const MasterField('is_certification', 'Gives a certificate', type: MasterFieldType.boolean),
          const MasterField('is_free', 'Free', type: MasterFieldType.boolean),
        ],
        title: _courseTitle,
        badges: _courseBadges,
      );

  static (String, String?) _courseTitle(MasterRow r) => (
        text(r['title']),
        '${r['skill_name'] ?? ''} · level ${asInt(r['level'])}'
            '${r['provider'] == null ? '' : ' · ${r['provider']}'}',
      );

  static List<Widget> _courseBadges(MasterRow r) => [
        if (asBool(r['is_free'])) const Tag('Free', color: Brand.success),
      ];
}
