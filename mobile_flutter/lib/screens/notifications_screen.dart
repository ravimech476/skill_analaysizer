import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/pickers.dart';

const _typeColors = {
  'general': Brand.info,
  'placement': Brand.success,
  'marks': Color(0xFF6D28D9),
  'skill': Color(0xFFB45309),
  'system': Brand.textSoft,
};

/// The inbox, and for staff the announcements they have sent.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.can(['notification.create'])) return const _Inbox();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const TabBar(tabs: [Tab(text: 'Inbox'), Tab(text: 'Sent')]),
        body: const TabBarView(children: [_Inbox(), _Sent()]),
      ),
    );
  }
}

class _Inbox extends StatefulWidget {
  const _Inbox();

  @override
  State<_Inbox> createState() => _InboxState();
}

class _InboxState extends State<_Inbox> {
  bool _unreadOnly = false;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: ChipFilter<bool>(
                  value: _unreadOnly,
                  options: const [(false, 'All'), (true, 'Unread')],
                  onChanged: (v) => setState(() => _unreadOnly = v),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await runAction(context, notificationsApi.readAll, success: 'All marked read');
                  if (ok) {
                    await session.refreshUnread();
                    setState(() => _reload++);
                  }
                },
                child: const Text('Mark all read'),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<Paged<Map<String, dynamic>>>(
            refreshKey: '$_unreadOnly|$_reload',
            load: () => notificationsApi.inbox(unreadOnly: _unreadOnly, pageSize: 50),
            builder: (context, page, reload) {
              if (page.rows.isEmpty) {
                return const EmptyView('Nothing here yet', icon: Icons.notifications_none);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: page.rows.map(Notice.new).map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: n.isRead
                              ? null
                              : () async {
                                  await runAction(context, () => notificationsApi.markRead(n.id));
                                  await session.refreshUnread();
                                  if (mounted) setState(() => _reload++);
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (!n.isRead)
                                      Container(
                                        width: 7,
                                        height: 7,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: const BoxDecoration(color: Brand.accent, shape: BoxShape.circle),
                                      ),
                                    Expanded(
                                      child: Text(n.title,
                                          style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                                    ),
                                    Tag(pretty(n.type), color: _typeColors[n.type]),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(n.body, style: const TextStyle(fontSize: 13, color: Brand.textSoft)),
                                const SizedBox(height: 6),
                                Text(
                                  '${n.senderName ?? 'System'} · ${fmtDateTime(n.createdAt)}',
                                  style: const TextStyle(fontSize: 11.5, color: Brand.muted),
                                ),
                                if (n.attachment != null) ...[
                                  const SizedBox(height: 8),
                                  FileTile(link: n.attachment!, dense: true),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Sent extends StatefulWidget {
  const _Sent();

  @override
  State<_Sent> createState() => _SentState();
}

class _SentState extends State<_Sent> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Brand.accent,
          foregroundColor: Colors.white,
          onPressed: () async {
            final sent = await showFormSheet<bool>(context, 'Send an announcement', (ctx) => const _SendForm());
            if (sent == true) setState(() => _reload++);
          },
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Announce'),
        ),
        body: AsyncView<List<Map<String, dynamic>>>(
          refreshKey: _reload,
          load: notificationsApi.sent,
          builder: (context, rows, reload) {
            if (rows.isEmpty) return const EmptyView('You have not sent anything yet');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows
                  .map((n) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(text(n['title']),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '${text(n['body'])}\n'
                              '${asInt(n['recipients'])} recipients · ${asInt(n['read_count'])} read · '
                              '${fmtDateTime(text(n['created_at']))}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Tag(text(n['target_label'], pretty(text(n['target_type'])))),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      );
}

class _SendForm extends StatefulWidget {
  const _SendForm();

  @override
  State<_SendForm> createState() => _SendFormState();
}

class _SendFormState extends State<_SendForm> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _type = 'general';
  String _targetType = 'all';
  int? _targetId;
  bool _includeParents = false;
  FileLink? _attachment;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field('Title', child: TextField(controller: _title)),
          Field('Message', child: TextField(controller: _body, maxLines: 4)),
          Field(
            'Type',
            child: EnumPicker(
              value: _type,
              options: const ['general', 'placement', 'marks', 'skill', 'system'],
              onChanged: (v) => setState(() => _type = v ?? 'general'),
            ),
          ),
          Field(
            'Send to',
            child: EnumPicker(
              value: _targetType,
              options: const ['all', 'role', 'department', 'class', 'user'],
              onChanged: (v) => setState(() {
                _targetType = v ?? 'all';
                _targetId = null;
              }),
            ),
          ),
          if (_targetType == 'department')
            Field(
              'Department',
              child: RefPicker(
                hint: 'Department',
                allowClear: false,
                load: Lookups.departments,
                value: _targetId,
                onChanged: (v) => setState(() => _targetId = v),
              ),
            ),
          if (_targetType == 'class')
            Field(
              'Class',
              child: RefPicker(
                hint: 'Class',
                allowClear: false,
                load: Lookups.classes,
                value: _targetId,
                onChanged: (v) => setState(() => _targetId = v),
              ),
            ),
          if (_targetType == 'user')
            Field(
              'Student',
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pickStudent(context);
                  if (picked != null) setState(() => _targetId = picked.id);
                },
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text(_targetId == null ? 'Choose a student' : 'Student #$_targetId'),
              ),
            ),
          if (_targetType == 'role')
            Field(
              'Role',
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: rolesApi.list(),
                builder: (context, snap) => DropdownButtonFormField<int>(
                  initialValue: _targetId,
                  isExpanded: true,
                  hint: const Text('Role'),
                  items: (snap.data ?? [])
                      .map((r) => DropdownMenuItem(value: asInt(r['id']), child: Text(text(r['name']))))
                      .toList(),
                  onChanged: (v) => setState(() => _targetId = v),
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeParents,
            activeThumbColor: Brand.accent,
            title: const Text('Also send to parents', style: TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() => _includeParents = v),
          ),
          const SizedBox(height: 8),
          Field(
            'Attachment',
            child: FileSlot(
              category: 'notification_attachment',
              current: _attachment,
              onChanged: (fileId, link) async => setState(() => _attachment = link),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _busy || _title.text.trim().isEmpty
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await runAction(context, () async {
                      final r = await notificationsApi.send({
                        'title': _title.text.trim(),
                        'body': _body.text.trim(),
                        'type': _type,
                        'target_type': _targetType,
                        if (_targetId != null) 'target_id': _targetId,
                        'include_parents': _includeParents,
                        if (_attachment?.id != null) 'attachment_file_id': _attachment!.id,
                      });
                      if (context.mounted) toast(context, 'Sent to ${asInt(r['recipients'])} people');
                    });
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: const Text('Send'),
          ),
        ],
      );
}
