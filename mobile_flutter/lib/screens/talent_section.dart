import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../api/talent_api.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/pickers.dart';

const _kindTitles = {
  'personality': 'Personality',
  'interests': 'Interests and values',
  'learning': 'Learning behaviour',
};

Color _levelColor(String level) => switch (level) {
      'high' => Brand.success,
      'low' => Brand.error,
      _ => Brand.warning,
    };

/// A short plain-language reading of one student's record. The figures come from the database; a local
/// model only words them, and its text is dropped when it adds anything that is not in the record.
class InsightSection extends StatefulWidget {
  const InsightSection({super.key, required this.studentId});
  final int studentId;

  @override
  State<InsightSection> createState() => _InsightSectionState();
}

class _InsightSectionState extends State<InsightSection> {
  int _version = 0;
  bool _refresh = false;

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        refreshKey: '${widget.studentId}|$_version',
        scrollable: false,
        load: () async {
          final r = await talentApi.insight(widget.studentId, refresh: _refresh);
          _refresh = false;
          return r;
        },
        builder: (context, data, _) {
          final i = (data['insight'] as Map).cast<String, dynamic>();
          Widget list(String title, Color color, dynamic items) {
            final rows = ((items ?? []) as List).map((e) => '$e').toList();
            if (rows.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
                for (final r in rows) Padding(padding: const EdgeInsets.only(top: 3), child: Text('• $r', style: const TextStyle(fontSize: 13))),
              ]),
            );
          }

          return SectionCard(
            title: 'Overall reading',
            trailing: IconButton(
              tooltip: 'Refresh',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => setState(() {
                _refresh = true;
                _version++;
              }),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text(i['summary']), style: const TextStyle(fontSize: 14)),
                list('Strengths', Brand.success, i['strengths']),
                list('Needs attention', Brand.warning, i['focus_areas']),
                list('Next steps', Brand.info, i['next_steps']),
                const SizedBox(height: 10),
                Text(
                  '${text(i['source']) == 'llm' ? 'Worded by the local AI model. ' : 'Written from the record. '}Every figure comes from the student\'s record.',
                  style: const TextStyle(fontSize: 12, color: Brand.textSoft),
                ),
              ],
            ),
          );
        },
      );
}

/// Placement readiness over time, one point per daily snapshot.
class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context) => AsyncView<List<Map<String, dynamic>>>(
        refreshKey: 'history$studentId',
        scrollable: false,
        load: () => talentApi.scoreHistory(studentId),
        builder: (context, points, _) => SectionCard(
          title: 'Readiness over time',
          subtitle: points.length < 2 ? null : 'From ${points.first['readiness']} to ${points.last['readiness']} since ${fmtDate(text(points.first['date']))}.',
          child: TrendChart(
            points: points.map((p) => asDouble(p['readiness'])).toList(),
            labels: points.map((p) => text(p['date']).length >= 10 ? text(p['date']).substring(5) : text(p['date'])).toList(),
          ),
        ),
      );
}

/// Psychometric results and coding data of one student, shown under their analysis.
/// Students manage their own entries; staff can enter, verify and review for students in their scope.
class TalentSection extends StatefulWidget {
  const TalentSection({super.key, required this.studentId});
  final int studentId;

  @override
  State<TalentSection> createState() => _TalentSectionState();
}

class _TalentSectionState extends State<TalentSection> {
  int _version = 0;

