import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';

/// Dropdown data shared by every screen. Each list is fetched once per session;
/// `Lookups.clear()` after an edit makes the next screen fetch it again.
class Lookups {
  static final Map<String, Future<List<Ref>>> _cache = {};

  static Future<List<Ref>> _of(String key, Future<List<Ref>> Function() load) => _cache[key] ??= load();

  static void clear([String? key]) {
    if (key == null) {
      _cache.clear();
    } else {
      _cache.remove(key);
    }
  }

  static Future<List<Ref>> departments() => _of('departments', () async {
        final rows = await mastersApi.all('departments');
        return rows.map((r) => Ref(r.id, '${r['code']} · ${r['name']}', r.raw)).toList();
      });

  static Future<List<Ref>> academicYears() => _of('academic-years', () async {
        final rows = await mastersApi.all('academic-years');
        return rows.map((r) => Ref(r.id, '${r['name']}${asBool(r['is_current']) ? ' (current)' : ''}', r.raw)).toList();
      });

  static Future<List<Ref>> yearLevels() => _of('year-levels', () async {
        final rows = await mastersApi.all('year-levels');
        return rows.map((r) => Ref(r.id, text(r['name']), r.raw)).toList();
      });

  static Future<List<Ref>> semesters() => _of('semesters', () async {
        final rows = await mastersApi.all('semesters');
        return rows.map((r) => Ref(r.id, text(r['name']), r.raw)).toList();
      });

  static Future<List<Ref>> subjects() => _of('subjects', () async {
        final rows = await mastersApi.all('subjects');
        return rows.map((r) => Ref(r.id, '${r['code']} · ${r['name']}', r.raw)).toList();
      });

  static Future<List<Ref>> examTypes() => _of('exam-types', () async {
        final rows = await mastersApi.all('exam-types');
        return rows.map((r) => Ref(r.id, text(r['name']), r.raw)).toList();
      });

  static Future<List<Ref>> skills() => _of('skills', () async {
        final rows = await mastersApi.all('skills');
        return rows.map((r) => Ref(r.id, text(r['name']), r.raw)).toList();
      });

  static Future<List<Ref>> companies() => _of('companies', () async {
        final rows = await mastersApi.all('companies');
        return rows.map((r) => Ref(r.id, text(r['name']), r.raw)).toList();
      });

  static Future<List<Ref>> classes() => _of('classes', () async {
        final rows = await classesApi.list();
        return rows.map((c) => Ref(c.id, c.label, c.raw)).toList();
      });

  static Future<List<Ref>> staff() => _of('staff', () async {
        final rows = await staffApi.options();
        return rows
            .map((s) => Ref(s.id, s.employeeCode == null ? s.name : '${s.name} (${s.employeeCode})', s.raw))
            .toList();
      });
}

/// A dropdown fed by one of the lookups above.
class RefPicker extends StatelessWidget {
  const RefPicker({
    super.key,
    required this.load,
    required this.value,
    required this.onChanged,
    this.hint = 'Select',
    this.allowClear = true,
    this.filter,
  });

  final Future<List<Ref>> Function() load;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String hint;
  final bool allowClear;
  final bool Function(Ref)? filter;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Ref>>(
      future: load(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(errorMessage(snap.error), style: const TextStyle(fontSize: 12.5, color: Brand.error));
        }
        final all = snap.data ?? const <Ref>[];
        final options = filter == null ? all : all.where(filter!).toList();
        final valid = options.any((o) => o.id == value) ? value : null;
        return DropdownButtonFormField<int>(
          initialValue: valid,
          isExpanded: true,
          hint: Text(snap.hasData ? hint : 'Loading…', style: const TextStyle(color: Brand.muted, fontSize: 14)),
          items: [
            if (allowClear) const DropdownMenuItem<int>(value: null, child: Text('Any')),
            ...options.map((o) => DropdownMenuItem(
                  value: o.id,
                  child: Text(o.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                )),
          ],
          onChanged: snap.hasData ? onChanged : null,
        );
      },
    );
  }
}

/// A plain string dropdown for enums (status, gender, relation…).
class EnumPicker extends StatelessWidget {
  const EnumPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = 'Select',
    this.allowClear = false,
    this.clearLabel = 'Any',
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String hint;
  final bool allowClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : null,
        isExpanded: true,
        hint: Text(hint, style: const TextStyle(color: Brand.muted, fontSize: 14)),
        items: [
          if (allowClear) DropdownMenuItem<String>(value: null, child: Text(clearLabel)),
          ...options.map((o) => DropdownMenuItem(value: o, child: Text(pretty(o), style: const TextStyle(fontSize: 14)))),
        ],
        onChanged: onChanged,
      );
}

/// Searches students on the server and returns the one picked — used wherever staff
/// need to act on a single student (careers, marks, documents, lifecycle).
Future<Student?> pickStudent(BuildContext context, {String title = 'Choose a student'}) {
  return showModalBottomSheet<Student>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Brand.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _StudentSearchSheet(title: title),
  );
}

class _StudentSearchSheet extends StatefulWidget {
  const _StudentSearchSheet({required this.title});
  final String title;

  @override
  State<_StudentSearchSheet> createState() => _StudentSearchSheetState();
}

class _StudentSearchSheetState extends State<_StudentSearchSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SearchBox(hint: 'Name or register number', onChanged: (v) => setState(() => _search = v)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView<Paged<Map<String, dynamic>>>(
                refreshKey: _search,
                scrollable: false,
                load: () => studentsApi.list(search: _search, pageSize: 40),
                builder: (context, page, reload) {
                  if (page.rows.isEmpty) return const EmptyView('No students matched');
                  return ListView.separated(
                    itemCount: page.rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = Student(page.rows[i]);
                      return ListTile(
                        title: Text(s.name, style: const TextStyle(fontSize: 14.5)),
                        subtitle: Text(s.subtitle, style: const TextStyle(fontSize: 12.5)),
                        onTap: () => Navigator.pop(context, s),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
