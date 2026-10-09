import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Individual student skill analysis derived from mark history, skills and
/// placement eligibility. Admin/staff pick a student; students see their own;
/// parents pick a child.
class StudentAnalysisScreen extends StatefulWidget {
  const StudentAnalysisScreen({super.key});

  @override
  State<StudentAnalysisScreen> createState() => _StudentAnalysisScreenState();
}

class _StudentAnalysisScreenState extends State<StudentAnalysisScreen> {
  int? _studentId;
  String? _studentName;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final audience = session.audience;

    // Students see their own analysis directly.
    if (audience == Audience.student) {
      return _AnalysisBody(studentId: session.user!.id);
    }

    // Parents pick a child.
    if (audience == Audience.parent) {
      return _ParentView(
        selectedId: _studentId,
        onSelect: (id) => setState(() => _studentId = id),
      );
    }

    // Admin / staff: search and pick a student.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final s = await pickStudent(context, title: 'Choose a student to analyze');
                    if (s != null && mounted) {
                      setState(() {
                        _studentId = s.id;
                        _studentName = s.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: Text(
                    _studentName ?? 'Pick a student',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_studentId != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _studentId = null;
                    _studentName = null;
                  }),
                ),
              ],
            ],
          ),
        ),
        if (_studentId == null)
          const Expanded(
            child: EmptyView(
              'Pick a student to see their skill analysis based on marks, skills and placement eligibility.',
              icon: Icons.person_search_outlined,
            ),
          )
        else
          Expanded(child: _AnalysisBody(studentId: _studentId!)),
      ],
    );
  }
}

/// Parents: load children, pick one, show analysis.
class _ParentView extends StatelessWidget {
  const _ParentView({required this.selectedId, required this.onSelect});
  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Student>>(
      scrollable: false,
      load: () async =>
          (await studentsApi.list(pageSize: 50)).rows.map(Student.new).toList(),
      builder: (context, children, reload) {
        if (children.isEmpty) {
          return const EmptyView('No student profile is linked to your account yet.');
        }
        final chosen = children.firstWhere(
          (c) => c.id == selectedId,
          orElse: () => children.first,
        );
        return Column(
          children: [
            if (children.length > 1)
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<int>(
                  initialValue: chosen.id,
                  isExpanded: true,
                  items: children
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSelect(v);
                  },
                ),
              ),
            Expanded(child: _AnalysisBody(studentId: chosen.id)),
          ],
        );
      },
    );
  }
}

