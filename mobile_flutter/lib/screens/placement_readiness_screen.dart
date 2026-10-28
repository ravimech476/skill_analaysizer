import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Placement readiness dashboard — shows a ranked list of students with combined
/// readiness scores derived from marks, skills, attendance and placement eligibility.
class PlacementReadinessScreen extends StatefulWidget {
  const PlacementReadinessScreen({super.key});

  @override
  State<PlacementReadinessScreen> createState() => _PlacementReadinessScreenState();
}

class _PlacementReadinessScreenState extends State<PlacementReadinessScreen> {
  int? _classId;
  int? _departmentId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── filters ──
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: RefPicker(
                  hint: 'Department',
                  load: Lookups.departments,
                  value: _departmentId,
                  onChanged: (v) => setState(() {
                    _departmentId = v;
                    _classId = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RefPicker(
                  hint: 'Class',
                  load: Lookups.classes,
                  value: _classId,
                  onChanged: (v) => setState(() => _classId = v),
                ),
              ),
            ],
          ),
        ),

        // ── body ──
        if (_departmentId == null && _classId == null)
          const Expanded(
            child: EmptyView(
              'Pick a department or class to view placement readiness scores.',
              icon: Icons.speed_outlined,
            ),
          )
        else
          Expanded(
            child: _ReadinessBody(
              departmentId: _departmentId,
              classId: _classId,
            ),
          ),
      ],
    );
  }
}

class _ReadinessBody extends StatelessWidget {
  const _ReadinessBody({this.departmentId, this.classId});
  final int? departmentId;
  final int? classId;

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      refreshKey: '$departmentId|$classId',
      load: () async => (await api.get('/analyzer/readiness', query: {
            'department_id': departmentId,
            'class_id': classId,
          })) as Map<String, dynamic>,
      builder: (context, data, reload) {
        final students = maps(data['students']);
        final avgScore = asDouble(data['avg_score']);
        final readyCount = asInt(data['ready_count']);
        final totalCount = asInt(data['total_count']);

        if (students.isEmpty) {
          return const EmptyView('No readiness data for this selection.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── summary tiles ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TileGrid(children: [
                StatTile(
                  label: 'Avg Score',
                  value: '${avgScore.toStringAsFixed(0)}%',
                  icon: Icons.speed_outlined,
                  color: avgScore >= 70 ? Brand.success : (avgScore >= 50 ? Brand.warning : Brand.error),
                ),
                StatTile(
                  label: 'Ready',
                  value: '$readyCount / $totalCount',
                  icon: Icons.check_circle_outline,
                  color: Brand.success,
                  hint: 'Score >= 70%',
                ),
              ]),
            ),
            const SizedBox(height: 10),

            // ── readiness distribution donut ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SectionCard(
                title: 'Readiness Distribution',
                child: Row(
                  children: [
                    DonutChart(
                      value: readyCount.toDouble(),
                      total: totalCount.toDouble(),
                      centerLabel: '${totalCount > 0 ? (readyCount / totalCount * 100).toStringAsFixed(0) : 0}%',
                      caption: 'ready',
                      color: Brand.success,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendRow(color: Brand.success, label: 'Ready (>=70%)', count: readyCount),
                          const SizedBox(height: 6),
                          _LegendRow(
                            color: Brand.warning,
                            label: 'Developing (50-69%)',
                            count: students.where((s) {
                              final sc = asDouble(s['score']);
                              return sc >= 50 && sc < 70;
                            }).length,
                          ),
                          const SizedBox(height: 6),
                          _LegendRow(
                            color: Brand.error,
                            label: 'At Risk (<50%)',
                            count: students.where((s) => asDouble(s['score']) < 50).length,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── ranked student list ──
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                itemCount: students.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final s = students[i];
                  final score = asDouble(s['score']);
                  final rank = i + 1;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // rank badge
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: rank <= 3
                                  ? Brand.accent.withValues(alpha: 0.12)
                                  : Brand.borderSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: rank <= 3 ? Brand.accent : Brand.textSoft,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // student info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text(s['name']),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${text(s['register_no'])} · ${text(s['class_label'], text(s['department']))}',
                                  style: const TextStyle(fontSize: 12, color: Brand.textSoft),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // score meter
                          SizedBox(
                            width: 60,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${score.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: score >= 70
                                        ? Brand.success
                                        : (score >= 50 ? Brand.warning : Brand.error),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: (score / 100).clamp(0, 1),
                                    minHeight: 5,
                                    backgroundColor: Brand.borderSoft,
                                    valueColor: AlwaysStoppedAnimation(
                                      score >= 70
                                          ? Brand.success
                                          : (score >= 50 ? Brand.warning : Brand.error),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
