import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
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
        itemCount: _courses!.length,
        itemBuilder: (context, i) {
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

class _GapCourse {
  _GapCourse({required this.course, required this.skillName, required this.careerName});
  final CourseRef course;
  final String skillName;
  final String careerName;
}