/// The analysis body: calls the backend and renders all sections.
class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.studentId});
  final int studentId;

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      refreshKey: '$studentId',
      load: () async =>
          (await api.get('/analyzer/student/$studentId')) as Map<String, dynamic>,
      builder: (context, data, reload) {
        final semesters = maps(data['semesters']);
        final subjects = maps(data['subjects']);
        final skills = maps(data['skills']);
        final strengths = ((data['strengths'] ?? []) as List).cast<String>();
        final weaknesses = ((data['weaknesses'] ?? []) as List).cast<String>();
        final drives = maps(data['eligible_drives']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── student info card ──
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text(data['name']),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${text(data['register_no'])} · ${text(data['class_label'])} · ${text(data['department'])}',
                    style: const TextStyle(fontSize: 13, color: Brand.textSoft),
                  ),
                  const SizedBox(height: 12),
                  TileGrid(children: [
                    StatTile(
                      label: 'CGPA',
                      value: asDouble(data['cgpa']).toStringAsFixed(2),
                      icon: Icons.menu_book_outlined,
                    ),
                    StatTile(
                      label: 'Backlogs',
                      value: '${asInt(data['backlog_count'])}',
                      color: asInt(data['backlog_count']) > 0 ? Brand.error : Brand.success,
                      icon: Icons.warning_amber_outlined,
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── semester performance ──
            if (semesters.isNotEmpty)
              SectionCard(
                title: 'Semester Performance',
                child: Column(
                  children: [
                    // Header row.
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 50, child: Text('Sem', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                          SizedBox(width: 45, child: Text('SGPA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                          SizedBox(width: 45, child: Text('Avg %', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                          Expanded(child: Text('P / F', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                        ],
                      ),
                    ),
                    ...semesters.map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(width: 50, child: Text(text(s['name']), style: const TextStyle(fontSize: 13))),
                              SizedBox(
                                width: 45,
                                child: Text(
                                  asDouble(s['sgpa']).toStringAsFixed(2),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(
                                width: 45,
                                child: Text(
                                  '${asDouble(s['avg_percent']).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: asDouble(s['avg_percent']) >= 60 ? Brand.success : Brand.error,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${asInt(s['passed'])} / ${asInt(s['failed'])}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 10),

            // ── SGPA trend chart ──
            if (semesters.length > 1)
              SectionCard(
                title: 'SGPA Trend',
                child: TrendChart(
                  points: semesters.map((s) => asDouble(s['sgpa'])).toList(),
                  labels: semesters.map((s) => text(s['name'])).toList(),
                  color: Brand.accent,
                ),
              ),
            if (semesters.length == 1)
              SectionCard(
                title: 'SGPA Trend',
                child: BarChart(
                  suffix: '',
                  max: 10,
                  rows: semesters
                      .map((s) => BarRow(
                            text(s['name']),
                            asDouble(s['sgpa']),
                            color: Brand.accent,
                          ))
                      .toList(),
                ),
              ),
            if (semesters.isNotEmpty) const SizedBox(height: 10),

            // ── subject marks bar chart ──
            if (subjects.isNotEmpty)
              SectionCard(
                title: 'Subject Marks',
                subtitle: 'Marks %',
                child: BarChart(
                  suffix: '%',
                  max: 100,
                  labelWidth: 90,
                  rows: subjects.map((s) {
                    final pct = asDouble(s['marks_percent']);
                    return BarRow(
                      text(s['code']),
                      pct,
                      caption: text(s['semester']),
                      color: pct >= 75
                          ? Brand.success
                          : pct >= 60
                              ? Brand.accent
                              : Brand.error,
                    );
                  }).toList(),
                ),
              ),
            if (subjects.isNotEmpty) const SizedBox(height: 10),

            // ── performance overview donut ──
            if (subjects.isNotEmpty)
              Builder(builder: (context) {
                final strongCount = subjects.where((s) => asDouble(s['marks_percent']) >= 75).length;
                final weakCount = subjects.where((s) => asDouble(s['marks_percent']) < 60).length;
                final avgCount = subjects.length - strongCount - weakCount;
                return SectionCard(
                  title: 'Performance Overview',
                  child: Row(
                    children: [
                      DonutChart(
                        value: strongCount.toDouble(),
                        total: subjects.length.toDouble(),
                        centerLabel: '${subjects.length}',
                        caption: 'subjects',
                        color: Brand.success,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendRow(color: Brand.success, label: 'Strong (>=75%)', count: strongCount),
                            const SizedBox(height: 6),
                            _LegendRow(color: Brand.warning, label: 'Average (60-74%)', count: avgCount),
                            const SizedBox(height: 6),
                            _LegendRow(color: Brand.error, label: 'Weak (<60%)', count: weakCount),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (subjects.isNotEmpty) const SizedBox(height: 10),

            // ── subject marks list ──
            if (subjects.isNotEmpty)
              SectionCard(
                title: 'Subject Marks',
                subtitle: '${subjects.length} subjects',
                child: Column(
                  children: subjects.map((s) {
                    final pct = asDouble(s['marks_percent']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${text(s['code'])} · ${text(s['name'])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                                Text(text(s['semester']),
                                    style: const TextStyle(fontSize: 11, color: Brand.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tag(
                            '${pct.toStringAsFixed(0)}%',
                            color: pct >= 75
                                ? Brand.success
                                : pct >= 60
                                    ? Brand.accent
                                    : Brand.error,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 10),

            // ── skills ──
            if (skills.isNotEmpty)
              SectionCard(
                title: 'Skills',
                subtitle: '${skills.length} recorded',
                child: Column(
                  children: skills.map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(text(s['name']), style: const TextStyle(fontSize: 13.5)),
                                  Text(pretty(text(s['source'])),
                                      style: const TextStyle(fontSize: 11, color: Brand.muted)),
                                ],
                              ),
                            ),
                            Stars(asInt(s['proficiency'])),
                          ],
                        ),
                      )).toList(),
                ),
              ),
            const SizedBox(height: 10),

            // ── skill proficiency donut ──
            if (skills.isNotEmpty)
              Builder(builder: (context) {
                final high = skills.where((s) => asInt(s['proficiency']) >= 4).length;
                return SectionCard(
                  title: 'Skill Proficiency',
                  child: Row(
                    children: [
                      DonutChart(
                        value: high.toDouble(),
                        total: skills.length.toDouble(),
                        centerLabel: '$high/${skills.length}',
                        caption: 'proficient',
                        color: Brand.accent,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegendRow(
                              color: Brand.accent,
                              label: 'Proficient (4-5)',
                              count: high,
                            ),
                            const SizedBox(height: 6),
                            _LegendRow(
                              color: Brand.warning,
                              label: 'Developing (2-3)',
                              count: skills.where((s) {
                                final p = asInt(s['proficiency']);
                                return p >= 2 && p < 4;
                              }).length,
                            ),
                            const SizedBox(height: 6),
                            _LegendRow(
                              color: Brand.error,
                              label: 'Beginner (0-1)',
                              count: skills.where((s) => asInt(s['proficiency']) < 2).length,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (skills.isNotEmpty) const SizedBox(height: 10),

            // ── strengths & weaknesses ──
            if (strengths.isNotEmpty || weaknesses.isNotEmpty)
              SectionCard(
                title: 'Strengths & Weaknesses',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (strengths.isNotEmpty) ...[
                      const Text('Strengths',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.success)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: strengths.map((s) => Tag(s, color: Brand.success)).toList(),
                      ),
                    ],
                    if (strengths.isNotEmpty && weaknesses.isNotEmpty) const SizedBox(height: 12),
                    if (weaknesses.isNotEmpty) ...[
                      const Text('Weaknesses',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.error)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: weaknesses.map((s) => Tag(s, color: Brand.error)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 10),

            // ── eligible drives ──
            if (drives.isNotEmpty)
              SectionCard(
                title: 'Eligible Drives',
                subtitle: '${drives.length} drives',
                child: Column(
                  children: drives.map((d) {
                    final match = asDouble(d['match_percent']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${text(d['company'])} · ${text(d['title'])}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5)),
                                Text(lpa(asDouble(d['package_lpa'])),
                                    style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${match.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: match >= 70 ? Brand.success : (match >= 40 ? Brand.warning : Brand.error),
                                    )),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: (match / 100).clamp(0, 1),
                                    minHeight: 4,
                                    backgroundColor: Brand.borderSoft,
                                    valueColor: AlwaysStoppedAnimation(
                                      match >= 70 ? Brand.success : (match >= 40 ? Brand.warning : Brand.error),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Small legend row used next to donut charts.
class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Text('$count', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