  void _reload() => setState(() => _version++);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final self = session.user?.id == widget.studentId;
    final staff = session.can(['student_skill.update']);
    return AsyncView<Map<String, dynamic>>(
      refreshKey: '${widget.studentId}|$_version',
      scrollable: false,
      load: () => talentApi.profile(widget.studentId),
      builder: (context, data, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Psychometric(studentId: widget.studentId, data: data, canWrite: self || staff, onChanged: _reload),
          const SizedBox(height: 10),
          _Aptitude(key: ValueKey('apt$_version'), studentId: widget.studentId, canTake: self, onChanged: _reload),
          const SizedBox(height: 10),
          _Communication(studentId: widget.studentId, data: data, canWrite: self || staff, canReview: staff && !self, onChanged: _reload),
          const SizedBox(height: 10),
          _Coding(studentId: widget.studentId, data: data, canWrite: self || staff, canReview: staff && !self, onChanged: _reload),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- psychometric

class _Psychometric extends StatelessWidget {
  const _Psychometric({required this.studentId, required this.data, required this.canWrite, required this.onChanged});
  final int studentId;
  final Map<String, dynamic> data;
  final bool canWrite;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final psy = (data['psychometric'] as Map?)?.cast<String, dynamic>() ?? const {};
    final aptitude = data['aptitude_score'];
    return SectionCard(
      title: 'Psychometric profile',
      subtitle: 'Short questionnaires on working style, interests and study habits. They describe tendencies, not ability.',
      trailing: aptitude == null ? null : Tag('Aptitude $aptitude', color: Brand.info),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final kind in _kindTitles.keys) ...[
            const SizedBox(height: 10),
            _kindBlock(context, kind, psy[kind] as Map<String, dynamic>?),
          ],
        ],
      ),
    );
  }

  Widget _kindBlock(BuildContext context, String kind, Map<String, dynamic>? r) {
    final traits = maps(r?['traits']);
    final signals = r?['signals'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: _kindTitles[kind], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (r != null)
                  TextSpan(text: '  taken ${fmtDate(text(r['taken_at']))}', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
              ])),
            ),
            if (canWrite)
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final saved = await push<bool>(
                    context,
                    SubPage(title: _kindTitles[kind]!, child: _QuestionnaireScreen(studentId: studentId, kind: kind)),
                  );
                  if (saved == true) onChanged();
                },
                child: Text(r == null ? 'Take' : 'Retake'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (r == null)
          const Text('Not taken yet', style: TextStyle(fontSize: 13, color: Brand.muted))
        else ...[
          NoteBanner(title: text(r['headline']), color: Brand.info, icon: Icons.info_outline),
          const SizedBox(height: 6),
          for (final t in traits) _TraitBar(t),
          if (kind == 'learning' && signals != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'From the app: ${signals['attendance_percent'] != null ? 'attendance ${signals['attendance_percent']}%, ' : ''}'
                '${asInt(signals['ai_questions_30_days'])} question(s) asked to the AI assistant in the last 30 days.',
                style: const TextStyle(fontSize: 12, color: Brand.textSoft),
              ),
            ),
        ],
      ],
    );
  }
}

class _TraitBar extends StatelessWidget {
  const _TraitBar(this.trait);
  final Map<String, dynamic> trait;

