import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

/// Excel imports for students, staff and student skills, plus the history of past runs.
class BulkUploadScreen extends StatelessWidget {
  const BulkUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final tabs = <(String, Widget)>[
      if (session.can(['department.create'])) ('Depts', const _Upload(kind: 'departments')),
      if (session.can(['subject.create'])) ('Subjects', const _Upload(kind: 'subjects')),
      if (session.can(['company.create'])) ('Companies', const _Upload(kind: 'companies')),
      if (session.can(['bulk_upload.create'])) ('Students', const _Upload(kind: 'students')),
      if (session.can(['staff.create'])) ('Staff', const _Upload(kind: 'staff')),
      if (session.can(['student_skill.create'])) ('Skills', const _Upload(kind: 'skills')),
      ('History', const _Jobs()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: TabBar(tabs: tabs.map((t) => Tab(text: t.$1)).toList()),
        body: TabBarView(children: tabs.map((t) => t.$2).toList()),
      ),
    );
  }
}

class _Upload extends StatefulWidget {
  const _Upload({required this.kind});
  final String kind;

  @override
  State<_Upload> createState() => _UploadState();
}

class _UploadState extends State<_Upload> {
  PlatformFile? _file;
  bool _dryRun = true;
  bool _createClasses = false;
  bool _busy = false;
  UploadJob? _result;

  String get _title => switch (widget.kind) {
        'departments' => 'Import departments',
        'subjects' => 'Import subjects',
        'companies' => 'Import companies',
        'students' => 'Import students',
        'staff' => 'Import staff',
        _ => 'Import student skills',
      };

  String get _hint => switch (widget.kind) {
        'departments' => 'One row per department: code, name and optional HOD employee code.',
        'subjects' => 'One row per subject: code, name, credits and optional department code.',
        'companies' => 'One row per company: name, industry, contact person and optional website.',
        'students' =>
          'One row per student: register number, name, department code, class and optional parent details.',
        'staff' => 'One row per staff member: employee code, name, department code, designation and roles.',
        _ => 'One row per student and skill: register number, skill name and a level from 1 to 5.',
      };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        SectionCard(
          title: _title,
          subtitle: _hint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const NoteBanner(
                title: 'Download the template from the web app first',
                body: 'The templates carry the exact column names and a reference sheet of valid codes. '
                    'Fill one in, then upload it here.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(_file == null ? 'Choose an .xlsx file' : _file!.name),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _dryRun,
                activeThumbColor: Brand.accent,
                title: const Text('Dry run', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Check every row and save nothing', style: TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() => _dryRun = v),
              ),
              if (widget.kind == 'students')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _createClasses,
                  activeThumbColor: Brand.accent,
                  title: const Text('Create missing classes', style: TextStyle(fontSize: 14)),
                  onChanged: (v) => setState(() => _createClasses = v),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy || _file == null ? null : _upload,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_dryRun ? 'Check the file' : 'Upload and save'),
              ),
            ],
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          _JobCard(job: _result!),
        ],
      ],
    );
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _file = result.files.first;
        _result = null;
      });
    }
  }

  Future<void> _upload() async {
    final f = _file!;
    setState(() => _busy = true);
    try {
      final part = f.bytes != null
          ? MultipartFile.fromBytes(f.bytes!, filename: f.name)
          : await MultipartFile.fromFile(f.path!, filename: f.name);
      final job = switch (widget.kind) {
        'departments' => await bulkApi.departments(part, dryRun: _dryRun),
        'subjects' => await bulkApi.subjects(part, dryRun: _dryRun),
        'companies' => await bulkApi.companies(part, dryRun: _dryRun),
        'students' => await bulkApi.students(part, dryRun: _dryRun, createMissingClasses: _createClasses),
        'staff' => await bulkApi.staff(part, dryRun: _dryRun),
        _ => await bulkApi.skills(part, dryRun: _dryRun),
      };
      Lookups.clear();
      if (mounted) {
        setState(() => _result = job);
        toast(context, _dryRun ? 'Checked ${job.totalRows} rows' : 'Saved ${job.successRows} rows');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Jobs extends StatelessWidget {
  const _Jobs();

  @override
  Widget build(BuildContext context) => AsyncView<Paged<Map<String, dynamic>>>(
        load: () => bulkApi.jobs(pageSize: 30),
        builder: (context, page, reload) {
          if (page.rows.isEmpty) return const EmptyView('No imports yet');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: page.rows.map(UploadJob.new).map((j) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _JobCard(job: j),
                )).toList(),
          );
        },
      );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final UploadJob job;

  @override
  Widget build(BuildContext context) => Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Row(
              children: [
                Expanded(
                  child: Text(job.fileName, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (job.dryRun) const Tag('Dry run', color: Brand.info),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Tag('${job.successRows} ok', color: Brand.success),
                  const SizedBox(width: 6),
                  if (job.failedRows > 0) Tag('${job.failedRows} failed', color: Brand.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${pretty(job.uploadType)} · ${fmtDateTime(job.createdAt)}',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
                  ),
                ],
              ),
            ),
            children: job.errors.isEmpty
                ? [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Every row was accepted.', style: TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    )
                  ]
                : job.errors
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 54,
                                child: Text('Row ${asInt(e['row'])}',
                                    style: const TextStyle(fontSize: 12, color: Brand.muted)),
                              ),
                              Expanded(
                                child: Text(
                                  '${text(e['register_no']).isEmpty ? '' : '${e['register_no']} — '}${e['message']}',
                                  style: const TextStyle(fontSize: 12.5, color: Brand.error),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
          ),
        ),
      );
}
