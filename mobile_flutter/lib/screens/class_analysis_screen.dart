import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Class-wide skill overview and performance. Staff/admin pick a class, then
/// see headline stats, subject performance, skill coverage and student ranking.
class ClassAnalysisScreen extends StatefulWidget {
  const ClassAnalysisScreen({super.key});

  @override
  State<ClassAnalysisScreen> createState() => _ClassAnalysisScreenState();
}

class _ClassAnalysisScreenState extends State<ClassAnalysisScreen> {
  int? _classId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: RefPicker(
            hint: 'Pick a class',
            load: Lookups.classes,
            value: _classId,
            allowClear: false,
            onChanged: (v) => setState(() => _classId = v),
          ),
        ),
        if (_classId == null)
          const Expanded(
            child: EmptyView(
              'Pick a class to see its subject performance, skill coverage and student ranking.',
              icon: Icons.analytics_outlined,
            ),
          )
        else
          Expanded(
            child: AsyncView<Map<String, dynamic>>(
              refreshKey: '$_classId',
              load: () async =>
                  (await api.get('/analyzer/class/$_classId')) as Map<String, dynamic>,
              builder: (context, data, reload) {
                final subjects = maps(data['subjects']);
                final skills = maps(data['skill_summary']);
                final ranking = maps(data['student_ranking']);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── headline stats ──
                    TileGrid(children: [
                      StatTile(
                        label: 'Students',
                        value: '${asInt(data['students'])}',
                        icon: Icons.school_outlined,
                      ),
                      StatTile(
                        label: 'Avg CGPA',
                        value: asDouble(data['avg_cgpa']).toStringAsFixed(2),
                        icon: Icons.menu_book_outlined,
                      ),
                      StatTile(
                        label: 'Pass %',
                        value: '${asDouble(data['pass_percent']).toStringAsFixed(0)}%',
                        color: asDouble(data['pass_percent']) >= 75 ? Brand.success : Brand.warning,
                        icon: Icons.check_circle_outline,
                      ),
                      StatTile(
                        label: 'Top CGPA',
                        value: asDouble(data['top_cgpa']).toStringAsFixed(2),
                        color: Brand.accent,
                        icon: Icons.emoji_events_outlined,
                      ),
                    ]),
                    const SizedBox(height: 10),

                    // ── pass rate donut ──
                    Builder(builder: (context) {
                      final passPct = asDouble(data['pass_percent']);
                      final total = asInt(data['students']);
                      final passed = (passPct / 100 * total).round();
                      return SectionCard(
                        title: 'Pass Rate',
                        child: Row(
                          children: [
                            DonutChart(
                              value: passed.toDouble(),
                              total: total.toDouble(),
                              centerLabel: '${passPct.toStringAsFixed(0)}%',
                              caption: 'pass rate',
                              color: passPct >= 75 ? Brand.success : (passPct >= 50 ? Brand.warning : Brand.error),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _LegendRow(color: Brand.success, label: 'Passed', count: passed),
                                  const SizedBox(height: 6),
                                  _LegendRow(color: Brand.error, label: 'Failed', count: total - passed),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 10),

                    // ── subject performance ──
                    if (subjects.isNotEmpty)
                      SectionCard(
                        title: 'Subject Performance',
                        child: BarChart(
                          suffix: '%',
                          max: 100,
                          labelWidth: 100,
                          rows: subjects.map((s) {
                            final avg = asDouble(s['avg_percent']);
                            return BarRow(
                              text(s['code']),
                              avg,
                              caption: 'Pass ${asDouble(s['pass_percent']).toStringAsFixed(0)}% · '
                                  '${asInt(s['failed'])} failed',
                              color: avg >= 70
                                  ? Brand.success
                                  : avg >= 50
                                      ? Brand.accent
                                      : Brand.error,
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 10),

                    // ── skill coverage ──
                    if (skills.isNotEmpty)
                      SectionCard(
                        title: 'Skill Coverage',
                        subtitle: 'Students with each skill',
                        child: Column(
                          children: skills.map((s) {
                            final coverage = asDouble(s['coverage_percent']);
                            final studentsWithSk = asInt(s['students_with_skill']);
                            final total = asInt(s['total_students']);
                            return MeterBar(
                              label: text(s['name']),
                              progress: total <= 0 ? 0 : studentsWithSk / total,
                              trailing: '$studentsWithSk/$total',
                              met: coverage >= 50,
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 10),

                    // ── student ranking ──
                    if (ranking.isNotEmpty)
                      SectionCard(
                        title: 'Student Ranking',
                        subtitle: 'By CGPA',
                        child: Column(
                          children: ranking.asMap().entries.map((e) {
                            final idx = e.key;
                            final s = e.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.muted),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(text(s['name']),
                                            style: const TextStyle(fontSize: 13.5)),
                                        Text(text(s['register_no']),
                                            style: const TextStyle(fontSize: 11, color: Brand.muted)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        asDouble(s['cgpa']).toStringAsFixed(2),
                                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          Tag('${asInt(s['skill_count'])} skills'),
                                          if (asBool(s['placed']))
                                            const Tag('Placed', color: Brand.success),
                                        ],
                                      ),
                                    ],
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
            ),
          ),
      ],
    );
  }
}

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