  @override
  Widget build(BuildContext context) {
    final level = text(trait['level']);
    final color = _levelColor(level);
    return Tooltip(
      message: text(trait['meaning']),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 128, child: Text(text(trait['label']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (asDouble(trait['score']) / 100).clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: Brand.borderSoft,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            SizedBox(width: 64, child: Text(level, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

class _QuestionnaireScreen extends StatefulWidget {
  const _QuestionnaireScreen({required this.studentId, required this.kind});
  final int studentId;
  final String kind;

  @override
  State<_QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<_QuestionnaireScreen> {
  final _answers = <String, int>{};
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await talentApi.submit(widget.studentId, widget.kind, _answers);
      if (!mounted) return;
      toast(context, 'Saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        refreshKey: widget.kind,
        scrollable: false,
        load: () => talentApi.questionnaire(widget.kind),
        builder: (context, q, _) {
          final questions = maps(q['questions']);
          final scale = ((q['scale'] ?? []) as List).cast<String>();
          final firstValue = questions.indexWhere((x) => text(x['trait']).startsWith('val_'));
          final done = _answers.length;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  children: [
                    Text(text(q['intro']), style: const TextStyle(color: Brand.textSoft, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text([for (var i = 0; i < scale.length; i++) '${i + 1} = ${scale[i]}'].join('  ·  '),
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: questions.isEmpty ? 0 : done / questions.length),
                    const SizedBox(height: 2),
                    Text('$done of ${questions.length} answered', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                    for (var i = 0; i < questions.length; i++) ...[
                      if (i == firstValue)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text('What matters to you in a job?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. ${text(questions[i]['text'])}', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (var n = 1; n <= 5; n++)
                                  ChoiceChip(
                                    label: Text('$n'),
                                    selected: _answers[text(questions[i]['id'])] == n,
                                    onSelected: (_) => setState(() => _answers[text(questions[i]['id'])] = n),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: const BoxDecoration(color: Brand.surface, border: Border(top: BorderSide(color: Brand.border))),
                  child: FilledButton(
                    onPressed: _saving || done < questions.length ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save answers'),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- aptitude

Color _percentColor(double p) => p >= 65 ? Brand.success : (p >= 40 ? Brand.warning : Brand.error);

class _SectionBars extends StatelessWidget {
  const _SectionBars(this.sections);
  final Map<String, dynamic> sections;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final e in sections.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 128, child: Text(aptitudeSections[e.key] ?? e.key, style: const TextStyle(fontSize: 12.5))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (asDouble((e.value as Map)['percent']) / 100).clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: Brand.borderSoft,
                        valueColor: AlwaysStoppedAnimation(_percentColor(asDouble((e.value as Map)['percent']))),
                      ),
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${asInt((e.value as Map)['correct'])}/${asInt((e.value as Map)['total'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
        ],
      );
}

class _Aptitude extends StatelessWidget {
  const _Aptitude({super.key, required this.studentId, required this.canTake, required this.onChanged});
  final int studentId;
  final bool canTake;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        refreshKey: 'apt$studentId',
        scrollable: false,
        load: () => talentApi.aptitude(studentId),
        builder: (context, d, _) {
          final latest = d['latest'] as Map<String, dynamic>?;
          final history = maps(d['history']);
          final waitUntil = DateTime.tryParse(text(d['can_take_after']))?.toLocal();
          final inProgress = d['in_progress'] == true;
          final blocked = !inProgress && waitUntil != null;
          return SectionCard(
            title: 'Aptitude test',
            subtitle: '${asInt(d['per_section']) * 3} questions (quantitative, logical, verbal), ${asInt(d['time_limit_sec']) ~/ 60} minutes. '
                'The latest score counts towards placement readiness; it can be repeated once a day.',
            trailing: latest == null ? null : Tag('Score ${latest['score']}', color: Brand.info),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (latest == null)
                  const Text('Not taken yet', style: TextStyle(fontSize: 13, color: Brand.muted))
                else ...[
                  _SectionBars((latest['sections'] as Map).cast<String, dynamic>()),
                  Text(
                    'Taken ${fmtDate(text(latest['submitted_at']))}'
                    '${history.length > 1 ? ' · earlier scores: ${history.skip(1).take(4).map((h) => h['score']).join(', ')}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Brand.textSoft),
                  ),
                ],
                if (canTake) ...[
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: blocked
                        ? null
                        : () async {
                            await push<bool>(context, SubPage(title: 'Aptitude test', child: _AptitudeTestScreen(studentId: studentId)));
                            onChanged();
                          },
                    child: Text(inProgress ? 'Resume test' : (latest == null ? 'Take the test' : 'Take the test again')),
                  ),
                  if (blocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('You can take it again after ${fmtDate(waitUntil.toIso8601String())}',
                          style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                    ),
                ],
              ],
            ),
          );
        },
      );
}

class _AptitudeTestScreen extends StatefulWidget {
  const _AptitudeTestScreen({required this.studentId});
  final int studentId;

  @override
  State<_AptitudeTestScreen> createState() => _AptitudeTestScreenState();
}

class _AptitudeTestScreenState extends State<_AptitudeTestScreen> {
  late final Future<Map<String, dynamic>> _start = talentApi.startAptitude(widget.studentId);
  final _answers = <String, String>{};
  Map<String, dynamic>? _attempt;
  Map<String, dynamic>? _result;
  Timer? _timer;
  DateTime? _deadline;
  int _left = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _begin(Map<String, dynamic> attempt) {
    if (_attempt != null) return;
    _attempt = attempt;
    _deadline = DateTime.now().add(Duration(seconds: asInt(attempt['remaining_sec'])));
    _left = asInt(attempt['remaining_sec']);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _deadline!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
      if (!mounted) return;
      setState(() => _left = left);
      if (left == 0) _submit();
    });
  }

  Future<void> _submit() async {
    if (_submitting || _result != null) return;
    setState(() => _submitting = true);
    try {
      final r = await talentApi.submitAptitude(asInt(_attempt!['attempt_id']), _answers);
      _timer?.cancel();
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _start,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: NoteBanner(title: 'The test could not be started', body: errorMessage(snap.error!), color: Brand.warning, icon: Icons.info_outline),
            );
          }
          final result = _result;
          if (result != null) {
            return ListView(padding: const EdgeInsets.all(16), children: [
              StatTile(label: 'Score', value: '${result['score']} / 100', icon: Icons.quiz_outlined, color: Brand.accent),
              const SizedBox(height: 8),
              Text('${asInt(result['correct'])} of ${asInt(result['total'])} correct.', style: const TextStyle(color: Brand.textSoft)),
              const SizedBox(height: 8),
              _SectionBars((result['sections'] as Map).cast<String, dynamic>()),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Done')),
            ]);
          }
          _begin(snap.data!);
          final questions = maps(_attempt!['questions']);
          final answered = _answers.length;
          final clock = '${_left ~/ 60}:${(_left % 60).toString().padLeft(2, '0')}';
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  children: [
                    for (var i = 0; i < questions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tag(aptitudeSections[text(questions[i]['section'])] ?? text(questions[i]['section'])),
                            const SizedBox(height: 4),
                            Text('${i + 1}. ${text(questions[i]['text'])}', style: const TextStyle(fontSize: 14)),
                            RadioGroup<String>(
                              groupValue: _answers[text(questions[i]['id'])],
                              onChanged: (v) => setState(() => _answers[text(questions[i]['id'])] = v!),
                              child: Column(children: [
                                for (var k = 0; k < 4; k++)
                                  RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    value: 'abcd'[k],
                                    title: Text('${'ABCD'[k]}. ${((questions[i]['options'] as List)[k])}', style: const TextStyle(fontSize: 13.5)),
                                  ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: const BoxDecoration(color: Brand.surface, border: Border(top: BorderSide(color: Brand.border))),
                  child: Row(
                    children: [
                      Text('Time left $clock', style: TextStyle(fontWeight: FontWeight.w600, color: _left < 60 ? Brand.error : Brand.textSoft)),
                      const Spacer(),
                      FilledButton(
                        onPressed: _submitting
                            ? null
                            : () async {
                                final unanswered = questions.length - answered;
                                final ok = await confirm(context, unanswered > 0 ? 'Submit with $unanswered unanswered?' : 'Submit your answers?', okLabel: 'Submit');
                                if (ok) _submit();
                              },
                        child: Text('Submit ($answered/${questions.length})'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- communication

class _Communication extends StatelessWidget {
  const _Communication({required this.studentId, required this.data, required this.canWrite, required this.canReview, required this.onChanged});
  final int studentId;
  final Map<String, dynamic> data;
  final bool canWrite;
  final bool canReview;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = (data['communication'] as Map?)?.cast<String, dynamic>() ?? const {};
    final self = c['self'] as Map<String, dynamic>?;
    final review = c['review'] as Map<String, dynamic>?;
    final rubric = (review?['rubric'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SectionCard(
      title: 'Communication and soft skills',
      subtitle: text(c['formula']),
      trailing: c['score'] == null ? null : Tag('Score ${c['score']}', color: Brand.info),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Staff review', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (canReview)
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final saved = await showFormSheet<bool>(context, 'Rate communication', (ctx) => _CommunicationReviewForm(studentId: studentId, existing: review));
                  if (saved == true) onChanged();
                },
                child: Text(review == null ? 'Rate communication' : 'Update review'),
              ),
          ]),
          const SizedBox(height: 6),
          if (review == null)
            const NoteBanner(title: 'Not reviewed yet', body: 'The score appears once a staff member has rated communication.', color: Brand.info, icon: Icons.info_outline)
          else ...[
            for (final e in communicationCriteria.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 128, child: Text(e.value, style: const TextStyle(fontSize: 12.5))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (asInt(rubric[e.key]) / 5).clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: Brand.borderSoft,
                        valueColor: AlwaysStoppedAnimation(_percentColor(asInt(rubric[e.key]) * 20.0)),
                      ),
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${asInt(rubric[e.key])}/5', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            Text(
              'Reviewed ${fmtDate(text(review['reviewed_at']))}'
              '${text(review['reviewed_by']).isEmpty ? '' : ' by ${text(review['reviewed_by'])}'}'
              '${text(review['notes']).isEmpty ? '' : '. ${text(review['notes'])}'}',
              style: const TextStyle(fontSize: 12, color: Brand.textSoft),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Self-assessment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (self != null) TextSpan(text: '  taken ${fmtDate(text(self['taken_at']))}', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
              ])),
            ),
            if (canWrite)
              OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final saved = await push<bool>(
                    context,
                    SubPage(title: 'Communication and soft skills', child: _QuestionnaireScreen(studentId: studentId, kind: 'communication')),
                  );
                  if (saved == true) onChanged();
                },
                child: Text(self == null ? 'Take' : 'Retake'),
              ),
          ]),
          const SizedBox(height: 6),
          if (self == null)
            const Text('Not taken yet', style: TextStyle(fontSize: 13, color: Brand.muted))
          else ...[
            NoteBanner(title: text(self['headline']), color: Brand.info, icon: Icons.info_outline),
            const SizedBox(height: 6),
            for (final t in maps(self['traits'])) _TraitBar(t),
          ],
        ],
      ),
    );
  }
}

class _CommunicationReviewForm extends StatefulWidget {
  const _CommunicationReviewForm({required this.studentId, this.existing});
  final int studentId;
  final Map<String, dynamic>? existing;

  @override
  State<_CommunicationReviewForm> createState() => _CommunicationReviewFormState();
}

class _CommunicationReviewFormState extends State<_CommunicationReviewForm> {
  late final Map<String, int> _rubric = {
    for (final e in ((widget.existing?['rubric'] as Map?) ?? const {}).entries) '${e.key}': asInt(e.value),
  };
  late final _notes = TextEditingController(text: text(widget.existing?['notes']));
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await talentApi.reviewCommunication(widget.studentId, _rubric, _notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = communicationCriteria.keys.every(_rubric.containsKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Rate each area from 1 (needs a lot of work) to 5 (excellent), based on presentations, viva, group work and written submissions.',
            style: TextStyle(fontSize: 13, color: Brand.textSoft)),
        for (final e in communicationCriteria.entries)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              SizedBox(width: 90, child: Text(e.value)),
              Wrap(spacing: 6, children: [
                for (var n = 1; n <= 5; n++) ChoiceChip(label: Text('$n'), selected: _rubric[e.key] == n, onSelected: (_) => setState(() => _rubric[e.key] = n)),
              ]),
            ]),
          ),
        Field('Notes for the student (optional)', child: TextField(controller: _notes, maxLines: 2)),
        FilledButton(onPressed: _busy || !complete ? null : _save, child: const Text('Save review')),
      ],
    );
  }
}

// ---------------------------------------------------------------- coding

class _Coding extends StatelessWidget {
  const _Coding({required this.studentId, required this.data, required this.canWrite, required this.canReview, required this.onChanged});
  final int studentId;
  final Map<String, dynamic> data;
  final bool canWrite;
  final bool canReview;
  final VoidCallback onChanged;

  Widget _status(bool verified) => verified
      ? const Tag('Verified', color: Brand.success, icon: Icons.check_circle)
      : const Tag('Waiting for staff', icon: Icons.schedule);

  Future<void> _run(BuildContext context, Future<void> Function() action, {String? ok}) async {
    if (await runAction(context, action, success: ok)) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = (data['coding'] as Map).cast<String, dynamic>();
    final profiles = maps(c['profiles']);
    final projects = maps(c['projects']);
    final index = c['index'];
    String show(dynamic v) => v == null ? '—' : text(v);
    return SectionCard(
      title: 'Coding profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileGrid(children: [
            StatTile(label: 'Programming skill index', value: index == null ? '—' : '${show(index)} / 100', icon: Icons.code, color: Brand.accent),
            StatTile(label: 'Platform score', value: show(c['platform_score']), icon: Icons.emoji_events_outlined),
            StatTile(label: 'Project score', value: show(c['project_score']), icon: Icons.build_outlined),
          ]),
          const SizedBox(height: 8),
          if (index == null)
            const NoteBanner(
              title: 'No verified coding data yet',
              body: 'Add your coding platform profiles and projects. Once a staff member verifies them, the index appears here and counts towards placement readiness.',
              color: Brand.info,
              icon: Icons.info_outline,
            )
          else
            Text('${text(c['formula'])} Counted: ${asInt(c['problems_counted'])} problems on ${asInt(c['verified_platforms'])} verified platform(s), '
                '${asInt(c['verified_projects'])} reviewed project(s).',
                style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
          const SizedBox(height: 14),
          _heading(context, 'Coding platforms', canWrite ? 'Add platform' : null, () => _platformForm(context, null)),
          if (profiles.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('No platforms added', style: TextStyle(color: Brand.muted, fontSize: 13))),
          for (final p in profiles)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${platforms[text(p['platform'])] ?? text(p['platform'])} · ${text(p['username'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${asInt(p['problems_solved'])} solved${p['rating'] != null ? ' · rating ${p['rating']}' : ''}', style: const TextStyle(fontSize: 12.5)),
                _status(p['verified'] == true),
              ]),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'verify') {
                    await _run(context, () => talentApi.verifyPlatform(asInt(p['id']), p['verified'] != true));
                  } else if (v == 'edit') {
                    _platformForm(context, p);
                  } else if (v == 'open') {
                    openLink(context, text(p['profile_url']));
                  } else if (v == 'delete' && await confirm(context, 'Remove this platform?', danger: true, okLabel: 'Remove')) {
                    if (context.mounted) await _run(context, () => talentApi.removePlatform(asInt(p['id'])));
                  }
                },
                itemBuilder: (_) => [
                  if (text(p['profile_url']).isNotEmpty) const PopupMenuItem(value: 'open', child: Text('Open profile')),
                  if (canReview) PopupMenuItem(value: 'verify', child: Text(p['verified'] == true ? 'Unverify' : 'Verify')),
                  if (canWrite) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (canWrite) const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: Brand.error))),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _heading(context, 'Projects', canWrite ? 'Add project' : null, () => _projectForm(context, null)),
          if (projects.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('No projects added', style: TextStyle(color: Brand.muted, fontSize: 13))),
          for (final p in projects)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(text(p['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (text(p['tech_stack']).isNotEmpty) Text(text(p['tech_stack']), style: const TextStyle(fontSize: 12.5)),
                _status(p['verified'] == true),
                if (p['quality_score'] != null) Text('quality ${p['quality_score']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'review') {
                    _reviewForm(context, p);
                  } else if (v == 'edit') {
                    _projectForm(context, p);
                  } else if (v == 'repo') {
                    openLink(context, text(p['repo_url']));
                  } else if (v == 'live') {
                    openLink(context, text(p['live_url']));
                  } else if (v == 'delete' && await confirm(context, 'Remove this project?', danger: true, okLabel: 'Remove')) {
                    if (context.mounted) await _run(context, () => talentApi.removeProject(asInt(p['id'])));
                  }
                },
                itemBuilder: (_) => [
                  if (text(p['repo_url']).isNotEmpty) const PopupMenuItem(value: 'repo', child: Text('Open code')),
                  if (text(p['live_url']).isNotEmpty) const PopupMenuItem(value: 'live', child: Text('Open live demo')),
                  if (canReview) PopupMenuItem(value: 'review', child: Text(p['verified'] == true ? 'Re-review' : 'Review code')),
                  if (canWrite) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (canWrite) const PopupMenuItem(value: 'delete', child: Text('Remove', style: TextStyle(color: Brand.error))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String? action, VoidCallback onAction) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          if (action != null)
            TextButton.icon(onPressed: onAction, icon: const Icon(Icons.add, size: 18), label: Text(action), style: TextButton.styleFrom(visualDensity: VisualDensity.compact)),
        ],
      );

  Future<void> _platformForm(BuildContext context, Map<String, dynamic>? row) async {
    final saved = await showFormSheet<bool>(context, row == null ? 'Add coding platform' : 'Edit platform', (ctx) => _PlatformForm(studentId: studentId, row: row));
    if (saved == true) onChanged();
  }

  Future<void> _projectForm(BuildContext context, Map<String, dynamic>? row) async {
    final saved = await showFormSheet<bool>(context, row == null ? 'Add project' : 'Edit project', (ctx) => _ProjectForm(studentId: studentId, row: row));
    if (saved == true) onChanged();
  }

  Future<void> _reviewForm(BuildContext context, Map<String, dynamic> project) async {
    final saved = await showFormSheet<bool>(context, 'Review: ${text(project['title'])}', (ctx) => _ReviewForm(project: project));
    if (saved == true) onChanged();
  }
}

class _PlatformForm extends StatefulWidget {
  const _PlatformForm({required this.studentId, this.row});
  final int studentId;
  final Map<String, dynamic>? row;

  @override
  State<_PlatformForm> createState() => _PlatformFormState();
}

class _PlatformFormState extends State<_PlatformForm> {
  late String _platform = text(widget.row?['platform'], 'leetcode');
  late final _user = TextEditingController(text: text(widget.row?['username']));
  late final _url = TextEditingController(text: text(widget.row?['profile_url']));
  late final _solved = TextEditingController(text: widget.row == null ? '0' : text(widget.row!['problems_solved']));
  late final _rating = TextEditingController(text: text(widget.row?['rating']));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_user, _url, _solved, _rating]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_user.text.trim().isEmpty) {
      setState(() => _error = 'Enter your username on that platform');
      return;
    }
    final body = {
      'platform': _platform,
      'username': _user.text.trim(),
      'profile_url': _url.text.trim().isEmpty ? null : _url.text.trim(),
      'problems_solved': int.tryParse(_solved.text.trim()) ?? 0,
      'rating': int.tryParse(_rating.text.trim()),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.row == null) {
        await talentApi.addPlatform(widget.studentId, body);
      } else {
        await talentApi.updatePlatform(asInt(widget.row!['id']), body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline), const SizedBox(height: 12)],
          Field('Platform', child: EnumPicker(value: _platform, options: platforms.keys.toList(), onChanged: (v) => setState(() => _platform = v ?? _platform))),
          Field('Username', child: TextField(controller: _user)),
          Field('Profile link (optional)', hint: 'Staff use this to check the numbers', child: TextField(controller: _url, keyboardType: TextInputType.url)),
          Field('Problems solved', child: TextField(controller: _solved, keyboardType: TextInputType.number)),
          Field('Rating (optional)', child: TextField(controller: _rating, keyboardType: TextInputType.number)),
          FilledButton(onPressed: _busy ? null : _save, child: Text(widget.row == null ? 'Add platform' : 'Save changes')),
        ],
      );
}

class _ProjectForm extends StatefulWidget {
  const _ProjectForm({required this.studentId, this.row});
  final int studentId;
  final Map<String, dynamic>? row;

  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  late final _title = TextEditingController(text: text(widget.row?['title']));
  late final _desc = TextEditingController(text: text(widget.row?['description']));
  late final _tech = TextEditingController(text: text(widget.row?['tech_stack']));
  late final _repo = TextEditingController(text: text(widget.row?['repo_url']));
  late final _live = TextEditingController(text: text(widget.row?['live_url']));
  late String _status = text(widget.row?['status'], 'completed');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _desc, _tech, _repo, _live]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the project a title');
      return;
    }
    final body = {
      'title': _title.text.trim(),
      'description': _opt(_desc),
      'tech_stack': _opt(_tech),
      'repo_url': _opt(_repo),
      'live_url': _opt(_live),
      'status': _status,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.row == null) {
        await talentApi.addProject(widget.studentId, body);
      } else {
        await talentApi.updateProject(asInt(widget.row!['id']), body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline), const SizedBox(height: 12)],
          Field('Title', child: TextField(controller: _title)),
          Field('What it does', child: TextField(controller: _desc, maxLines: 3)),
          Field('Technologies', hint: 'e.g. Java, Spring Boot, React', child: TextField(controller: _tech)),
          Field('Code repository link', hint: 'Staff review the code here', child: TextField(controller: _repo, keyboardType: TextInputType.url)),
          Field('Live demo link (optional)', child: TextField(controller: _live, keyboardType: TextInputType.url)),
          Field('Stage', child: EnumPicker(value: _status, options: const ['completed', 'ongoing'], onChanged: (v) => setState(() => _status = v ?? _status))),
          FilledButton(onPressed: _busy ? null : _save, child: Text(widget.row == null ? 'Add project' : 'Save changes')),
        ],
      );
}

