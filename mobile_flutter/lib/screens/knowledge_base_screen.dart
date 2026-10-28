import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/knowledge_api.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Staff screen: the documents the AI assistant can search, with a test search to see what it would find.
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  int _version = 0;
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _hits;
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _version++);

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final hits = await kbApi.search(q);
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _upload() async {
    final saved = await showFormSheet<bool>(context, 'Upload document', (ctx) => const _UploadForm());
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<Map<String, dynamic>>>(
        refreshKey: 'kb$_version',
        load: kbApi.list,
        builder: (context, docs, reload) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoteBanner(
              title: 'Documents the assistant can answer from',
              body: 'Uploaded files are cut into passages and indexed, so students get answers with the document named as the source. '
                  'PDF, Word, text and Markdown up to 10 MB; scanned PDFs are not supported. ${docs.length} document(s) now.',
              color: Brand.info,
              icon: Icons.info_outline,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _upload, icon: const Icon(Icons.upload_file), label: const Text('Upload document')),
            const SizedBox(height: 10),
            SectionCard(
              title: 'Test search',
              subtitle: 'Ask a question the way a student would and see which passages the assistant would find.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      maxLength: 500,
                      decoration: const InputDecoration(hintText: 'e.g. Which topics are in the graphs unit?', counterText: ''),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _searching ? null : _search, icon: const Icon(Icons.search)),
                ]),
                if (_searching) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                if (_hits != null && !_searching) ...[
                  const SizedBox(height: 10),
                  if (_hits!.isEmpty)
                    const NoteBanner(title: 'No passage matched closely enough', body: 'The assistant would answer without document sources.', color: Brand.warning, icon: Icons.info_outline)
                  else
                    for (final h in _hits!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(border: Border.all(color: Brand.border), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(text(h['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                              Tag('${(asDouble(h['score']) * 100).round()}% match', color: Brand.success),
                            ]),
                            const SizedBox(height: 4),
                            Text(text(h['content']), maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                          ]),
                        ),
                      ),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty) const EmptyView('No documents yet. Upload a syllabus or notes to get started.'),
            for (final d in docs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(text(d['title']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Tag(kbDocTypes[text(d['doc_type'])] ?? text(d['doc_type'])),
                    Text(text(d['department_name'], 'Everyone'), style: const TextStyle(fontSize: 12)),
                    if (text(d['subject_name']).isNotEmpty) Text(text(d['subject_name']), style: const TextStyle(fontSize: 12)),
                    Text('${asInt(d['chunk_count'])} passage(s)', style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                  ]),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Brand.error),
                    tooltip: 'Remove',
                    onPressed: () async {
                      if (!await confirm(context, 'Remove this document?', body: 'The assistant will stop using it.', danger: true, okLabel: 'Remove')) return;
                      if (context.mounted && await runAction(context, () => kbApi.remove(asInt(d['id'])), success: 'Removed')) _reload();
                    },
                  ),
                ),
              ),
          ],
        ),
      );
}

class _UploadForm extends StatefulWidget {
  const _UploadForm();

  @override
  State<_UploadForm> createState() => _UploadFormState();
}

class _UploadFormState extends State<_UploadForm> {
  static const _maxMb = 10;
  PlatformFile? _file;
  final _title = TextEditingController();
  String _type = 'notes';
  int? _departmentId;
  int? _subjectId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'docx', 'txt', 'md'], withData: kIsWeb);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    setState(() {
      if (f.size > _maxMb * 1024 * 1024) {
        _file = null;
        _error = 'That file is larger than $_maxMb MB';
      } else {
        _file = f;
        _error = null;
      }
    });
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final part = f.bytes != null ? MultipartFile.fromBytes(f.bytes!, filename: f.name) : await MultipartFile.fromFile(f.path!, filename: f.name);
      final r = await kbApi.upload(part, docType: _type, title: _title.text.trim().isEmpty ? null : _title.text.trim(), departmentId: _departmentId, subjectId: _subjectId);
      if (!mounted) return;
      toast(context, 'Indexed "${text(r['title'])}" as ${asInt(r['chunk_count'])} passage(s)');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final crossDepartment = context.read<Session>().user?.roles.any((r) => r == 'admin' || r == 'placement_officer') ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[NoteBanner(title: _error!, color: Brand.error, icon: Icons.error_outline), const SizedBox(height: 12)],
      OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.attach_file), label: Text(_file?.name ?? 'Choose a file (PDF, DOCX, TXT, MD)')),
      const SizedBox(height: 12),
      Field('Title', hint: 'Shown to students under answers. Defaults to the file name.', child: TextField(controller: _title, maxLength: 200)),
      Field('Type', child: DropdownButtonFormField<String>(
        initialValue: _type,
        isExpanded: true,
        items: [for (final e in kbDocTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) => setState(() => _type = v ?? _type),
      )),
      if (crossDepartment)
        Field('Department', hint: 'Leave empty to share with every department.', child: RefPicker(hint: 'Everyone', load: Lookups.departments, value: _departmentId, onChanged: (v) => setState(() => _departmentId = v)))
      else
        const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('This document will be shared with your own department.', style: TextStyle(fontSize: 12.5, color: Brand.textSoft))),
      Field('Subject (optional)', child: RefPicker(hint: 'None', load: Lookups.subjects, value: _subjectId, onChanged: (v) => setState(() => _subjectId = v))),
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
      FilledButton(onPressed: _busy || _file == null ? null : _save, child: Text(_busy ? 'Indexing… this can take a minute' : 'Upload and index')),
    ]);
  }
}
