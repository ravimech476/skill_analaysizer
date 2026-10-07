import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

/// Confirmed placement records with statistics.
class PlacementHistoryScreen extends StatefulWidget {
  const PlacementHistoryScreen({super.key});

  @override
  State<PlacementHistoryScreen> createState() => _PlacementHistoryScreenState();
}

class _PlacementHistoryScreenState extends State<PlacementHistoryScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isStaff) return const _MyPlacementHistory();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SearchBox(
                hint: 'Student or company',
                onChanged: (v) => setState(() => _search = v)),
          ),
          Expanded(
            child: AsyncView<(List<Placement>, Map<String, dynamic>)>(
              refreshKey: _search,
              load: () async => (
                await placementApi.placements(search: _search),
                await placementApi.stats()
              ),
              builder: (context, data, reload) {
                final (placements, stats) = data;
                final byDept = maps(stats['by_department']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileGrid(children: [
                      StatTile(
                        label: 'Placed',
                        value: '${asInt(stats['placed_students'])}',
                        hint:
                            '${asDouble(stats['placed_percent']).toStringAsFixed(1)}% of ${asInt(stats['total_students'])}',
                        color: Brand.success,
                      ),
                      StatTile(
                          label: 'Offers',
                          value: '${asInt(stats['total_offers'])}'),
                      StatTile(
                        label: 'Highest',
                        value: stats['highest_package'] == null
                            ? '—'
                            : lpa(asDouble(stats['highest_package'])),
                        color: Brand.accent,
                      ),
                      StatTile(
                        label: 'Average',
                        value: stats['average_package'] == null
                            ? '—'
                            : lpa(asDouble(stats['average_package'])),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (byDept.isNotEmpty)
                      SectionCard(
                        title: 'Placed by department',
                        child: BarChart(
                          suffix: '%',
                          max: 100,
                          rows: byDept
                              .map((d) => BarRow(
                                    text(d['code']),
                                    asDouble(d['percent']),
                                    caption:
                                        '${asInt(d['placed'])} of ${asInt(d['students'])}',
                                  ))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (placements.isEmpty)
                      const EmptyView('No offers recorded yet')
                    else
                      ...placements.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                title: Text(p.studentName,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${p.registerNo} · ${p.companyName} · ${p.jobTitle}'
                                  '${p.offerDate == null ? '' : ' · ${fmtDate(p.offerDate)}'}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                trailing:
                                    Tag(lpa(p.packageLpa), color: Brand.success),
                              ),
                            ),
                          )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- student / parent

class _MyPlacementHistory extends StatefulWidget {
  const _MyPlacementHistory();

  @override
  State<_MyPlacementHistory> createState() => _MyPlacementHistoryState();
}

class _MyPlacementHistoryState extends State<_MyPlacementHistory> {
  int? _studentId;

  @override
  Widget build(BuildContext context) {
    final isParent = context.watch<Session>().audience.name == 'parent';
    return AsyncView<List<Student>>(
      scrollable: false,
      load: () async => (await studentsApi.list(pageSize: isParent ? 50 : 1))
          .rows
          .map(Student.new)
          .toList(),
      builder: (context, children, reload) {
        if (children.isEmpty) {
          return const EmptyView(
              'No student profile is linked to your account yet.');
        }
        final chosen = children.firstWhere((c) => c.id == _studentId,
            orElse: () => children.first);
        return Column(
          children: [
            if (children.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<int>(
                  initialValue: chosen.id,
                  isExpanded: true,
                  items: children
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _studentId = v),
                ),
              ),
            Expanded(
              child: AsyncView<Map<String, dynamic>>(
                load: () => placementApi.opportunities(chosen.id),
                builder: (context, data, reload) {
                  final apps =
                      maps(data['applications']).map(Application.new).toList();
                  final offers =
                      apps.where((a) => a.status == 'selected').toList();

                  if (offers.isEmpty && apps.isEmpty) {
                    return const EmptyView('No placement records yet');
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (offers.isNotEmpty)
                        NoteBanner(
                          title: 'Placed at ${offers.first.companyName}',
                          body:
                              '${offers.first.jobTitle} · ${lpa(offers.first.packageLpa)}',
                          color: Brand.success,
                          icon: Icons.celebration_outlined,
                        ),
                      if (apps.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SectionCard(
                          title: 'Your applications',
                          child: Column(
                            children: apps
                                .map((a) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(
                                          '${a.companyName} · ${a.jobTitle}',
                                          style:
                                              const TextStyle(fontSize: 13.5)),
                                      subtitle: Text(lpa(a.packageLpa),
                                          style:
                                              const TextStyle(fontSize: 12)),
                                      trailing: StatusTag(a.status),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ],
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
