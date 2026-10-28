import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Career prediction screen.
/// - Admin/staff: pick a student and see matched careers.
/// - Student: see own matched careers.
/// - Parent: pick a child and see matched careers.
class CareersScreen extends StatefulWidget {
  const CareersScreen({super.key});

  @override
  State<CareersScreen> createState() => _CareersScreenState();
}

class _CareersScreenState extends State<CareersScreen> {
  int? _studentId;
  String? _studentName;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final audience = session.audience;

    if (audience == Audience.student) {
      return _MatchesBody(studentId: session.user!.id, canRate: true);
    }

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
          Expanded(child: _MatchesBody(studentId: _studentId!, canRate: false)),
        if (_studentId == null)
          const Expanded(child: Center(child: Text('Pick a student to see matched careers', style: TextStyle(color: Brand.textSoft)))),
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
            Expanded(child: _MatchesBody(studentId: chosen.id, canRate: false)),
          ],
        );
      },
    );
  }
}

class _MatchesBody extends StatefulWidget {
  const _MatchesBody({required this.studentId, required this.canRate});
  final int studentId;
  final bool canRate;

  @override
  State<_MatchesBody> createState() => _MatchesBodyState();
}

class _MatchesBodyState extends State<_MatchesBody> {
  CareerMatches? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MatchesBody old) {
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
      if (mounted) setState(() => _data = data);
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
    if (_data == null || _data!.total == 0) {
      return const Center(child: Text('No career matches yet', style: TextStyle(color: Brand.textSoft)));
    }

    final matches = _data!.matches;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: matches.length,
        itemBuilder: (context, i) => _MatchCard(match: matches[i]),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});
  final CareerMatch match;

  @override
  Widget build(BuildContext context) {
    final readiness = match.readiness;
    Color badgeColor;
    switch (readiness) {
      case 'ready':
        badgeColor = Colors.green;
        break;
      case 'close':
        badgeColor = Colors.orange;
        break;
      default:
        badgeColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${match.rank} ', style: const TextStyle(color: Brand.textSoft, fontSize: 13)),
                Expanded(child: Text(match.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(readiness.toUpperCase(), style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (match.domain != null) ...[
              const SizedBox(height: 4),
              Text(match.domain!, style: const TextStyle(color: Brand.textSoft, fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Text('${match.finalScore}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Text(' / 100', style: TextStyle(color: Brand.textSoft)),
                const Spacer(),
                Text('skills ${match.skillScore}%  academics ${match.academicScore}%',
                    style: const TextStyle(color: Brand.textSoft, fontSize: 12)),
              ],
            ),
            if (match.explanation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(match.explanation, style: const TextStyle(color: Brand.textSoft, fontSize: 13)),
            ],
            if (match.interestFit != null || match.personalityFit != null || match.codingFit != null || match.growthOutlook != null) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (match.interestFit != null) Tag('Interest ${match.interestFit!.round()}%'),
                if (match.personalityFit != null) Tag('Personality ${match.personalityFit!.round()}%'),
                if (match.codingFit != null) Tag('Coding ${match.codingFit!.round()}%'),
                if (match.growthOutlook != null) Tag('Growth ${match.growthOutlook}/5', color: Brand.info),
              ]),
            ],
            if (match.gaps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${match.gaps.length} skill gap${match.gaps.length == 1 ? '' : 's'} to close',
                  style: const TextStyle(color: Brand.textSoft, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
