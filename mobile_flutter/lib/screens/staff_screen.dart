import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/import_upload.dart';
import '../widgets/pickers.dart';

/// The staff directory, with their department, roles and subject allocations.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final showImport = session.can(['staff.create']);
    if (!showImport) return const _StaffList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const TabBar(tabs: [Tab(text: 'List'), Tab(text: 'Import')]),
        body: TabBarView(
          children: [
            const _StaffList(),
            ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                ImportUpload(
                  title: 'staff',
                  hint: 'One row per staff member: employee code, name, department code, designation and roles.',
                  upload: (file, {required dryRun}) => bulkApi.staff(file, dryRun: dryRun),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffList extends StatefulWidget {
  const _StaffList();

  @override
  State<_StaffList> createState() => _StaffListState();
}

class _StaffListState extends State<_StaffList> {
  String _search = '';
  int? _departmentId;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: session.can(['staff.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Staff'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(flex: 3, child: SearchBox(hint: 'Name or code', onChanged: (v) => setState(() => _search = v))),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: RefPicker(
                    hint: 'Department',
                    load: Lookups.departments,
                    value: _departmentId,
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<Paged<Map<String, dynamic>>>(
              refreshKey: '$_search|$_departmentId|$_reload',
              load: () => staffApi.list(search: _search, departmentId: _departmentId, pageSize: 50),
              builder: (context, page, reload) {
                if (page.rows.isEmpty) return const EmptyView('No staff matched');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: page.rows.map(Staff.new).map((s) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: Avatar(name: s.name, photo: s.photo, radius: 20),
                          title: Text(s.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [s.employeeCode, s.designation, s.departmentName]
                                      .whereType<String>()
                                      .join(' · '),
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 5,
                                  children: [
                                    ...s.roles.map((r) => Tag(pretty(r), color: Brand.info)),
                                    if (s.inchargeOf != null) Tag('Incharge ${s.inchargeOf}', color: Brand.accent),
                                    if (!s.isActive) const Tag('Inactive', color: Brand.warning),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          isThreeLine: true,
                          trailing: session.can(['staff.update'])
                              ? IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => _edit(s),
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Staff? staff) async {
    final saved = await showFormSheet<bool>(
      context,
      staff == null ? 'New staff member' : 'Edit ${staff.name}',
      (ctx) => _StaffForm(staff: staff),
    );
    if (saved == true) {
      Lookups.clear('staff');
      setState(() => _reload++);
    }
  }
}

class _StaffForm extends StatefulWidget {
  const _StaffForm({this.staff});
  final Staff? staff;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late final _name = TextEditingController(text: widget.staff?.name);
  late final _code = TextEditingController(text: widget.staff?.employeeCode);
  late final _mobile = TextEditingController(text: widget.staff?.mobile);
  late final _email = TextEditingController(text: widget.staff?.email);
  late final _designation = TextEditingController(text: widget.staff?.designation);
  late final _qualification = TextEditingController(text: widget.staff?.qualification);
  late final _joinedOn = TextEditingController(text: widget.staff?.joinedOn);
  late final _password = TextEditingController();
  late int? _departmentId = widget.staff?.departmentId;
  late final Set<String> _roles = {...(widget.staff?.roles ?? ['staff'])};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _code, _mobile, _email, _designation, _qualification, _joinedOn, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field('Full name', child: TextField(controller: _name)),
          Field(
            'Employee code',
            hint: 'Also becomes the login username',
            child: TextField(controller: _code, textCapitalization: TextCapitalization.characters),
          ),
          Field(
            'Department',
            hint: 'Leave empty for non-departmental staff',
            child: RefPicker(
              hint: 'Department',
              load: Lookups.departments,
              value: _departmentId,
              onChanged: (v) => setState(() => _departmentId = v),
            ),
          ),
          Row(children: [
            Expanded(child: Field('Designation', child: TextField(controller: _designation))),
            const SizedBox(width: 12),
            Expanded(child: Field('Qualification', child: TextField(controller: _qualification))),
          ]),
          Row(children: [
            Expanded(child: Field('Mobile', child: TextField(controller: _mobile, keyboardType: TextInputType.phone))),
            const SizedBox(width: 12),
            Expanded(child: Field('Joined on', hint: 'YYYY-MM-DD', child: TextField(controller: _joinedOn))),
          ]),
          Field('Email', child: TextField(controller: _email, keyboardType: TextInputType.emailAddress)),
          Field(
            'Password',
            hint: widget.staff == null ? 'Optional — they can also use a one-time code' : 'Leave blank to keep',
            child: TextField(controller: _password, obscureText: true),
          ),
          Field(
            'Roles',
            child: Wrap(
              spacing: 8,
              children: ['staff', 'hod', 'placement_officer']
                  .map((r) => FilterChip(
                        label: Text(pretty(r), style: const TextStyle(fontSize: 12.5)),
                        selected: _roles.contains(r),
                        onSelected: (on) => setState(() => on ? _roles.add(r) : _roles.remove(r)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_name.text.trim().isEmpty || _code.text.trim().isEmpty) {
                      toast(context, 'Name and employee code are required', error: true);
                      return;
                    }
                    setState(() => _busy = true);
                    final body = {
                      'name': _name.text.trim(),
                      'employee_code': _code.text.trim().toUpperCase(),
                      'department_id': _departmentId,
                      'designation': _designation.text.trim().isEmpty ? null : _designation.text.trim(),
                      'qualification': _qualification.text.trim().isEmpty ? null : _qualification.text.trim(),
                      'mobile': _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
                      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
                      'joined_on': _joinedOn.text.trim().isEmpty ? null : _joinedOn.text.trim(),
                      'roles': _roles.isEmpty ? ['staff'] : _roles.toList(),
                      if (_password.text.isNotEmpty) 'password': _password.text,
                    };
                    final ok = await runAction(
                      context,
                      () => widget.staff == null ? staffApi.create(body) : staffApi.update(widget.staff!.id, body),
                      success: widget.staff == null ? 'Staff added' : 'Staff updated',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: Text(widget.staff == null ? 'Add staff' : 'Save changes'),
          ),
        ],
      );
}
