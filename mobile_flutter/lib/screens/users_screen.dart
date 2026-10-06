import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/pickers.dart';

/// Every account: students, staff, parents and admins, with their roles.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _search = '';
  String? _role;
  String _status = 'active';
  int _page = 1;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: session.can(['user.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('User'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                SearchBox(
                  hint: 'Name, username or mobile',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChipFilter<String?>(
                    value: _role,
                    options: const [
                      (null, 'All roles'),
                      ('admin', 'Admin'),
                      ('staff', 'Staff'),
                      ('hod', 'HOD'),
                      ('placement_officer', 'Placement'),
                      ('student', 'Student'),
                      ('parent', 'Parent'),
                    ],
                    onChanged: (v) => setState(() {
                      _role = v;
                      _page = 1;
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChipFilter<String>(
                    value: _status,
                    options: const [('active', 'Active'), ('inactive', 'Inactive'), ('all', 'All')],
                    onChanged: (v) => setState(() {
                      _status = v;
                      _page = 1;
                    }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<Paged<Map<String, dynamic>>>(
              refreshKey: '$_search|$_role|$_status|$_page|$_reload',
              load: () => usersApi.list(search: _search, role: _role, status: _status, page: _page),
              builder: (context, page, reload) {
                if (page.rows.isEmpty) return const EmptyView('No users matched');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${page.total} users', style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    const SizedBox(height: 8),
                    ...page.rows.map((u) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Avatar(name: text(u['name']), photo: FileLink.from(u['photo']), radius: 19),
                            title: Text(text(u['name']), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [text(u['username']), str(u['mobile']), str(u['department_name'])]
                                        .whereType<String>()
                                        .where((s) => s.isNotEmpty)
                                        .join(' · '),
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 5,
                                    runSpacing: 5,
                                    children: [
                                      ...maps(u['roles']).map((r) => Tag(
                                            text(r['name']),
                                            color: roleColors[text(r['slug'])] ?? Brand.textSoft,
                                          )),
                                      if (!asBool(u['is_active'])) const Tag('Inactive', color: Brand.warning),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                            trailing: session.can(['user.update'])
                                ? PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      const PopupMenuItem(value: 'roles', child: Text('Change roles')),
                                      const PopupMenuItem(value: 'password', child: Text('Set password')),
                                      PopupMenuItem(
                                        value: 'status',
                                        child: Text(asBool(u['is_active']) ? 'Deactivate' : 'Activate'),
                                      ),
                                    ],
                                    onSelected: (v) => _action(v, u),
                                  )
                                : null,
                          ),
                        )),
                    if (page.total > page.pageSize)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _page > 1 ? () => setState(() => _page--) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('$_page / ${(page.total / page.pageSize).ceil()}'),
                          IconButton(
                            onPressed: page.hasMore ? () => setState(() => _page++) : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(String action, Map<String, dynamic> user) async {
    final id = asInt(user['id']);
    switch (action) {
      case 'edit':
        _edit(user);
      case 'roles':
        final saved = await showFormSheet<bool>(context, 'Roles for ${user['name']}', (ctx) => _RolesForm(user: user));
        if (saved == true) setState(() => _reload++);
      case 'password':
        final password = await _askPassword(context);
        if (password == null) return;
        await runAction(context, () => usersApi.setPassword(id, password), success: 'Password set');
      case 'status':
        final active = !asBool(user['is_active']);
        final ok = await runAction(
          context,
          () => usersApi.setStatus(id, active),
          success: active ? 'User activated' : 'User deactivated',
        );
        if (ok) setState(() => _reload++);
    }
  }

  Future<void> _edit(Map<String, dynamic>? user) async {
    final saved = await showFormSheet<bool>(
      context,
      user == null ? 'New user' : 'Edit ${user['name']}',
      (ctx) => _UserForm(user: user),
    );
    if (saved == true) setState(() => _reload++);
  }
}

Future<String?> _askPassword(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set a new password'),
      content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Set password'),
        ),
      ],
    ),
  );
}

class _UserForm extends StatefulWidget {
  const _UserForm({this.user});
  final Map<String, dynamic>? user;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  late final _name = TextEditingController(text: str(widget.user?['name']));
  late final _username = TextEditingController(text: str(widget.user?['username']));
  late final _mobile = TextEditingController(text: str(widget.user?['mobile']));
  late final _email = TextEditingController(text: str(widget.user?['email']));
  late final _reference = TextEditingController(text: str(widget.user?['reference_number']));
  late final _dob = TextEditingController(text: str(widget.user?['dob']));
  final _password = TextEditingController();
  late String? _gender = str(widget.user?['gender']);
  late final Set<int> _roleIds = {...maps(widget.user?['roles']).map((r) => asInt(r['id']))};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _username, _mobile, _email, _reference, _dob, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field('Full name', child: TextField(controller: _name)),
          Field('Username', child: TextField(controller: _username, autocorrect: false)),
          Row(children: [
            Expanded(child: Field('Mobile', child: TextField(controller: _mobile, keyboardType: TextInputType.phone))),
            const SizedBox(width: 12),
            Expanded(
              child: Field(
                'Gender',
                child: EnumPicker(
                  value: _gender,
                  options: const ['male', 'female', 'other'],
                  allowClear: true,
                  clearLabel: 'Not set',
                  onChanged: (v) => setState(() => _gender = v),
                ),
              ),
            ),
          ]),
          Field('Email', child: TextField(controller: _email, keyboardType: TextInputType.emailAddress)),
          Row(children: [
            Expanded(child: Field('Reference number', child: TextField(controller: _reference))),
            const SizedBox(width: 12),
            Expanded(child: Field('Date of birth', hint: 'YYYY-MM-DD', child: TextField(controller: _dob))),
          ]),
          Field(
            'Password',
            hint: widget.user == null ? 'Optional' : 'Leave blank to keep the current one',
            child: TextField(controller: _password, obscureText: true),
          ),
          Field(
            'Roles',
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: rolesApi.list(),
              builder: (context, snap) => Wrap(
                spacing: 8,
                runSpacing: 4,
                children: (snap.data ?? [])
                    .map((r) => FilterChip(
                          label: Text(text(r['name']), style: const TextStyle(fontSize: 12.5)),
                          selected: _roleIds.contains(asInt(r['id'])),
                          onSelected: (on) => setState(
                              () => on ? _roleIds.add(asInt(r['id'])) : _roleIds.remove(asInt(r['id']))),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final body = {
                      'name': _name.text.trim(),
                      'username': _username.text.trim(),
                      'mobile': _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
                      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
                      'reference_number': _reference.text.trim().isEmpty ? null : _reference.text.trim(),
                      'gender': _gender,
                      'dob': _dob.text.trim().isEmpty ? null : _dob.text.trim(),
                      'role_ids': _roleIds.toList(),
                      if (_password.text.isNotEmpty) 'password': _password.text,
                    };
                    final ok = await runAction(
                      context,
                      () => widget.user == null
                          ? usersApi.create(body)
                          : usersApi.update(asInt(widget.user!['id']), body),
                      success: widget.user == null ? 'User created' : 'User updated',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: Text(widget.user == null ? 'Create user' : 'Save changes'),
          ),
        ],
      );
}

class _RolesForm extends StatefulWidget {
  const _RolesForm({required this.user});
  final Map<String, dynamic> user;

  @override
  State<_RolesForm> createState() => _RolesFormState();
}

class _RolesFormState extends State<_RolesForm> {
  late final Set<int> _roleIds = {...maps(widget.user['roles']).map((r) => asInt(r['id']))};
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AsyncView<List<Map<String, dynamic>>>(
        load: rolesApi.list,
        builder: (context, roles, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('A user can hold several roles; the most privileged one decides what they see.',
                style: TextStyle(fontSize: 12.5, color: Brand.textSoft)),
            const SizedBox(height: 10),
            ...roles.map((r) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _roleIds.contains(asInt(r['id'])),
                  title: Text(text(r['name']), style: const TextStyle(fontSize: 14)),
                  subtitle: r['description'] == null
                      ? null
                      : Text(text(r['description']), style: const TextStyle(fontSize: 12)),
                  onChanged: (on) => setState(
                      () => on == true ? _roleIds.add(asInt(r['id'])) : _roleIds.remove(asInt(r['id']))),
                )),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await runAction(
                        context,
                        () => usersApi.setRoles(asInt(widget.user['id']), _roleIds.toList()),
                        success: 'Roles updated',
                      );
                      if (mounted) setState(() => _busy = false);
                      if (ok && mounted) Navigator.pop(context, true);
                    },
              child: const Text('Save roles'),
            ),
          ],
        ),
      );
}
