import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/pickers.dart';
import 'student_detail_screen.dart';

/// The verification queue: documents students have uploaded, newest first.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  String _status = 'pending';
  int? _classId;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            children: [
              RefPicker(
                hint: 'All classes',
                load: Lookups.classes,
                value: _classId,
                onChanged: (v) => setState(() => _classId = v),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ChipFilter<String>(
                  value: _status,
                  options: const [
                    ('pending', 'Pending'),
                    ('verified', 'Verified'),
                    ('rejected', 'Rejected'),
                    ('all', 'All'),
                  ],
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<Paged<Map<String, dynamic>>>(
            refreshKey: '$_status|$_classId|$_reload',
            load: () => documentsApi.queue(status: _status == 'all' ? null : _status, classId: _classId, pageSize: 50),
            builder: (context, page, reload) {
              if (page.rows.isEmpty) {
                return const EmptyView('Nothing waiting here', icon: Icons.folder_open_outlined);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${page.total} document${page.total == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                  const SizedBox(height: 8),
                  ...page.rows.map(StudentDocument.new).map((d) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(d.title.isEmpty ? d.docTypeLabel : d.title,
                                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                  ),
                                  StatusTag(d.status),
                                ],
                              ),
                              const SizedBox(height: 3),
                              InkWell(
                                onTap: () => push(context, StudentDetailScreen(studentId: d.studentId)),
                                child: Text(
                                  '${d.studentName} · ${d.registerNo}${d.classLabel == null ? '' : ' · ${d.classLabel}'}',
                                  style: const TextStyle(fontSize: 12.5, color: Brand.accent),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text('${d.docTypeLabel} · uploaded ${fmtDate(d.createdAt)}',
                                  style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                              if (d.remarks != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Remarks: ${d.remarks}',
                                      style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
                                ),
                              if (d.file != null) ...[
                                const SizedBox(height: 10),
                                FileTile(link: d.file!, dense: true),
                              ],
                              if (d.status == 'pending') ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                            backgroundColor: Brand.success, minimumSize: const Size(0, 38)),
                                        onPressed: () async {
                                          final ok = await runAction(
                                            context,
                                            () => documentsApi.review(d.studentId, d.id, 'verified'),
                                            success: 'Verified',
                                          );
                                          if (ok) setState(() => _reload++);
                                        },
                                        child: const Text('Verify'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor: Brand.error, minimumSize: const Size(0, 38)),
                                        onPressed: () async {
                                          final remarks = await _rejectReason(context);
                                          if (remarks == null) return;
                                          final ok = await runAction(
                                            context,
                                            () => documentsApi.review(d.studentId, d.id, 'rejected', remarks: remarks),
                                            success: 'Rejected',
                                          );
                                          if (ok) setState(() => _reload++);
                                        },
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      )),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<String?> _rejectReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject this document'),
      content: TextField(
        controller: controller,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Why? (shown to the student)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.error),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Reject'),
        ),
      ],
    ),
  );
}
