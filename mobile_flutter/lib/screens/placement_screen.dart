import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';
import '../widgets/master_crud.dart';
import '../widgets/pickers.dart';
import 'analyzer_screen.dart';

/// Staff run drives, applications and offers; students and parents see what they
/// are eligible for and how their applications are going.
class PlacementScreen extends StatelessWidget {
  const PlacementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.isStaff) return const _MyPlacement();

    final tabs = <(String, Widget)>[
      ('Drives', const _DrivesTab()),
      ('Offers', const _PlacementsTab()),
      ('Companies', const _CompaniesTab()),
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

// ---------------------------------------------------------------- drives

class _DrivesTab extends StatefulWidget {
  const _DrivesTab();

  @override
  State<_DrivesTab> createState() => _DrivesTabState();
}

class _DrivesTabState extends State<_DrivesTab> {
  String _search = '';
  String? _status;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: session.can(['job_role.create'])
          ? FloatingActionButton.extended(
              backgroundColor: Brand.accent,
              foregroundColor: Colors.white,
              onPressed: () async {
                final saved = await showFormSheet<bool>(context, 'New drive', (ctx) => const JobRoleForm());
                if (saved == true) setState(() => _reload++);
              },
              icon: const Icon(Icons.add),
              label: const Text('Drive'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                SearchBox(hint: 'Company or role', onChanged: (v) => setState(() => _search = v)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ChipFilter<String?>(
                    value: _status,
                    options: const [
                      (null, 'All'),
                      ('open', 'Open'),
                      ('upcoming', 'Upcoming'),
                      ('closed', 'Closed'),
                      ('completed', 'Completed'),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<JobRole>>(
              refreshKey: '$_search|$_status|$_reload',
              load: () => placementApi.roles(search: _search, status: _status),
              builder: (context, roles, reload) {
                if (roles.isEmpty) return const EmptyView('No drives yet');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: roles
                      .map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DriveCard(
                              role: r,
                              onTap: () async {
                                await push(context, JobRoleScreen(roleId: r.id));
                                setState(() => _reload++);
                              },
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveCard extends StatelessWidget {
  const _DriveCard({required this.role, required this.onTap});
  final JobRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (role.logo != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Brand.borderSoft,
                          foregroundImage: NetworkImage(api.fileUrl(role.logo!.url)),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Avatar(name: role.companyName, radius: 17),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(role.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          Text(role.companyName, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                        ],
                      ),
                    ),
                    StatusTag(role.status),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Tag(lpa(role.packageLpa), color: Brand.accent),
                  Tag('CGPA ${role.minCgpa}+'),
                  Tag('≤ ${role.maxBacklogs} backlogs'),
                  if (role.driveDate != null) Tag('Drive ${fmtDate(role.driveDate, 'dd MMM')}'),
                  if (role.applicationCount > 0) Tag('${role.applicationCount} applied'),
                  if (role.selectedCount > 0) Tag('${role.selectedCount} selected', color: Brand.success),
                ]),
              ],
            ),
          ),
        ),
      );
}

/// One drive: requirements, the ranking shortcut, applications and files.
class JobRoleScreen extends StatefulWidget {
  const JobRoleScreen({super.key, required this.roleId});
  final int roleId;

  @override
  State<JobRoleScreen> createState() => _JobRoleScreenState();
}

class _JobRoleScreenState extends State<JobRoleScreen> {
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AsyncView<(JobRole, List<Application>)>(
      refreshKey: _reload,
      scrollable: false,
      load: () async {
        final role = await placementApi.role(widget.roleId);
        List<Application> apps = const [];
        if (session.can(['placement.view'])) {
          try {
            apps = await placementApi.applications(widget.roleId);
          } catch (_) {
            // Applications are staff-only; the drive itself is still worth showing.
          }
        }
        return (role, apps);
      },
      builder: (context, data, reload) {
        final (role, apps) = data;
        return Scaffold(
          backgroundColor: Brand.layout,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role.title, overflow: TextOverflow.ellipsis),
                Text(role.companyName,
                    style: const TextStyle(fontSize: 12, color: Brand.textSoft, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: [
              if (session.can(['job_role.update']))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit drive')),
                    for (final s in ['upcoming', 'open', 'closed', 'completed'])
                      if (s != role.status) PopupMenuItem(value: 'status:$s', child: Text('Mark ${pretty(s)}')),
                  ],
                  onSelected: (v) async {
                    if (v == 'edit') {
                      final saved = await showFormSheet<bool>(
                          context, 'Edit drive', (ctx) => JobRoleForm(role: role));
                      if (saved == true) setState(() => _reload++);
                    } else {
                      final status = v.split(':')[1];
                      final ok = await runAction(
                        context,
                        () => placementApi.setRoleStatus(role.id, status),
                        success: 'Drive marked ${pretty(status)}',
                      );
                      if (ok) setState(() => _reload++);
                    }
                  },
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              SectionCard(
                title: 'Requirements',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailRow('Package', lpa(role.packageLpa)),
                    DetailRow('Minimum CGPA', '${role.minCgpa}'),
                    DetailRow('Backlogs allowed', '${role.maxBacklogs}'),
                    DetailRow('Batch', role.eligibleBatch ?? 'Any'),
                    DetailRow('Departments',
                        role.departments.isEmpty ? 'All' : role.departments.map((d) => d.label).join(', ')),
                    DetailRow('Drive date', role.driveDate == null ? null : fmtDate(role.driveDate)),
                    DetailRow('Apply by', role.lastApplyDate == null ? null : fmtDate(role.lastApplyDate)),
                    if (role.openings != null) DetailRow('Openings', '${role.openings}'),
                    const SizedBox(height: 8),
                    const Text('Skills needed', style: TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: role.skills
                          .map((s) => Tag('${s.name} L${s.requiredLevel}${s.isMandatory ? ' *' : ''}',
                              color: s.isMandatory ? Brand.error : null))
                          .toList(),
                    ),
                    if (role.description != null) ...[
                      const SizedBox(height: 10),
                      Text(role.description!, style: const TextStyle(fontSize: 13, color: Brand.textSoft)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (session.can(['job_role.update']))
                SectionCard(
                  title: 'Job description',
                  child: FileSlot(
                    category: 'job_description',
                    current: role.jd,
                    onChanged: (fileId, _) async {
                      await filesApi.setJobDescription(role.id, fileId);
                      setState(() => _reload++);
                    },
                  ),
                )
              else if (role.jd != null)
                SectionCard(title: 'Job description', child: FileTile(link: role.jd!)),
              const SizedBox(height: 10),
              if (session.can(['skill_analyzer.view']))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights_outlined, color: Brand.accent),
                    title: const Text('Rank students for this drive',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      role.analyzedAt == null
                          ? 'Not analysed yet'
                          : 'Last run ${fmtDateTime(role.analyzedAt)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
                    onTap: () async {
                      await push(context, SubPage(title: 'Skill Analyzer', child: AnalyzerScreen(roleId: role.id)));
                      setState(() => _reload++);
                    },
                  ),
                ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Applications',
                subtitle: '${apps.length} student${apps.length == 1 ? '' : 's'}',
                child: apps.isEmpty
                    ? const Text('Nobody has been shortlisted or applied yet',
                        style: TextStyle(fontSize: 13, color: Brand.muted))
                    : Column(
                        children: apps
                            .map((a) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(a.studentName, style: const TextStyle(fontSize: 14)),
                                  subtitle: Text(
                                    '${a.registerNo} · CGPA ${a.cgpa.toStringAsFixed(2)}'
                                    '${a.matchScore == null ? '' : ' · match ${a.matchScore!.toStringAsFixed(0)}'}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  trailing: session.can(['placement.update'])
                                      ? PopupMenuButton<String>(
                                          child: StatusTag(a.status),
                                          itemBuilder: (context) => [
                                            for (final s in [
                                              'shortlisted',
                                              'applied',
                                              'in_process',
                                              'selected',
                                              'rejected',
                                              'withdrawn'
                                            ])
                                              if (s != a.status) PopupMenuItem(value: s, child: Text(pretty(s))),
                                          ],
                                          onSelected: (s) async {
                                            final ok = await runAction(
                                              context,
                                              () => placementApi.updateApplication(a.id, s),
                                              success: 'Marked ${pretty(s)}',
                                            );
                                            if (ok) setState(() => _reload++);
                                          },
                                        )
                                      : StatusTag(a.status),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Create or edit a drive, with its eligibility rules and required skills.
class JobRoleForm extends StatefulWidget {
  const JobRoleForm({super.key, this.role});
  final JobRole? role;

  @override
  State<JobRoleForm> createState() => _JobRoleFormState();
}

class _JobRoleFormState extends State<JobRoleForm> {
  late final _title = TextEditingController(text: widget.role?.title);
  late final _description = TextEditingController(text: widget.role?.description);
  late final _package = TextEditingController(text: widget.role?.packageLpa.toString());
  late final _minCgpa = TextEditingController(text: '${widget.role?.minCgpa ?? 0}');
  late final _maxBacklogs = TextEditingController(text: '${widget.role?.maxBacklogs ?? 0}');
  late final _batch = TextEditingController(text: widget.role?.eligibleBatch);
  late final _openings = TextEditingController(text: widget.role?.openings?.toString());
  late final _driveDate = TextEditingController(text: widget.role?.driveDate);
  late final _applyDate = TextEditingController(text: widget.role?.lastApplyDate);
  late int? _companyId = widget.role?.companyId;
  late String _status = widget.role?.status ?? 'upcoming';
  late final List<int> _departmentIds = (widget.role?.departments ?? []).map((d) => d.id).toList();
  late final List<Map<String, dynamic>> _skills = (widget.role?.skills ?? [])
      .map((s) => {
            'skill_id': s.skillId,
            'required_level': s.requiredLevel,
            'is_mandatory': s.isMandatory,
            'weight': s.weight,
          })
      .toList();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _title,
      _description,
      _package,
      _minCgpa,
      _maxBacklogs,
      _batch,
      _openings,
      _driveDate,
      _applyDate
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field(
            'Company',
            child: RefPicker(
              hint: 'Company',
              allowClear: false,
              load: Lookups.companies,
              value: _companyId,
              onChanged: (v) => setState(() => _companyId = v),
            ),
          ),
          Field('Role title', child: TextField(controller: _title)),
          Row(children: [
            Expanded(
              child: Field('Package (LPA)',
                  child: TextField(controller: _package, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Field(
                'Status',
                child: EnumPicker(
                  value: _status,
                  options: const ['upcoming', 'open', 'closed', 'completed'],
                  onChanged: (v) => setState(() => _status = v ?? 'upcoming'),
                ),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: Field('Minimum CGPA',
                  child: TextField(controller: _minCgpa, keyboardType: const TextInputType.numberWithOptions(decimal: true))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Field('Backlogs allowed',
                  child: TextField(controller: _maxBacklogs, keyboardType: TextInputType.number)),
            ),
          ]),
          Row(children: [
            Expanded(child: Field('Eligible batch', hint: 'e.g. 2023-2027', child: TextField(controller: _batch))),
            const SizedBox(width: 12),
            Expanded(child: Field('Openings', child: TextField(controller: _openings, keyboardType: TextInputType.number))),
          ]),
          Row(children: [
            Expanded(child: Field('Drive date', hint: 'YYYY-MM-DD', child: TextField(controller: _driveDate))),
            const SizedBox(width: 12),
            Expanded(child: Field('Apply by', hint: 'YYYY-MM-DD', child: TextField(controller: _applyDate))),
          ]),
          Field('About the role', child: TextField(controller: _description, maxLines: 3)),
          Field(
            'Eligible departments',
            hint: 'Leave empty for every department',
            child: FutureBuilder<List<Ref>>(
              future: Lookups.departments(),
              builder: (context, snap) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (snap.data ?? [])
                    .map((d) => FilterChip(
                          label: Text(d.label, style: const TextStyle(fontSize: 12)),
                          selected: _departmentIds.contains(d.id),
                          onSelected: (on) => setState(
                              () => on ? _departmentIds.add(d.id) : _departmentIds.remove(d.id)),
                        ))
                    .toList(),
              ),
            ),
          ),
          const Divider(height: 24),
          const Text('Skills it needs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'A mandatory skill below the required level makes a student ineligible, not just lower ranked.',
            style: TextStyle(fontSize: 12, color: Brand.muted),
          ),
          const SizedBox(height: 12),
          ..._skills.asMap().entries.map((e) {
            final i = e.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RefPicker(
                          hint: 'Skill',
                          allowClear: false,
                          load: Lookups.skills,
                          value: asIntOrNull(_skills[i]['skill_id']),
                          onChanged: (v) => setState(() => _skills[i]['skill_id'] = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _skills.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: asInt(_skills[i]['required_level'], 3),
                          items: [1, 2, 3, 4, 5].map((l) => DropdownMenuItem(value: l, child: Text('Level $l'))).toList(),
                          onChanged: (v) => setState(() => _skills[i]['required_level'] = v ?? 3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 86,
                        child: TextFormField(
                          initialValue: '${_skills[i]['weight'] ?? 1}',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'weight'),
                          onChanged: (v) => _skills[i]['weight'] = double.tryParse(v) ?? 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          const Text('must', style: TextStyle(fontSize: 11, color: Brand.textSoft)),
                          Switch(
                            value: _skills[i]['is_mandatory'] == true,
                            activeThumbColor: Brand.error,
                            onChanged: (v) => setState(() => _skills[i]['is_mandatory'] = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => setState(() =>
                _skills.add({'skill_id': null, 'required_level': 3, 'is_mandatory': false, 'weight': 1.0})),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a skill'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.role == null ? 'Add drive' : 'Save changes'),
          ),
        ],
      );

  Future<void> _save() async {
    if (_companyId == null || _title.text.trim().isEmpty) {
      toast(context, 'Company and role title are required', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = {
      'company_id': _companyId,
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'package_lpa': double.tryParse(_package.text.trim()) ?? 0,
      'min_cgpa': double.tryParse(_minCgpa.text.trim()) ?? 0,
      'max_backlogs': int.tryParse(_maxBacklogs.text.trim()) ?? 0,
      'eligible_batch': _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      'openings': int.tryParse(_openings.text.trim()),
      'drive_date': _driveDate.text.trim().isEmpty ? null : _driveDate.text.trim(),
      'last_apply_date': _applyDate.text.trim().isEmpty ? null : _applyDate.text.trim(),
      'status': _status,
      'department_ids': _departmentIds,
      'skills': _skills
          .where((s) => s['skill_id'] != null)
          .map((s) => {
                'skill_id': s['skill_id'],
                'required_level': s['required_level'],
                'is_mandatory': s['is_mandatory'] == true,
                'weight': s['weight'] ?? 1,
              })
          .toList(),
    };
    final ok = await runAction(
      context,
      () => widget.role == null ? placementApi.createRole(body) : placementApi.updateRole(widget.role!.id, body),
      success: widget.role == null ? 'Drive added' : 'Drive updated',
    );
    if (mounted) setState(() => _busy = false);
    if (ok && mounted) Navigator.pop(context, true);
  }
}

// ---------------------------------------------------------------- offers & companies

class _PlacementsTab extends StatefulWidget {
  const _PlacementsTab();

  @override
  State<_PlacementsTab> createState() => _PlacementsTabState();
}

class _PlacementsTabState extends State<_PlacementsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SearchBox(hint: 'Student or company', onChanged: (v) => setState(() => _search = v)),
          ),
          Expanded(
            child: AsyncView<(List<Placement>, Map<String, dynamic>)>(
              refreshKey: _search,
              load: () async => (await placementApi.placements(search: _search), await placementApi.stats()),
              builder: (context, data, reload) {
                final (placements, stats) = data;
                final byDept = maps(stats['by_department']);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileGrid(children: [
                      StatTile(
                        label: 'Placed',
                        value: '${asInt(stats['placed_students'])}',
                        hint: '${asDouble(stats['placed_percent']).toStringAsFixed(1)}% of ${asInt(stats['total_students'])}',
                        color: Brand.success,
                      ),
                      StatTile(label: 'Offers', value: '${asInt(stats['total_offers'])}'),
                      StatTile(
                        label: 'Highest',
                        value: stats['highest_package'] == null ? '—' : lpa(asDouble(stats['highest_package'])),
                        color: Brand.accent,
                      ),
                      StatTile(
                        label: 'Average',
                        value: stats['average_package'] == null ? '—' : lpa(asDouble(stats['average_package'])),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (byDept.isNotEmpty)
                      SectionCard(
                        title: 'Placed by department',
                        child: BarChart(
                          suffix: '%',
                          max: 100,
                          rows: byDept
                              .map((d) => BarRow(
                                    text(d['code']),
                                    asDouble(d['percent']),
                                    caption: '${asInt(d['placed'])} of ${asInt(d['students'])}',
                                  ))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (placements.isEmpty)
                      const EmptyView('No offers recorded yet')
                    else
                      ...placements.map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                title: Text(p.studentName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${p.registerNo} · ${p.companyName} · ${p.jobTitle}'
                                  '${p.offerDate == null ? '' : ' · ${fmtDate(p.offerDate)}'}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                                trailing: Tag(lpa(p.packageLpa), color: Brand.success),
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

class _CompaniesTab extends StatelessWidget {
  const _CompaniesTab();

  @override
  Widget build(BuildContext context) => MasterCrud(
        path: 'companies',
        permission: 'company',
        noun: 'company',
        fields: const [
          MasterField('name', 'Company name', required: true),
          MasterField('industry', 'Industry'),
          MasterField('location', 'Location'),
          MasterField('website', 'Website'),
          MasterField('contact_person', 'Contact person'),
          MasterField('contact_email', 'Contact email'),
          MasterField('contact_mobile', 'Contact mobile'),
          MasterField('description', 'Notes'),
        ],
        title: _companyTitle,
        badges: _companyBadges,
      );

  static (String, String?) _companyTitle(MasterRow r) => (
        text(r['name']),
        [r['industry'], r['location']].whereType<String>().join(' · '),
      );

  static List<Widget> _companyBadges(MasterRow r) => [
        if (asInt(r['job_role_count']) > 0) Tag('${asInt(r['job_role_count'])} drives'),
      ];
}

// ---------------------------------------------------------------- student / parent

class _MyPlacement extends StatefulWidget {
  const _MyPlacement();

  @override
  State<_MyPlacement> createState() => _MyPlacementState();
}

class _MyPlacementState extends State<_MyPlacement> {
  int? _studentId;

  @override
  Widget build(BuildContext context) {
    final isParent = context.watch<Session>().audience.name == 'parent';
    return AsyncView<List<Student>>(
      scrollable: false,
      load: () async => (await studentsApi.list(pageSize: isParent ? 50 : 1)).rows.map(Student.new).toList(),
      builder: (context, children, reload) {
        if (children.isEmpty) return const EmptyView('No student profile is linked to your account yet.');
        final chosen = children.firstWhere((c) => c.id == _studentId, orElse: () => children.first);
        return Column(
          children: [
            if (children.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<int>(
                  initialValue: chosen.id,
                  isExpanded: true,
                  items: children.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                  onChanged: (v) => setState(() => _studentId = v),
                ),
              ),
            Expanded(child: StudentOpportunitiesView(studentId: chosen.id, mode: 'drives')),
          ],
        );
      },
    );
  }
}

/// What one student is eligible for. `mode` is 'drives' (with applications) or
/// 'gap' (the skill-gap reading used by the analyzer screen).
class StudentOpportunitiesView extends StatelessWidget {
  const StudentOpportunitiesView({super.key, required this.studentId, this.mode = 'drives'});
  final int studentId;
  final String mode;

  @override
  Widget build(BuildContext context) => AsyncView<Map<String, dynamic>>(
        load: () => placementApi.opportunities(studentId),
        builder: (context, data, reload) {
          final ops = maps(data['opportunities']).map(Opportunity.new).toList();
          final apps = maps(data['applications']).map(Application.new).toList();
          final offers = apps.where((a) => a.status == 'selected').toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mode == 'drives' && offers.isNotEmpty) ...[
                NoteBanner(
                  title: 'Placed at ${offers.first.companyName}',
                  body: '${offers.first.jobTitle} · ${lpa(offers.first.packageLpa)}. '
                      'You can still apply to drives with a higher package.',
                  color: Brand.success,
                  icon: Icons.celebration_outlined,
                ),
                const SizedBox(height: 12),
              ],
              if (ops.isEmpty)
                const EmptyView('No open or upcoming drives right now', icon: Icons.work_outline)
              else
                ...ops.map((o) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OpportunityCard(op: o, mode: mode),
                    )),
              if (mode == 'drives' && apps.isNotEmpty) ...[
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Your applications',
                  child: Column(
                    children: apps
                        .map((a) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text('${a.companyName} · ${a.jobTitle}', style: const TextStyle(fontSize: 13.5)),
                              subtitle: Text(lpa(a.packageLpa), style: const TextStyle(fontSize: 12)),
                              trailing: StatusTag(a.status),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          );
        },
      );
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({required this.op, required this.mode});
  final Opportunity op;
  final String mode;

  @override
  Widget build(BuildContext context) {
    final role = op.role;
    final all = [...op.missing, ...op.matched];
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: mode == 'gap',
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Expanded(
                child: Text('${role.companyName} · ${role.title}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
              Tag(op.isEligible ? 'Eligible' : 'Not eligible', color: op.isEligible ? Brand.success : Brand.error),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              Tag(lpa(role.packageLpa), color: Brand.accent),
              Tag('Skill match ${op.skillScore.toStringAsFixed(0)}%'),
              if (role.driveDate != null) Tag('Drive ${fmtDate(role.driveDate, 'dd MMM')}'),
              if (op.applicationStatus != null) StatusTag(op.applicationStatus),
            ]),
          ),
          children: [
            if (!op.isEligible) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: op.reasons
                      .map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.close, size: 13, color: Brand.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(r, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(height: 20),
            ],
            ...all.map((g) => MeterBar(
                  label: g.name,
                  progress: g.progress,
                  trailing: '${g.studentLevel}/${g.requiredLevel}',
                  emphasise: g.isMandatory,
                  met: g.met,
                  tooltip: 'Blended score ${g.studentScore} of the ${g.requiredScore} needed',
                )),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('* must-have skill. Levels come from your blended skill score.',
                  style: TextStyle(fontSize: 11, color: Brand.muted)),
            ),
          ],
        ),
      ),
    );
  }
}
