import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../api/talent_api.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Learning path screen -- shows courses recommended to close skill gaps.
/// - Admin/staff: pick a student and see recommended courses.
/// - Student: see own recommended courses.
/// - Parent: pick a child and see recommended courses.
class LearningPathScreen extends StatefulWidget {
  const LearningPathScreen({super.key});

  @override
  State<LearningPathScreen> createState() => _LearningPathScreenState();
}

class _LearningPathScreenState extends State<LearningPathScreen> {
  int? _studentId;
  String? _studentName;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final audience = session.audience;

    if (audience == Audience.student) {
      return _CoursesBody(studentId: session.user!.id);
    }

    if (audience == Audience.parent) {
      return _ParentView(
        selectedId: _studentId,
        onSelect: (id) => setState(() => _studentId = id),
      );
    }

    // Admin / staff: pick a student.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final s = await pickStudent(context, title: 'Choose a student');
                    if (s != null && mounted) {
                      setState(() {
                        _studentId = s.id;
                        _studentName = s.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: Text(_studentName ?? 'Pick a student'),
                ),
              ),
            ],
          ),
        ),
        if (_studentId != null)
          Expanded(child: _CoursesBody(studentId: _studentId!)),
        if (_studentId == null)
          const Expanded(child: Center(child: Text('Pick a student to see recommended courses', style: TextStyle(color: Brand.textSoft)))),
      ],
    );
  }
}

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
      builder: (context, students, reload) {
        if (students.isEmpty) {
          return const EmptyView('No student profile is linked to your account yet.');
        }
        final chosen = students.firstWhere(
          (c) => c.id == selectedId,
          orElse: () => students.first,
        );
        return Column(
          children: [
            if (students.length > 1)
              Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<int>(
                  value: chosen.id,
                  isExpanded: true,
                  items: students
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSelect(v);
                  },
                  decoration: const InputDecoration(labelText: 'Select child'),
                ),
              ),
            Expanded(child: _CoursesBody(studentId: chosen.id)),
          ],
        );
      },
    );
  }
}

/// Fetches career matches and extracts gap courses.
class _CoursesBody extends StatefulWidget {
  const _CoursesBody({required this.studentId});
  final int studentId;

  @override
  State<_CoursesBody> createState() => _CoursesBodyState();
}

class _CoursesBodyState extends State<_CoursesBody> {
  List<_GapCourse>? _courses;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CoursesBody old) {
    super.didUpdateWidget(old);
    if (old.studentId != widget.studentId) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await careersApi.matches(widget.studentId);
      final courses = <_GapCourse>[];
      final seen = <int>{};
      for (final m in data.matches) {
        for (final g in m.gaps) {
          for (final c in g.courses) {
            if (seen.contains(c.id)) continue;
            seen.add(c.id);
            courses.add(_GapCourse(course: c, skillName: g.name, careerName: m.name));
          }
        }
      }
      if (mounted) setState(() => _courses = courses);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Brand.error)));
    if (_courses == null || _courses!.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No course recommendations yet.\nRun the career prediction first to get personalised suggestions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.textSoft),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _courses!.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _PrepPlanView(studentId: widget.studentId),
              const Padding(
                padding: EdgeInsets.fromLTRB(2, 6, 2, 8),
                child: Text('All recommended courses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ]);
          }
          final i = index - 1;
          final gc = _courses![i];
          final c = gc.course;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text('Skill: ${gc.skillName}  |  For: ${gc.careerName}', style: const TextStyle(fontSize: 12)),
                  Row(
                    children: [
                      if (c.provider != null) Text(c.provider!, style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                      if (c.provider != null && c.hours != null) const Text('  |  ', style: TextStyle(fontSize: 12, color: Brand.textSoft)),
                      if (c.hours != null) Text('${c.hours}h', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                      const Spacer(),
                      Text('Level ${c.level}', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                      if (c.isFree) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Free', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              trailing: c.url != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Open course',
                      onPressed: () => launchUrl(Uri.parse(c.url!), mode: LaunchMode.externalApplication),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// The placement preparation plan: skills to build, a weekly schedule, practice, habits and project ideas.
class _PrepPlanView extends StatefulWidget {
  const _PrepPlanView({required this.studentId});
  final int studentId;

  @override
  State<_PrepPlanView> createState() => _PrepPlanViewState();
}

class _PrepPlanViewState extends State<_PrepPlanView> {
  int? _careerId;

  Widget _items(List<Map<String, dynamic>> rows, String empty) {
    if (rows.isEmpty) return Text(empty, style: const TextStyle(fontSize: 13, color: Brand.muted));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final a in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text(a['area']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(text(a['why']), style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
            Text(text(a['do']), style: const TextStyle(fontSize: 13)),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        refreshKey: '${widget.studentId}|$_careerId',
        scrollable: false,
        load: () => talentApi.prepPlan(widget.studentId, careerId: _careerId),
        builder: (context, p, _) {
          final skills = maps(p['skills']);
          final weeks = maps(p['weeks']);
          final projects = maps(p['projects']);
          final alts = maps(p['alternatives']);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionCard(
              title: 'Placement plan for ${text(p['career'])}',
              subtitle: 'Built from your record at ${asInt(p['hours_per_week'])} study hours a week.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (alts.isNotEmpty) ...[
                  NoteBanner(
                    title: 'Your interests point more towards ${alts.map((a) => text(a['career'])).join(' or ')}',
                    color: Brand.info,
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 10),
                ],
                const Text('Skills to build', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                if (skills.isEmpty)
                  const Text('You meet every skill requirement for this career.', style: TextStyle(fontSize: 13, color: Brand.muted)),
                for (final s in skills)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: text(s['skill']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: '  level ${asInt(s['level'])} of ${asInt(s['needed'])} needed', style: const TextStyle(color: Brand.textSoft, fontSize: 12.5)),
                      for (final c in maps(s['courses']).take(1)) TextSpan(text: '\n${text(c['title'])}${c['duration_hours'] != null ? ', ${c['duration_hours']}h' : ''}', style: const TextStyle(fontSize: 13)),
                    ])),
                  ),
                const SizedBox(height: 10),
                const Text('Weekly schedule', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                if (weeks.isEmpty) const Text('Nothing to schedule.', style: TextStyle(fontSize: 13, color: Brand.muted)),
                for (final w in weeks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Week ${asInt(w['number'])} (${asInt(w['hours'])}h): ${((w['study'] ?? []) as List).join('; ')}', style: const TextStyle(fontSize: 13)),
                  ),
                if (asInt(p['more_courses']) > 0)
                  Text('${asInt(p['more_courses'])} more course(s) follow after these weeks.', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
              ]),
            ),
            const SizedBox(height: 10),
            SectionCard(title: 'Practice', child: _items(maps(p['practice']), 'Nothing urgent. Keep up your practice.')),
            const SizedBox(height: 10),
            SectionCard(title: 'Study habits', child: _items(maps(p['habits']), 'Your study habits look strong.')),
            const SizedBox(height: 10),
            SectionCard(
              title: 'Projects to build',
              child: projects.isEmpty
                  ? const Text('No project ideas for this career yet.', style: TextStyle(fontSize: 13, color: Brand.muted))
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final i in projects)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(text(i['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            Text(text(i['description']), style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                          ]),
                        ),
                    ]),
            ),
            const SizedBox(height: 10),
          ]);
        },
      );
}

class _GapCourse {
  _GapCourse({required this.course, required this.skillName, required this.careerName});
  final CourseRef course;
  final String skillName;
  final String careerName;
}
