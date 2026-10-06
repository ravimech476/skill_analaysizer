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
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
