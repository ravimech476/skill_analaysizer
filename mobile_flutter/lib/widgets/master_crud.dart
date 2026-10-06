import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import 'common.dart';
import 'pickers.dart';

/// One editable column of a lookup table.
class MasterField {
  const MasterField(
    this.name,
    this.label, {
    this.type = MasterFieldType.text,
    this.required = false,
    this.options,
    this.lookup,
    this.hint,
    this.min,
    this.max,
  });

  final String name;
  final String label;
  final MasterFieldType type;
  final bool required;

  /// Choices for a `select`.
  final List<String>? options;

  /// Loader for a `reference` (a foreign key to another master).
  final Future<List<Ref>> Function()? lookup;
  final String? hint;
  final num? min;
  final num? max;
}

enum MasterFieldType { text, upper, number, integer, date, boolean, select, reference }

/// The mobile twin of the web app's MasterCrud: declare the columns once and get a
/// searchable list, an add/edit sheet and delete, for any of the simple lookup tables.
class MasterCrud extends StatefulWidget {
  const MasterCrud({
    super.key,
    required this.path,
    required this.permission,
    required this.noun,
    required this.fields,
    required this.title,
    this.subtitle,
    this.searchable = true,
    this.readOnly = false,
    this.badges,
  });

  /// API path, e.g. "departments".
  final String path;

  /// Permission module, e.g. "department" → department.create / update / delete.
  final String permission;

  /// Singular noun used in messages, e.g. "department".
  final String noun;
  final List<MasterField> fields;

  /// Builds the row's main line and its supporting line.
  final (String, String?) Function(MasterRow row) title;
  final String? subtitle;
  final bool searchable;
  final bool readOnly;

  /// Small tags on the right of a row, e.g. counts.
  final List<Widget> Function(MasterRow row)? badges;

  @override
  State<MasterCrud> createState() => _MasterCrudState();
}

class _MasterCrudState extends State<MasterCrud> {
  String _search = '';
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final canCreate = !widget.readOnly && session.can(['${widget.permission}.create']);
    final canUpdate = !widget.readOnly && session.can(['${widget.permission}.update']);
    final canDelete = !widget.readOnly && session.can(['${widget.permission}.delete']);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: Text(pretty(widget.noun)),
            )
          : null,
      body: Column(
        children: [
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SearchBox(hint: 'Search ${widget.noun}s', onChanged: (v) => setState(() => _search = v)),
            ),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.subtitle!, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
              ),
            ),
          Expanded(
            child: AsyncView<List<MasterRow>>(
              refreshKey: '$_search|$_reload',
              scrollable: false,
              load: () => mastersApi.all(widget.path, query: {'search': _search}),
              builder: (context, rows, reload) {
                if (rows.isEmpty) {
                  return ListView(children: [EmptyView('No ${widget.noun}s yet')]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    final (main, sub) = widget.title(row);
                    return Card(
                      child: ListTile(
                        title: Text(main, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                        subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12.5)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...?widget.badges?.call(row),
                            if (canUpdate || canDelete)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                itemBuilder: (context) => [
                                  if (canUpdate) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                  if (canDelete)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete', style: TextStyle(color: Brand.error)),
                                    ),
                                ],
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    _edit(row);
                                  } else if (await confirm(context, 'Delete this ${widget.noun}?',
                                      danger: true, okLabel: 'Delete')) {
                                    final ok = await runAction(
                                      context,
                                      () => mastersApi.remove(widget.path, row.id),
                                      success: '${pretty(widget.noun)} deleted',
                                    );
                                    if (ok) {
                                      Lookups.clear(widget.path);
                                      setState(() => _reload++);
                                    }
                                  }
                                },
                              ),
                          ],
                        ),
                        onTap: canUpdate ? () => _edit(row) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(MasterRow? row) async {
    final saved = await showFormSheet<bool>(
      context,
      row == null ? 'New ${widget.noun}' : 'Edit ${widget.noun}',
      (ctx) => _MasterForm(path: widget.path, noun: widget.noun, fields: widget.fields, row: row),
    );
    if (saved == true) {
      Lookups.clear(widget.path);
      setState(() => _reload++);
    }
  }
}

class _MasterForm extends StatefulWidget {
  const _MasterForm({required this.path, required this.noun, required this.fields, this.row});
  final String path;
  final String noun;
  final List<MasterField> fields;
  final MasterRow? row;

  @override
  State<_MasterForm> createState() => _MasterFormState();
}

class _MasterFormState extends State<_MasterForm> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, dynamic> _values = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final current = widget.row?[f.name];
      switch (f.type) {
        case MasterFieldType.boolean:
          _values[f.name] = current == true;
        case MasterFieldType.select:
        case MasterFieldType.reference:
          _values[f.name] = current;
        default:
          _text[f.name] = TextEditingController(text: current == null ? '' : current.toString());
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final body = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case MasterFieldType.boolean:
        case MasterFieldType.select:
        case MasterFieldType.reference:
          body[f.name] = _values[f.name];
        case MasterFieldType.number:
          final raw = _text[f.name]!.text.trim();
          body[f.name] = raw.isEmpty ? null : double.tryParse(raw);
        case MasterFieldType.integer:
          final raw = _text[f.name]!.text.trim();
          body[f.name] = raw.isEmpty ? null : int.tryParse(raw);
        default:
          final raw = _text[f.name]!.text.trim();
          body[f.name] = raw.isEmpty ? null : (f.type == MasterFieldType.upper ? raw.toUpperCase() : raw);
      }
      if (f.required && (body[f.name] == null || body[f.name] == '')) {
        setState(() => _error = '${f.label} is required');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.row == null) {
        await mastersApi.create(widget.path, body);
      } else {
        await mastersApi.update(widget.path, widget.row!.id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline),
            const SizedBox(height: 14),
          ],
          ...widget.fields.map(_field),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.row == null ? 'Add ${widget.noun}' : 'Save changes'),
          ),
        ],
      );

  Widget _field(MasterField f) {
    switch (f.type) {
      case MasterFieldType.boolean:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.label, style: const TextStyle(fontSize: 14)),
            subtitle: f.hint == null ? null : Text(f.hint!, style: const TextStyle(fontSize: 12)),
            value: _values[f.name] == true,
            activeThumbColor: Brand.accent,
            onChanged: (v) => setState(() => _values[f.name] = v),
          ),
        );
      case MasterFieldType.select:
        return Field(
          f.label,
          hint: f.hint,
          child: EnumPicker(
            value: _values[f.name] as String?,
            options: f.options ?? const [],
            allowClear: !f.required,
            clearLabel: 'Not set',
            onChanged: (v) => setState(() => _values[f.name] = v),
          ),
        );
      case MasterFieldType.reference:
        return Field(
          f.label,
          hint: f.hint,
          child: RefPicker(
            hint: f.label,
            allowClear: !f.required,
            load: f.lookup!,
            value: asIntOrNull(_values[f.name]),
            onChanged: (v) => setState(() => _values[f.name] = v),
          ),
        );
      default:
        return Field(
          f.label,
          hint: f.hint,
          child: TextField(
            controller: _text[f.name],
            keyboardType: f.type == MasterFieldType.number || f.type == MasterFieldType.integer
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            textCapitalization:
                f.type == MasterFieldType.upper ? TextCapitalization.characters : TextCapitalization.none,
          ),
        );
    }
  }
}
