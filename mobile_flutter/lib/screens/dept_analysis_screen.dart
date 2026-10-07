import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Department-wide analytics: per-department stats, skill distribution, semester
/// trend and weak subjects. Admins can pick a department or see all; staff are
/// scoped to their own department by the backend.
class DeptAnalysisScreen extends StatefulWidget {
  const DeptAnalysisScreen({super.key});

  @override
  State<DeptAnalysisScreen> createState() => _DeptAnalysisScreenState();
}

class _DeptAnalysisScreenState extends State<DeptAnalysisScreen> {
  int? _departmentId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isAdmin = session.audience == Audience.admin;

    return Column(
      children: [
        if (isAdmin)
          Padding(
            padding: const EdgeInsets.all(12),
            child: RefPicker(
              hint: 'All departments',
              load: Lookups.departments,
              value: _departmentId,
              onChanged: (v) => setState(() => _departmentId = v),
            ),
          ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            refreshKey: '$_departmentId',
            load: () async =>
                (await api.get('/analyzer/department', query: {
                  if (_departmentId != null) 'department_id': _departmentId,
                })) as Map<String, dynamic>,
            builder: (context, data, reload) {
              final scope = text(data['scope'], 'all');
              final depts = maps(data['departments']);
              final skillDist = maps(data['skill_distribution']);
              final semTrend = maps(data['semester_trend']);
              final weakSubjs = maps(data['weak_subjects']);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scope != 'all')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('Showing $scope',
                          style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    ),

                  // ── department stats ──
                  if (depts.isNotEmpty)
                    SectionCard(
                      title: 'Department Stats',
                      child: Column(
                        children: [
                          // Header.
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                SizedBox(width: 56, child: Text('Dept', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                                SizedBox(width: 46, child: Text('Count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                                SizedBox(width: 46, child: Text('CGPA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                                SizedBox(width: 46, child: Text('Pass%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                                Expanded(child: Text('Placed', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Brand.textSoft))),
                              ],
                            ),
                          ),
                          ...depts.map((d) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      child: Text(text(d['code']),
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                    ),
                                    SizedBox(
                                      width: 46,
                                      child: Text('${asInt(d['students'])}',
                                          style: const TextStyle(fontSize: 12.5)),
                                    ),
                                    SizedBox(
                                      width: 46,
                                      child: Text(asDouble(d['avg_cgpa']).toStringAsFixed(1),
                                          style: const TextStyle(fontSize: 12.5)),
                                    ),
                                    SizedBox(
                                      width: 46,
                                      child: Text('${asDouble(d['pass_percent']).toStringAsFixed(0)}%',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: asDouble(d['pass_percent']) >= 70 ? Brand.success : Brand.error,
                                          )),
                                    ),
                                    Expanded(
                                      child: Text(
                                        '${asInt(d['placed_count'])} (${asDouble(d['placed_percent']).toStringAsFixed(0)}%)',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 8),
                          // Top skills per department.
                          ...depts.where((d) {
                            final ts = (d['top_skills'] as List?) ?? [];
                            return ts.isNotEmpty;
                          }).map((d) {
                            final ts = ((d['top_skills'] as List?) ?? []).cast<String>();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(text(d['code']),
                                        style: const TextStyle(fontSize: 11, color: Brand.muted)),
                                  ),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: ts.map((s) => Tag(s, color: Brand.accent)).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),

                  // ── CGPA comparison bar chart ──
                  if (depts.length > 1)
                    SectionCard(
                      title: 'Avg CGPA by Department',
                      child: BarChart(
                        max: 10,
                        rows: depts.asMap().entries.map((e) {
                          final d = e.value;
                          final cgpa = asDouble(d['avg_cgpa']);
                          return BarRow(
                            text(d['code']),
                            cgpa,
                            caption: '${asInt(d['students'])} students',
                            color: Brand.series[e.key % Brand.series.length],
                          );
                        }).toList(),
                      ),
                    ),
                  if (depts.length > 1) const SizedBox(height: 10),

                  // ── skill distribution ──
                  if (skillDist.isNotEmpty)
                    SectionCard(
                      title: 'Skill Distribution',
                      subtitle: 'Students with each skill by department',
                      child: Column(
                        children: skillDist.take(15).map((s) {
                          final byDept = (s['by_department'] as Map?) ?? {};
                          final total = byDept.values.fold<int>(0, (sum, v) => sum + asInt(v));
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(text(s['name']),
                                          style: const TextStyle(fontSize: 13)),
                                      Text(
                                        byDept.entries
                                            .map((e) => '${e.key}: ${e.value}')
                                            .join(' · '),
                                        style: const TextStyle(fontSize: 11, color: Brand.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                Tag('$total', color: Brand.accent),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 10),

                  // ── semester trend ──
                  if (semTrend.length > 1)
                    SectionCard(
                      title: 'Semester Trend',
                      subtitle: 'Average marks % across semesters',
                      child: TrendChart(
                        points: semTrend.map((t) => asDouble(t['avg_percent'])).toList(),
                        labels: semTrend.map((t) => text(t['semester'])).toList(),
                      ),
                    ),
                  if (semTrend.length == 1)
                    SectionCard(
                      title: 'Semester Trend',
                      child: BarChart(
                        suffix: '%',
                        max: 100,
                        rows: semTrend
                            .map((t) => BarRow(
                                  text(t['semester']),
                                  asDouble(t['avg_percent']),
                                  color: Brand.accent,
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),

                  // ── weak subjects ──
                  if (weakSubjs.isNotEmpty)
                    SectionCard(
                      title: 'Weak Subjects',
                      subtitle: 'Subjects with pass rate below 70%',
                      child: Column(
                        children: weakSubjs.map((w) {
                          final passPct = asDouble(w['pass_percent']);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${text(w['code'])} · ${text(w['name'])}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13)),
                                      Text(text(w['department']),
                                          style: const TextStyle(fontSize: 11, color: Brand.muted)),
                                    ],
                                  ),
                                ),
                                Tag('${passPct.toStringAsFixed(0)}%', color: Brand.error),
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
