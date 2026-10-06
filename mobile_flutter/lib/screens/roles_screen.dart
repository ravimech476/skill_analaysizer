import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Roles and the permissions behind them. Admin bypasses every check, so its
/// permission list is informational.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: session.can(['role.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Role'),
            )
          : null,
      body: AsyncView<List<Map<String, dynamic>>>(
        refreshKey: _reload,
        load: rolesApi.list,
        builder: (context, roles, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: roles
              .map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(text(r['name']),
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          ),
                          if (asBool(r['is_system'])) const Tag('System'),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${text(r['description'], text(r['slug']))}\n'
                          '${asInt(r['user_count'])} users · ${asInt(r['permission_count'])} permissions',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      isThreeLine: true,
                      trailing: session.can(['role.update'])
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'permissions', child: Text('Permissions')),
                                if (!asBool(r['is_system'])) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                if (!asBool(r['is_system']) && session.can(['role.delete']))
                                  const PopupMenuItem(
                                      value: 'delete', child: Text('Delete', style: TextStyle(color: Brand.error))),
                              ],
                              onSelected: (v) async {
                                if (v == 'permissions') {
                                  await push(context, _RolePermissions(role: r));
                                  setState(() => _reload++);
                                } else if (v == 'edit') {
                                  _edit(r);
                                } else if (await confirm(context, 'Delete ${r['name']}?',
                                    danger: true, okLabel: 'Delete')) {
                                  final ok = await runAction(context, () => rolesApi.remove(asInt(r['id'])),
                                      success: 'Role deleted');
                                  if (ok) setState(() => _reload++);
                                }
                              },
                            )
                          : null,
                      onTap: () async {
                        await push(context, _RolePermissions(role: r));
                        setState(() => _reload++);
                      },
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _edit(Map<String, dynamic>? role) async {
    final saved = await showFormSheet<bool>(
      context,
      role == null ? 'New role' : 'Edit ${role['name']}',
      (ctx) => _RoleForm(role: role),
    );
    if (saved == true) setState(() => _reload++);
  }
}

class _RoleForm extends StatefulWidget {
  const _RoleForm({this.role});
  final Map<String, dynamic>? role;

  @override
  State<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends State<_RoleForm> {
  late final _name = TextEditingController(text: str(widget.role?['name']));
  late final _description = TextEditingController(text: str(widget.role?['description']));
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field('Role name', child: TextField(controller: _name)),
          Field('Description', child: TextField(controller: _description, maxLines: 2)),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final body = {
                      'name': _name.text.trim(),
                      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
                    };
                    final ok = await runAction(
                      context,
                      () => widget.role == null
                          ? rolesApi.create(body)
                          : rolesApi.update(asInt(widget.role!['id']), body),
                      success: widget.role == null ? 'Role created' : 'Role updated',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: Text(widget.role == null ? 'Create role' : 'Save changes'),
          ),
        ],
      );
}

class _RolePermissions extends StatefulWidget {
  const _RolePermissions({required this.role});
  final Map<String, dynamic> role;

  @override
  State<_RolePermissions> createState() => _RolePermissionsState();
}

class _RolePermissionsState extends State<_RolePermissions> {
  Set<int>? _selected;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<Session>().can(['role.update']);
    return SubPage(
      title: text(widget.role['name']),
      subtitle: 'Permissions',
      child: AsyncView<(List<Map<String, dynamic>>, Map<String, dynamic>)>(
        load: () async => (await rolesApi.permissionGroups(), await rolesApi.get(asInt(widget.role['id']))),
        builder: (context, data, reload) {
          final (groups, role) = data;
          _selected ??= {...((role['permission_ids'] ?? []) as List).map((e) => asInt(e))};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (text(role['slug']) == 'admin')
                const NoteBanner(
                  title: 'Admins bypass every permission check',
                  body: 'This list is informational — an admin can do everything regardless.',
                ),
              const SizedBox(height: 10),
              ...groups.map((g) {
                final perms = maps(g['permissions']);
                final allOn = perms.every((p) => _selected!.contains(asInt(p['id'])));
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      title: Text(pretty(text(g['module'])),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${perms.where((p) => _selected!.contains(asInt(p['id']))).length} of ${perms.length} allowed',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: canEdit
                          ? Checkbox(
                              value: allOn,
                              onChanged: (on) => setState(() {
                                for (final p in perms) {
                                  if (on == true) {
                                    _selected!.add(asInt(p['id']));
                                  } else {
                                    _selected!.remove(asInt(p['id']));
                                  }
                                }
                              }),
                            )
                          : null,
                      children: perms
                          .map((p) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _selected!.contains(asInt(p['id'])),
                                title: Text(pretty(text(p['action'])), style: const TextStyle(fontSize: 13.5)),
                                subtitle: p['description'] == null
                                    ? null
                                    : Text(text(p['description']), style: const TextStyle(fontSize: 11.5)),
                                onChanged: canEdit
                                    ? (on) => setState(() => on == true
                                        ? _selected!.add(asInt(p['id']))
                                        : _selected!.remove(asInt(p['id'])))
                                    : null,
                              ))
                          .toList(),
                    ),
                  ),
                );
              }),
              if (canEdit)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await runAction(
                            context,
                            () => rolesApi.setPermissions(asInt(widget.role['id']), _selected!.toList()),
                            success: 'Permissions saved',
                          );
                          if (mounted) setState(() => _busy = false);
                        },
                  child: const Text('Save permissions'),
                ),
            ],
          );
        },
      ),
    );
  }
}
