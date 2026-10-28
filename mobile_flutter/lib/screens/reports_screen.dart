import 'package:flutter/material.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Pass rates, CGPA spread, skill gaps and the placement trend — the same figures
/// the web dashboard shows, laid out for a phone.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int? _departmentId;
  int? _examTypeId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: RefPicker(
                  hint: 'All departments',
                  load: Lookups.departments,
                  value: _departmentId,
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RefPicker(
                  hint: 'Exam',
                  load: Lookups.examTypes,
                  value: _examTypeId,
                  onChanged: (v) => setState(() => _examTypeId = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            refreshKey: '$_departmentId|$_examTypeId',
            load: () => reportsApi.dashboard(departmentId: _departmentId, examTypeId: _examTypeId),
            builder: (context, data, reload) {
              final head = (data['headline'] as Map?)?.cast<String, dynamic>() ?? const {};
              final passByClass = maps(data['pass_by_class']);
              final cgpa = maps(data['cgpa_distribution']);
              final gaps = maps(data['skill_gaps']);
              final byBatch = maps(data['placement_by_batch']);
              final byMonth = maps(data['placement_by_month']);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data['scope_department'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('Showing ${data['scope_department']}',
                          style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    ),
                  TileGrid(children: [
                    StatTile(label: 'Students', value: '${asInt(head['students'])}', icon: Icons.school_outlined),
                    StatTile(label: 'Staff', value: '${asInt(head['staff'])}', icon: Icons.badge_outlined),
                    StatTile(
                      label: 'Average CGPA',
                      value: head['avg_cgpa'] == null ? '—' : asDouble(head['avg_cgpa']).toStringAsFixed(2),
                      icon: Icons.menu_book_outlined,
                    ),
                    StatTile(
                      label: 'With backlogs',
                      value: '${asInt(head['with_backlogs'])}',
                      color: Brand.warning,
                      icon: Icons.warning_amber_outlined,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Placement',
                    subtitle: '${asInt(head['open_drives'])} drive(s) open right now',
                    child: Row(
                      children: [
                        DonutChart(
                          value: asDouble(head['placed']),
                          total: asDouble(head['students']),
                          centerLabel: '${asDouble(head['placed_percent']).toStringAsFixed(0)}%',
                          caption: 'placed',
                          color: Brand.success,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${asInt(head['placed'])} students placed',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('of ${asInt(head['students'])} in scope',
                                  style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (passByClass.isNotEmpty)
                    SectionCard(
                      title: 'Pass rate by class',
                      subtitle: data['exam'] == null ? null : text((data['exam'] as Map)['name']),
                      child: BarChart(
                        suffix: '%',
                        max: 100,
                        rows: passByClass
                            .map((c) => BarRow(
                                  text(c['class_label']),
                                  asDouble(c['pass_percent']),
                                  caption: '${asInt(c['passed'])} of ${asInt(c['appeared'])}',
                                  color: asDouble(c['pass_percent']) >= 75
                                      ? Brand.success
                                      : asDouble(c['pass_percent']) >= 50
                                          ? Brand.accent
                                          : Brand.error,
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (cgpa.isNotEmpty)
                    SectionCard(
                      title: 'CGPA spread',
                      subtitle: asInt(data['cgpa_not_graded']) > 0
                          ? '${asInt(data['cgpa_not_graded'])} students have no final marks yet'
                          : null,
                      child: BarChart(
                        rows: cgpa
                            .map((b) => BarRow(text(b['label']), asDouble(b['total']), color: Brand.accent))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (gaps.isNotEmpty)
                    SectionCard(
                      title: 'Biggest skill gaps',
                      subtitle: 'How many students meet what the open drives ask for',
                      child: BarChart(
                        suffix: '%',
                        max: 100,
                        labelWidth: 120,
                        rows: gaps
                            .take(10)
                            .map((g) => BarRow(
                                  text(g['name']),
                                  asDouble(g['coverage_percent']),
                                  caption: '${asInt(g['students_meeting'])} of ${asInt(g['students_base'])} meet L${asInt(g['required_level'])}',
                                  color: asDouble(g['coverage_percent']) >= 60 ? Brand.success : Brand.error,
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (byBatch.isNotEmpty)
                    SectionCard(
                      title: 'Placement by batch',
                      child: Column(
                        children: byBatch
                            .map((b) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(text(b['batch']), style: const TextStyle(fontSize: 13.5)),
                                  subtitle: Text(
                                    '${asInt(b['placed'])} of ${asInt(b['students'])} placed · '
                                    '${asInt(b['offers'])} offers'
                                    '${b['highest_package'] == null ? '' : ' · highest ${lpa(asDouble(b['highest_package']))}'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Tag('${asDouble(b['placed_percent']).toStringAsFixed(0)}%',
                                      color: Brand.success),
                                ))
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (byMonth.length > 1)
                    SectionCard(
                      title: 'Offers over time',
                      child: TrendChart(
                        points: byMonth.map((m) => asDouble(m['offers'])).toList(),
                        labels: byMonth.map((m) => text(m['month'])).toList(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  _DataQuality(departmentId: _departmentId),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// How complete and consistent the student data is, checked before analysis.
class _DataQuality extends StatelessWidget {
  const _DataQuality({this.departmentId});
  final int? departmentId;

  Color _color(double p) => p >= 90 ? Brand.success : (p >= 60 ? Brand.warning : Brand.error);

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        refreshKey: 'dq|$departmentId',
        scrollable: false,
        load: () => reportsApi.dataQuality(departmentId: departmentId),
        builder: (context, data, _) {
          final r = (data['report'] as Map).cast<String, dynamic>();
          final total = asInt(r['students']);
          final ready = total == 0 ? 0 : (asInt(r['clean_students']) * 100 / total).round();
          final issues = maps(r['checks']).where((c) => asInt(c['count']) > 0).toList();
          final attention = maps(r['need_attention']);
          return SectionCard(
            title: 'Data quality',
            subtitle: 'Skill, career and insight results depend on complete, consistent records.',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TileGrid(children: [
                StatTile(label: 'Students checked', value: '$total', icon: Icons.groups_outlined),
                StatTile(label: 'Ready for analysis', value: '$ready%', icon: Icons.task_alt, color: _color(ready.toDouble())),
                StatTile(label: 'Errors', value: '${asInt(r['errors'])}', icon: Icons.error_outline, color: asInt(r['errors']) > 0 ? Brand.error : null),
                StatTile(label: 'Warnings', value: '${asInt(r['warnings'])}', icon: Icons.warning_amber_outlined),
              ]),
              const SizedBox(height: 12),
              const Text('Completeness by area', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              for (final a in maps(r['areas']))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 128, child: Text(text(a['label']), style: const TextStyle(fontSize: 12.5))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (asDouble(a['percent']) / 100).clamp(0, 1),
                          minHeight: 7,
                          backgroundColor: Brand.borderSoft,
                          valueColor: AlwaysStoppedAnimation(_color(asDouble(a['percent']))),
                        ),
                      ),
                    ),
                    SizedBox(width: 48, child: Text('${a['percent']}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                  ]),
                ),
              const SizedBox(height: 12),
              const Text('Issues found', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (issues.isEmpty) const Padding(padding: EdgeInsets.only(top: 4), child: Text('No issues found.', style: TextStyle(fontSize: 13, color: Brand.muted))),
              for (final c in issues)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Tag(text(c['severity']) == 'error' ? 'Error' : (text(c['severity']) == 'warning' ? 'Warning' : 'Optional'),
                          color: text(c['severity']) == 'error' ? Brand.error : (text(c['severity']) == 'warning' ? Brand.warning : null)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${text(c['label'])}: ${asInt(c['count'])}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                    ]),
                    Text(text(c['hint']), style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                  ]),
                ),
              if (attention.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('Students to fix first', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                for (final s in attention.take(8))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${text(s['register_no'])} ${text(s['name'])}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      TextSpan(text: '\n${((s['issues'] ?? []) as List).join(' · ')}', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                    ])),
                  ),
              ],
            ]),
          );
        },
      );
}