/// Staff rate a project's code on four criteria; the average becomes its quality score.
class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.project});
  final Map<String, dynamic> project;

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late final Map<String, int> _rubric = {
    for (final e in ((widget.project['rubric'] as Map?) ?? const {}).entries) '${e.key}': asInt(e.value),
  };
  late final _notes = TextEditingController(text: text(widget.project['review_notes']));
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _send(bool verified) async {
    setState(() => _busy = true);
    try {
      await talentApi.reviewProject(
        asInt(widget.project['id']),
        verified ? {'verified': true, 'rubric': _rubric, 'notes': _notes.text.trim()} : {'verified': false},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final complete = rubricCriteria.keys.every(_rubric.containsKey);
    final repo = text(widget.project['repo_url']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Open the repository and rate the code from 1 (poor) to 5 (excellent). The average becomes the code-quality score.',
            style: TextStyle(fontSize: 13, color: Brand.textSoft)),
        if (repo.isNotEmpty) TextButton.icon(onPressed: () => openLink(context, repo), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Open repository')),
        for (final e in rubricCriteria.entries)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(e.value)),
                Wrap(spacing: 6, children: [
                  for (var n = 1; n <= 5; n++)
                    ChoiceChip(label: Text('$n'), selected: _rubric[e.key] == n, onSelected: (_) => setState(() => _rubric[e.key] = n)),
                ]),
              ],
            ),
          ),
        Field('Notes for the student (optional)', child: TextField(controller: _notes, maxLines: 2)),
        FilledButton(onPressed: _busy || !complete ? null : () => _send(true), child: const Text('Verify with these ratings')),
        if (widget.project['verified'] == true)
          TextButton(onPressed: _busy ? null : () => _send(false), child: const Text('Withdraw verification', style: TextStyle(color: Brand.error))),
      ],
    );
  }
}
