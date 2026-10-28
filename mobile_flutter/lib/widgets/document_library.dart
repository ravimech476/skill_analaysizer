import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../theme.dart';
import 'common.dart';
import 'files.dart';
import 'master_crud.dart';
import 'pickers.dart';

/// The document libraries (study materials, interview documents, question papers) share one set of file actions.
bool readableByAi(String fileName) {
  final n = fileName.toLowerCase();
  return n.endsWith('.pdf') || n.endsWith('.docx');
}

/// Row-menu actions for a library row: open, attach or replace, remove, and add to the AI assistant.
List<MasterRowAction> documentRowActions(
  MasterRow row, {
  required String path,
  required String category,
  required bool canEdit,
  required bool canIndex,
}) {
  final file = FileLink.from(row['file']);
  return [
    if (file != null) MasterRowAction('Open file', Icons.open_in_new, (context, r) => openFile(context, file)),
    if (canEdit)
      MasterRowAction(file == null ? 'Attach file' : 'Replace file', Icons.upload_file, (context, r) async {
        final uploaded = await pickAndUpload(context, category);
        if (uploaded == null || uploaded.id == null || !context.mounted) return;
        await runAction(context, () => filesApi.setDocumentFile(path, r.id, uploaded.id), success: 'File saved');
      }),
    if (canEdit && file != null)
      MasterRowAction('Remove file', Icons.delete_outline, (context, r) async {
        if (!await confirm(context, 'Remove this file?', danger: true, okLabel: 'Remove')) return;
        if (!context.mounted) return;
        await runAction(context, () => filesApi.setDocumentFile(path, r.id, null), success: 'File removed');
      }),
    if (canIndex && file != null && readableByAi(file.name))
      MasterRowAction('Add to AI knowledge base', Icons.smart_toy_outlined, (context, r) async {
        try {
          final n = await filesApi.indexDocumentForAi(path, r.id);
          if (context.mounted) toast(context, 'Added to the AI knowledge base ($n passage${n == 1 ? '' : 's'})');
        } catch (e) {
          if (context.mounted) toastError(context, e);
        }
      }),
  ];
}

/// One detail shared by every file in a multi-file upload (company, subject, year…).
class UploadField {
  const UploadField.reference(this.name, this.label, {required this.lookup, this.required = false})
      : _kind = _Kind.reference,
        options = null,
        initial = null;
  const UploadField.select(this.name, this.label, {required this.options, this.required = false, this.initial})
      : _kind = _Kind.select,
        lookup = null;
  const UploadField.text(this.name, this.label)
      : _kind = _Kind.text,
        required = false,
        options = null,
        lookup = null,
        initial = null;
  const UploadField.integer(this.name, this.label)
      : _kind = _Kind.integer,
        required = false,
        options = null,
        lookup = null,
        initial = null;

  final String name;
  final String label;
  final _Kind _kind;
  final bool required;
  final List<String>? options;
  final Future<List<Ref>> Function()? lookup;
  final String? initial;
}

enum _Kind { reference, select, text, integer }

/// A toolbar button that uploads many documents at once. Every file becomes one row (titled after the file
/// name) with the shared details from the form; the file is stored, attached and optionally added to the AI.
class UploadDocumentsButton extends StatelessWidget {
  const UploadDocumentsButton({
    super.key,
    required this.title,
    required this.masterPath,
    required this.category,
    required this.fields,
    required this.onDone,
  });

  final String title;
  final String masterPath;
  final String category;
  final List<UploadField> fields;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: () async {
          final changed = await showFormSheet<bool>(
            context,
            title,
            (ctx) => _UploadForm(masterPath: masterPath, category: category, fields: fields),
          );
          if (changed == true) onDone();
        },
        icon: const Icon(Icons.upload_file, size: 18),
        label: const Text('Upload documents'),
      );
}

class _UploadForm extends StatefulWidget {
  const _UploadForm({required this.masterPath, required this.category, required this.fields});
  final String masterPath;
  final String category;
  final List<UploadField> fields;

