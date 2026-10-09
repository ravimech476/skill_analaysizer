import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/import_upload.dart';
import '../widgets/pickers.dart';

/// Staff work class by class and maintain the skill master, the subject mapping and
/// the scoring weights; students and parents read what is recorded for them.
class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isStaff) return const _MySkills();

    final tabs = <(String, Widget)>[
      ('By class', const _ClassSkills()),
      if (session.can(['student_skill.create'])) ('Import', const _SkillsImport()),
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

// ---------------------------------------------------------------- by class

class _ClassSkills extends StatefulWidget {
  const _ClassSkills();

  @override
  State<_ClassSkills> createState() => _ClassSkillsState();
}

class _ClassSkillsState extends State<_ClassSkills> {
  int? _classId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: RefPicker(
            hint: 'Pick a class',
            allowClear: false,
            load: Lookups.classes,
            value: _classId,
            onChanged: (v) => setState(() => _classId = v),
          ),
        ),
        if (_classId == null)
          const Expanded(child: EmptyView("Pick a class to see and record its students' skills"))
        else
          Expanded(
            child: AsyncView<Map<String, dynamic>>(
              refreshKey: _classId,
              load: () => skillsApi.matrix(_classId!),
              builder: (context, matrix, reload) {
                final rows = maps(matrix['rows']);
                if (rows.isEmpty) return const EmptyView('No students in this class yet');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows.map((r) {
                    final skills = ((r['skills'] ?? {}) as Map);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text(text(r['name']), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          subtitle: Text('${r['register_no']} · ${skills.length} skills recorded',
                              style: const TextStyle(fontSize: 12.5)),
                          trailing: const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
                          onTap: () async {
                            await push(
                              context,
                              SubPage(
                                title: text(r['name']),
                                subtitle: 'Skills',
                                child: StudentSkillsView(studentId: asInt(r['student_id'])),
                              ),
                            );
                            reload();
                          },
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- student / parent

class _MySkills extends StatefulWidget {
  const _MySkills();

  @override
  State<_MySkills> createState() => _MySkillsState();
}

class _MySkillsState extends State<_MySkills> {
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
            Expanded(child: StudentSkillsView(studentId: chosen.id)),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- one student's skills

/// A student's skills with their blended scores. Staff can record, verify and remove;
/// students and parents read.
class StudentSkillsView extends StatefulWidget {
  const StudentSkillsView({super.key, required this.studentId});
  final int studentId;

  @override
  State<StudentSkillsView> createState() => _StudentSkillsViewState();
}

class _StudentSkillsViewState extends State<StudentSkillsView> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final canEdit = session.isStaff && session.can(['student_skill.create', 'student_skill.update']);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _editSkill(null),
              icon: const Icon(Icons.add),
              label: const Text('Skill'),
            )
          : null,
      body: AsyncView<(List<StudentSkill>, SkillScores?)>(
        refreshKey: '${widget.studentId}|$_reload',
        load: () async {
          final skills = await skillsApi.of(widget.studentId);
          SkillScores? scores;
          try {
            scores = await scoresApi.of(widget.studentId);
          } catch (_) {
            // Scores are a bonus; the recorded levels still matter without them.
          }
          return (skills, scores);
        },
        builder: (context, data, reload) {
          final (skills, scores) = data;
          final byId = {for (final s in scores?.scores ?? <SkillScore>[]) s.skillId: s};

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteBanner(
                title: '${skills.length} skills recorded',
                body: scores?.computedAt == null
                    ? 'A score blends the recorded level with verified certificates, assessments and marks in mapped subjects.'
                    : 'Scores worked out ${fmtDateTime(scores!.computedAt)}. Tap a skill to see what went into it.',
                color: Brand.accent,
                icon: Icons.insights_outlined,
              ),
              const SizedBox(height: 10),
              if (skills.isEmpty)
                const EmptyView('No skills recorded yet', icon: Icons.star_outline)
              else
                ...skills.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SkillCard(
                        skill: s,
                        score: byId[s.skillId],
                        canEdit: canEdit,
                        onEdit: () => _editSkill(s),
                        onVerify: () => _verify(s),
                        onDelete: () => _delete(s),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editSkill(StudentSkill? skill) async {
    final saved = await showFormSheet<bool>(
      context,
      skill == null ? 'Record a skill' : 'Edit ${skill.name}',
      (ctx) => _SkillForm(studentId: widget.studentId, skill: skill),
    );
    if (saved == true) setState(() => _reload++);
  }

  Future<void> _verify(StudentSkill s) async {
    final ok = await runAction(
      context,
      () => skillsApi.verify(widget.studentId, s.skillId, !s.verified),
      success: s.verified ? 'Verification withdrawn' : 'Certificate verified',
    );
    if (ok) setState(() => _reload++);
  }

  Future<void> _delete(StudentSkill s) async {
    if (!await confirm(context, 'Remove ${s.name}?', danger: true, okLabel: 'Remove')) return;
    final ok = await runAction(
      context,
      () => skillsApi.remove(widget.studentId, s.skillId),
      success: 'Skill removed',
    );
    if (ok) setState(() => _reload++);
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.score,
    required this.canEdit,
    required this.onEdit,
    required this.onVerify,
    required this.onDelete,
  });

  final StudentSkill skill;
  final SkillScore? score;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onVerify;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final blended = score?.score ?? skill.score;
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(skill.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
              if (skill.verified)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.verified, size: 16, color: Brand.success),
                ),
              if (blended != null)
                Text(
                  blended.toStringAsFixed(blended % 1 == 0 ? 0 : 2),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: blended >= 80 ? Brand.success : (blended >= 50 ? Brand.accent : Brand.warning),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Stars(skill.proficiency, size: 15),
                const SizedBox(width: 8),
                Text(levelNames[skill.proficiency.clamp(0, 5)],
                    style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
              ],
            ),
          ),
          children: [
            if (score != null && score!.breakdown.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('What the score is built from',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.textSoft)),
              ),
              const SizedBox(height: 6),
              ...score!.breakdown.map((p) => MeterBar(
                    label: sourceLabels[p.source] ?? pretty(p.source),
                    progress: p.score / 100,
                    trailing: p.score.toStringAsFixed(0),
                    met: true,
                    tooltip: 'Weight ${p.weight}',
                  )),
              const SizedBox(height: 4),
              const Text(
                'Sources with nothing recorded are left out rather than counted as zero.',
                style: TextStyle(fontSize: 11.5, color: Brand.muted),
              ),
              const Divider(height: 20),
            ],
            DetailRow('Recorded as', pretty(skill.source)),
            DetailRow('Recorded by', '${skill.recordedBy ?? '—'} · ${fmtDate(skill.updatedAt)}'),
            if (skill.remarks != null) DetailRow('Remarks', skill.remarks),
            if (skill.verified)
              DetailRow('Verified by', '${skill.verifiedBy ?? 'staff'} · ${fmtDate(skill.verifiedAt)}'),
            if (skill.certificate != null) ...[
              const SizedBox(height: 8),
              FileTile(link: skill.certificate!, label: 'Certificate', dense: true),
            ] else if (skill.certificateUrl != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openLink(context, skill.certificateUrl!),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Open certificate link'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              ),
            ],
            if (canEdit) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                      child: const Text('Edit'),
                    ),
                  ),
                  if (skill.hasProof) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: skill.verified ? Brand.warning : Brand.success,
                          minimumSize: const Size(0, 38),
                        ),
                        onPressed: onVerify,
                        child: Text(skill.verified ? 'Unverify' : 'Verify'),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, color: Brand.error),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkillForm extends StatefulWidget {
  const _SkillForm({required this.studentId, this.skill});
  final int studentId;
  final StudentSkill? skill;

  @override
  State<_SkillForm> createState() => _SkillFormState();
}

class _SkillFormState extends State<_SkillForm> {
  late int? _skillId = widget.skill?.skillId;
  late int _level = widget.skill?.proficiency ?? 3;
  late String _source = widget.skill?.source ?? 'assessment';
  late final _remarks = TextEditingController(text: widget.skill?.remarks);
  late final _certUrl = TextEditingController(text: widget.skill?.certificateUrl);
  late FileLink? _certificate = widget.skill?.certificate;
  bool _removeCert = false;
  bool _busy = false;

  @override
  void dispose() {
    _remarks.dispose();
    _certUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            'Skill',
            child: RefPicker(
              hint: 'Skill',
              allowClear: false,
              load: Lookups.skills,
              value: _skillId,
              onChanged: widget.skill == null ? (v) => setState(() => _skillId = v) : (_) {},
            ),
          ),
          Field(
            'Level',
            hint: levelNames[_level.clamp(0, 5)],
            child: Align(
              alignment: Alignment.centerLeft,
              child: Stars(_level, size: 30, onChanged: (v) => setState(() => _level = v)),
            ),
          ),
          Field(
            'How it was assessed',
            child: EnumPicker(
              value: _source,
              options: const ['assessment', 'certification', 'project', 'internship', 'course'],
              onChanged: (v) => setState(() => _source = v ?? 'assessment'),
            ),
          ),
          Field('Remarks', child: TextField(controller: _remarks, maxLines: 2)),
          Field(
            'Certificate link',
            hint: 'Or attach the file below. A verified certificate counts towards the score.',
            child: TextField(controller: _certUrl, keyboardType: TextInputType.url),
          ),
          Field(
            'Certificate file',
            child: FileSlot(
              category: 'certificate',
              current: _removeCert ? null : _certificate,
              onChanged: (fileId, link) async => setState(() {
                _certificate = link;
                _removeCert = link == null;
              }),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy || _skillId == null
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runAction(
                      context,
                      () => skillsApi.save(widget.studentId, {
                        'skill_id': _skillId,
                        'proficiency': _level,
                        'source': _source,
                        'remarks': _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
                        'certificate_url': _certUrl.text.trim().isEmpty ? null : _certUrl.text.trim(),
                        if (_certificate?.id != null) 'certificate_file_id': _certificate!.id,
                        if (_removeCert) 'remove_certificate': true,
                      }),
                      success: 'Skill saved',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save skill'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- subject → skill mapping

/// Which skills each subject teaches — the link that lets marks move a skill score.
class SubjectSkillMapping extends StatefulWidget {
  const SubjectSkillMapping({super.key});

  @override
  State<SubjectSkillMapping> createState() => _SubjectSkillMappingState();
}

class _SubjectSkillMappingState extends State<SubjectSkillMapping> {
  String _search = '';
  String? _mapped;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['subject.update']);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              SearchBox(hint: 'Search subjects', onChanged: (v) => setState(() => _search = v)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ChipFilter<String?>(
                  value: _mapped,
                  options: const [(null, 'All'), ('true', 'Mapped'), ('false', 'Not mapped')],
                  onChanged: (v) => setState(() => _mapped = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            refreshKey: '$_search|$_mapped|$_reload',
            load: () => scoresApi.subjectMappings(search: _search, mapped: _mapped),
            builder: (context, data, reload) {
              final subjects = maps(data['subjects']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NoteBanner(
                    title: 'Marks only count towards a skill once the subject is mapped to it',
                    body: '${asInt(data['mapped'])} of ${asInt(data['total'])} subjects mapped. '
                        'Weight decides how much a subject counts when several feed one skill.',
                  ),
                  const SizedBox(height: 10),
                  if (subjects.isEmpty)
                    const EmptyView('No subjects matched')
                  else
                    ...subjects.map((s) {
                      final skills = maps(s['skills']);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text('${s['subject_code']} · ${s['subject_name']}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: skills.isEmpty
                                  ? const Text('Not mapped — its marks do not count towards any skill',
                                      style: TextStyle(fontSize: 12.5, color: Brand.muted))
                                  : Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: skills
                                          .map((k) => Tag(
                                              '${k['name']}${asDouble(k['weight'], 1) == 1 ? '' : ' × ${k['weight']}'}'))
                                          .toList(),
                                    ),
                            ),
                            trailing: canEdit
                                ? TextButton(
                                    onPressed: () async {
                                      final saved = await showFormSheet<bool>(
                                        context,
                                        '${s['subject_code']} · ${s['subject_name']}',
                                        (ctx) => _MappingForm(
                                          subjectId: asInt(s['subject_id']),
                                          initial: skills
                                              .map((k) => {
                                                    'skill_id': asInt(k['skill_id']),
                                                    'weight': asDouble(k['weight'], 1),
                                                  })
                                              .toList(),
                                        ),
                                      );
                                      if (saved == true) setState(() => _reload++);
                                    },
                                    child: Text(skills.isEmpty ? 'Map' : 'Edit'),
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MappingForm extends StatefulWidget {
  const _MappingForm({required this.subjectId, required this.initial});
  final int subjectId;
  final List<Map<String, dynamic>> initial;

  @override
  State<_MappingForm> createState() => _MappingFormState();
}

class _MappingFormState extends State<_MappingForm> {
  late final List<Map<String, dynamic>> _rows = List.of(widget.initial);
  bool _busy = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Marks in this subject will count towards each skill below, weighted as shown. '
            'Saving recomputes the scores of every student with marks in it.',
            style: TextStyle(fontSize: 12.5, color: Brand.textSoft),
          ),
          const SizedBox(height: 14),
          ..._rows.asMap().entries.map((e) {
            final i = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: RefPicker(
                      hint: 'Skill',
                      allowClear: false,
                      load: Lookups.skills,
                      value: asIntOrNull(_rows[i]['skill_id']),
                      onChanged: (v) => setState(() => _rows[i]['skill_id'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: '${_rows[i]['weight'] ?? 1}',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'weight'),
                      onChanged: (v) => _rows[i]['weight'] = double.tryParse(v) ?? 1,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _rows.removeAt(i)),
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => setState(() => _rows.add({'skill_id': null, 'weight': 1.0})),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a skill'),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final skills = _rows
                        .where((r) => r['skill_id'] != null)
                        .map((r) => {'skill_id': r['skill_id'], 'weight': r['weight'] ?? 1})
                        .toList();
                    final ok = await runAction(
                      context,
                      () => scoresApi.setSubjectSkills(widget.subjectId, skills),
                      success: 'Mapping saved — affected students were recomputed',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: const Text('Save mapping'),
          ),
        ],
      );
}

// ---------------------------------------------------------------- scoring weights

/// The weights behind every blended skill score and every match score.
class ScoringWeights extends StatefulWidget {
  const ScoringWeights({super.key});

  @override
  State<ScoringWeights> createState() => _ScoringWeightsState();
}

class _ScoringWeightsState extends State<ScoringWeights> {
  Map<String, double> _blend = {};
  Map<String, double> _match = {};
  List<String> _sources = const [];
  bool _busy = false;
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['config.update']);
    return AsyncView<Map<String, dynamic>>(
      load: () async {
        final data = await scoresApi.scoring();
        if (!_loaded) {
          final settings = {for (final s in maps(data['settings'])) text(s['key']): s['value']};
          _blend = ((settings['skill_score_weights'] ?? {}) as Map)
              .map((k, v) => MapEntry(k.toString(), asDouble(v)));
          _match = ((settings['match_weights'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), asDouble(v)));
          _sources = ((data['skill_sources'] ?? []) as List).map((e) => e.toString()).toList();
          _loaded = true;
        }
        return data;
      },
      builder: (context, data, reload) {
        final blendTotal = _blend.values.fold<double>(0, (a, b) => a + b);
        final matchTotal = _match.values.fold<double>(0, (a, b) => a + b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NoteBanner(
              title: 'These weights decide every score in the app',
              body: 'A skill score blends the four sources below. Sources with nothing recorded for a student are '
                  'left out and the rest scaled back up, so the weights are a ratio rather than a budget.',
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'What a skill score is made of',
              child: Column(
                children: _sources
                    .map((s) => _WeightRow(
                          label: sourceLabels[s] ?? pretty(s),
                          value: _blend[s] ?? 0,
                          share: blendTotal <= 0 ? 0 : (_blend[s] ?? 0) / blendTotal,
                          enabled: canEdit,
                          onChanged: (v) => setState(() => _blend[s] = v),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            SectionCard(
              title: 'What a match score is made of',
              subtitle: 'Used for both placement drives and career matches.',
              child: Column(
                children: [
                  _WeightRow(
                    label: 'Skill match',
                    value: _match['skill'] ?? 0,
                    share: matchTotal <= 0 ? 0 : (_match['skill'] ?? 0) / matchTotal,
                    enabled: canEdit,
                    onChanged: (v) => setState(() => _match['skill'] = v),
                  ),
                  _WeightRow(
                    label: 'Academic record (CGPA)',
                    value: _match['academic'] ?? 0,
                    share: matchTotal <= 0 ? 0 : (_match['academic'] ?? 0) / matchTotal,
                    enabled: canEdit,
                    onChanged: (v) => setState(() => _match['academic'] = v),
                  ),
                ],
              ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || blendTotal <= 0 || matchTotal <= 0
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ok = await runAction(
                          context,
                          () => scoresApi.saveScoring({'skill_score_weights': _blend, 'match_weights': _match}),
                          success: 'Weights saved. Every student is being recomputed in the background.',
                        );
                        if (mounted) setState(() => _busy = false);
                        if (ok) reload();
                      },
                child: const Text('Save weights'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await confirm(context, 'Recompute every student\'s skill scores?',
                            okLabel: 'Recompute');
                        if (!ok) return;
                        await runAction(
                          context,
                          () async {
                            final r = await scoresApi.recompute({'all': true});
                            if (context.mounted) toast(context, text(r['message'], 'Recomputing'));
                          },
                        );
                      },
                child: const Text('Recompute all scores'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.label,
    required this.value,
    required this.share,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double share;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(0, 1),
                max: 1,
                divisions: 20,
                activeColor: Brand.accent,
                label: value.toStringAsFixed(2),
                onChanged: enabled ? onChanged : null,
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${value.toStringAsFixed(2)}  ${(share * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------- import

class _SkillsImport extends StatelessWidget {
  const _SkillsImport();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        ImportUpload(
          title: 'student skills',
          hint: 'One row per student and skill: register number, skill name and a level from 1 to 5.',
          upload: (file, {required dryRun}) => bulkApi.skills(file, dryRun: dryRun),
        ),
      ],
    );
  }
}
