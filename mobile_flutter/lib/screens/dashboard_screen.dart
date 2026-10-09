import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../main.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import 'marks_screen.dart';
import 'placement_screen.dart';
import 'student_analysis_screen.dart';
import 'students_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return session.isStaff ? const _StaffDashboard() : const _MyDashboard();
  }
}

// ---------------------------------------------------------------- staff / admin

class _StaffDashboard extends StatelessWidget {
  const _StaffDashboard();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AsyncView<Map<String, dynamic>?>(
      load: () async {
        // The dashboard is a staff report; if this user cannot read it, the tiles below
        // are still useful on their own.
        if (!session.can(['report.view'])) return null;
        try {
          return await reportsApi.dashboard();
        } catch (_) {
          return null;
        }
      },
      builder: (context, data, reload) {
        final head = (data?['headline'] as Map?)?.cast<String, dynamic>() ?? const {};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good to see you, ${session.user?.name.split(' ').first ?? ''}',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              data?['scope_department'] != null
                  ? 'Showing ${data!['scope_department']}'
                  : 'Everything across the college',
              style: const TextStyle(color: Brand.textSoft, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (head.isNotEmpty) ...[
              TileGrid(children: [
                StatTile(label: 'Students', value: '${asInt(head['students'])}', icon: Icons.school_outlined),
                StatTile(label: 'Staff', value: '${asInt(head['staff'])}', icon: Icons.badge_outlined),
                StatTile(label: 'Classes', value: '${asInt(head['classes'])}', icon: Icons.account_tree_outlined),
                StatTile(
                  label: 'Average CGPA',
                  value: head['avg_cgpa'] == null ? '—' : asDouble(head['avg_cgpa']).toStringAsFixed(2),
                  icon: Icons.menu_book_outlined,
                ),
                StatTile(
                  label: 'Placed',
                  value: '${asInt(head['placed'])}',
                  hint: '${asDouble(head['placed_percent']).toStringAsFixed(0)}% of the batch',
                  color: Brand.success,
                  icon: Icons.emoji_events_outlined,
                ),
                StatTile(
                  label: 'Open drives',
                  value: '${asInt(head['open_drives'])}',
                  color: Brand.accent,
                  icon: Icons.work_outline,
                ),
                StatTile(
                  label: 'With backlogs',
                  value: '${asInt(head['with_backlogs'])}',
                  color: Brand.warning,
                  icon: Icons.warning_amber_outlined,
                ),
              ]),
              const SizedBox(height: 18),
            ],
            const Text('Jump to', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _ModuleTiles(session: session),
          ],
        );
      },
    );
  }
}

