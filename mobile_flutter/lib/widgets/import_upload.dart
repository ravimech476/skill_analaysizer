import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';
import 'common.dart';
import 'pickers.dart';

/// A reusable file-upload widget for importing .xlsx data.
///
/// Used inside the "Import" tab of each master screen (academic, staff,
/// students, skills, placement). It picks a file, optionally runs a dry run,
/// uploads via [upload], and shows the result card.
class ImportUpload extends StatefulWidget {
  const ImportUpload({
    super.key,
    required this.title,
    required this.hint,
    required this.upload,
    this.extraControls,
  });

  final String title;
  final String hint;

  /// Called with the chosen file and the dry-run flag. Must return an
  /// [UploadJob] so the result card can render totals and errors.
  final Future<UploadJob> Function(MultipartFile file, {required bool dryRun}) upload;

  /// Optional extra controls rendered between the dry-run switch and the
  /// upload button (e.g. a "Create missing classes" toggle for students).
  final Widget Function(bool busy)? extraControls;

  @override
  State<ImportUpload> createState() => _ImportUploadState();
}

class _ImportUploadState extends State<ImportUpload> {
  PlatformFile? _file;
  bool _dryRun = true;
  bool _busy = false;
  UploadJob? _result;

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
      final job = await widget.upload(part, dryRun: _dryRun);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionCard(
          title: 'Import ${widget.title}',
          subtitle: widget.hint,
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
              if (widget.extraControls != null) widget.extraControls!(_busy),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy || _file == null ? null : _upload,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
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
}

/// Shows the outcome of a single upload job: totals and per-row errors.
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
                  child: Text(job.fileName,
                      overflow: TextOverflow.ellipsis,
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
                    child: Text('${job.totalRows} total',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Brand.muted)),
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