  @override
  State<_UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<_UploadForm> {
  final _values = <String, dynamic>{};
  final _text = <String, TextEditingController>{};
  var _picked = <PlatformFile>[];
  final _status = <String, String>{}; // file name -> note, after it has been processed
  final _failed = <String>{};
  bool _addToAi = true;
  bool _busy = false;
  bool _finished = false;
  String? _error;

  FileRule get _rule => fileRules[widget.category]!;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f._kind == _Kind.select && f.initial != null) _values[f.name] = f.initial;
      if (f._kind == _Kind.text || f._kind == _Kind.integer) _text[f.name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _rule.extensions,
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null) return;
    final tooBig = result.files.where((f) => f.size > _rule.maxMb * 1024 * 1024).map((f) => f.name).toList();
    setState(() {
      _picked = result.files.where((f) => f.size <= _rule.maxMb * 1024 * 1024).toList();
      _error = tooBig.isEmpty ? null : 'Too large and skipped: ${tooBig.join(', ')}. ${_rule.hint}.';
      _status.clear();
      _failed.clear();
    });
  }

  Map<String, dynamic>? _sharedBody() {
    final body = <String, dynamic>{};
    for (final f in widget.fields) {
      dynamic v;
      switch (f._kind) {
        case _Kind.text:
          final raw = _text[f.name]!.text.trim();
          v = raw.isEmpty ? null : raw;
        case _Kind.integer:
          final raw = _text[f.name]!.text.trim();
          v = raw.isEmpty ? null : int.tryParse(raw);
        default:
          v = _values[f.name];
      }
      if (f.required && v == null) {
        setState(() => _error = '${f.label} is required');
        return null;
      }
      if (v != null) body[f.name] = v;
    }
    return body;
  }

  Future<void> _upload() async {
    final shared = _sharedBody();
    if (shared == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = 0;
    for (final f in _picked) {
      try {
        final part = f.bytes != null
            ? MultipartFile.fromBytes(f.bytes!, filename: f.name)
            : await MultipartFile.fromFile(f.path!, filename: f.name);
        final stored = await filesApi.upload(widget.category, part);
        final title = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
        final row = await mastersApi.create(widget.masterPath, {...shared, 'title': title.length > 200 ? title.substring(0, 200) : title});
        await filesApi.setDocumentFile(widget.masterPath, asInt(row['id']), stored.id);
        var note = 'Uploaded';
        if (_addToAi) {
          if (readableByAi(f.name)) {
            try {
              await filesApi.indexDocumentForAi(widget.masterPath, asInt(row['id']));
              note = 'Uploaded and added to the AI';
            } catch (e) {
              note = 'Saved, but not added to the AI: ${errorMessage(e)}';
            }
          } else {
            note = 'Saved. PowerPoint files cannot be added to the AI yet.';
          }
        }
        ok++;
        if (mounted) setState(() => _status[f.name] = note);
      } catch (e) {
        if (mounted) {
          setState(() {
            _status[f.name] = errorMessage(e);
            _failed.add(f.name);
          });
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _finished = true;
    });
    if (ok > 0) toast(context, '$ok document${ok == 1 ? '' : 's'} uploaded');
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          for (final f in widget.fields) _field(f),
          OutlinedButton.icon(
            onPressed: _busy || _finished ? null : _pick,
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(_picked.isEmpty ? 'Choose files' : 'Choose different files'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text('${_rule.hint}. Each file becomes one entry, titled after its file name.',
                style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
          ),
          for (final f in _picked)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _failed.contains(f.name)
                    ? Icons.error_outline
                    : _status.containsKey(f.name)
                        ? Icons.check_circle
                        : Icons.description_outlined,
                color: _failed.contains(f.name) ? Brand.error : (_status.containsKey(f.name) ? Brand.success : Brand.textSoft),
              ),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: _status[f.name] == null ? null : Text(_status[f.name]!, style: TextStyle(color: _failed.contains(f.name) ? Brand.error : Brand.textSoft)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also add PDF and Word files to the AI assistant', style: TextStyle(fontSize: 14)),
            value: _addToAi,
            activeThumbColor: Brand.accent,
            onChanged: _busy || _finished ? null : (v) => setState(() => _addToAi = v),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy || _picked.isEmpty
                ? null
                : _finished
                    ? () => Navigator.pop(context, true)
                    : _upload,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_finished ? 'Done' : 'Upload ${_picked.length} file${_picked.length == 1 ? '' : 's'}'),
          ),
        ],
      );

  Widget _field(UploadField f) {
    switch (f._kind) {
      case _Kind.reference:
        return Field(
          f.label,
          child: RefPicker(
            hint: f.label,
            allowClear: !f.required,
            load: f.lookup!,
            value: asIntOrNull(_values[f.name]),
            onChanged: _busy ? (_) {} : (v) => setState(() => _values[f.name] = v),
          ),
        );
      case _Kind.select:
        return Field(
          f.label,
          child: EnumPicker(
            value: _values[f.name] as String?,
            options: f.options ?? const [],
            allowClear: !f.required,
            clearLabel: 'Not set',
            onChanged: _busy ? (_) {} : (v) => setState(() => _values[f.name] = v),
          ),
        );
      default:
        return Field(
          f.label,
          child: TextField(
            controller: _text[f.name],
            enabled: !_busy,
            keyboardType: f._kind == _Kind.integer ? TextInputType.number : TextInputType.text,
          ),
        );
    }
  }
}