/// Every module the user may open, as cards — the fastest route on a phone.
class _ModuleTiles extends StatelessWidget {
  const _ModuleTiles({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final items = session.visibleFeatures.where((f) => f.key != 'dashboard').toList();
    return Column(
      children: items.map((f) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Brand.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(f.icon, size: 18, color: Brand.accent),
              ),
              title: Text(featureLabel(f, session.audience),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              subtitle: Text(featureDescription(f, session.audience),
                  style: const TextStyle(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
              onTap: () => push(context, SubPage(title: featureLabel(f, session.audience), child: screenFor(f.key))),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------- student / parent

class _MyDashboard extends StatefulWidget {
  const _MyDashboard();

  @override
  State<_MyDashboard> createState() => _MyDashboardState();
}

class _MyDashboardState extends State<_MyDashboard> {
  int? _studentId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isParent = session.audience == Audience.parent;

    return AsyncView<_Snapshot>(
      refreshKey: _studentId,
      load: () async {
        final page = await studentsApi.list(pageSize: isParent ? 50 : 1);
        final children = page.rows.map(Student.new).toList();
        if (children.isEmpty) return _Snapshot(children: const []);
        final chosen = children.firstWhere((c) => c.id == _studentId, orElse: () => children.first);
        final results = await Future.wait([
          scoresApi.of(chosen.id).then<Object?>((v) => v).catchError((_) => null),
          placementApi.opportunities(chosen.id).then<Object?>((v) => v).catchError((_) => null),
        ]);
        return _Snapshot(
          children: children,
          student: chosen,
          scores: results[0] as SkillScores?,
          opportunities: results[1] as Map<String, dynamic>?,
        );
      },
      builder: (context, snap, reload) {
        if (snap.student == null) {
          return EmptyView(isParent
              ? 'No children are linked to your account yet.'
              : 'Your student profile has not been set up yet.');
        }
        final s = snap.student!;
        final ops = maps(snap.opportunities?['opportunities']).map(Opportunity.new).toList();
        final eligible = ops.where((o) => o.isEligible).length;
        final applications = maps(snap.opportunities?['applications']);
        final offers = applications.where((a) => a['status'] == 'selected').toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snap.children.length > 1) ...[
              SectionCard(
                title: 'Viewing',
                child: DropdownButtonFormField<int>(
                  initialValue: s.id,
                  isExpanded: true,
                  items: snap.children
                      .map((c) => DropdownMenuItem(value: c.id, child: Text('${c.name} · ${c.subtitle}')))
                      .toList(),
                  onChanged: (v) => setState(() => _studentId = v),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Avatar(name: s.name, photo: s.photo, radius: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(s.subtitle, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            Tag('CGPA ${s.cgpa.toStringAsFixed(2)}', color: Brand.accent),
                            if (s.backlogCount > 0) Tag('${s.backlogCount} backlog(s)', color: Brand.error),
                            if (s.lifecycle != 'studying') StatusTag(s.lifecycle),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (offers.isNotEmpty) ...[
              NoteBanner(
                title: 'Placed at ${offers.first['company_name']}',
                body: '${offers.first['job_title']} · ${lpa(asDouble(offers.first['package_lpa']))}',
                color: Brand.success,
                icon: Icons.celebration_outlined,
              ),
              const SizedBox(height: 12),
            ],
            TileGrid(children: [
              StatTile(
                label: 'Skills recorded',
                value: '${snap.scores?.scores.length ?? 0}',
                icon: Icons.star_outline,
              ),
              StatTile(
                label: 'Drives you can apply to',
                value: '$eligible',
                hint: '${ops.length} open or upcoming',
                color: Brand.accent,
                icon: Icons.work_outline,
              ),
              StatTile(
                label: 'Applications',
                value: '${applications.length}',
                icon: Icons.send_outlined,
              ),
            ]),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Open these next',
              child: Column(
                children: [
                  _Shortcut(
                    icon: Icons.analytics_outlined,
                    label: 'My analysis',
                    hint: 'Skill scores and readiness overview',
                    onTap: () => push(context, SubPage(title: 'My Analysis', child: const StudentAnalysisScreen())),
                  ),
                  _Shortcut(
                    icon: Icons.emoji_events_outlined,
                    label: 'Placement drives',
                    hint: 'Eligibility and your applications',
                    onTap: () => push(context, SubPage(title: 'Placement', child: const PlacementScreen())),
                  ),
                  _Shortcut(
                    icon: Icons.menu_book_outlined,
                    label: 'My marks',
                    hint: 'Semester results and CGPA',
                    onTap: () => push(context, SubPage(title: 'Marks', child: const MarksScreen())),
                  ),
                  _Shortcut(
                    icon: Icons.person_outline,
                    label: isParent ? "My child's profile" : 'My profile',
                    hint: 'Personal details, documents and resume',
                    onTap: () => push(context, StudentDetailScreen(studentId: s.id)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Snapshot {
  _Snapshot({required this.children, this.student, this.scores, this.opportunities});
  final List<Student> children;
  final Student? student;
  final SkillScores? scores;
  final Map<String, dynamic>? opportunities;
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20, color: Brand.accent),
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
        onTap: onTap,
      );
}
