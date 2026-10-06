import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/access.dart';
import 'auth/session.dart';
import 'main.dart';
import 'screens/academic_screen.dart';
import 'screens/analyzer_screen.dart';
import 'screens/bulk_upload_screen.dart';
import 'screens/careers_screen.dart';
import 'screens/classes_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/marks_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/placement_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/roles_screen.dart';
import 'screens/skills_screen.dart';
import 'screens/staff_screen.dart';
import 'screens/students_screen.dart';
import 'screens/users_screen.dart';
import 'screens/year_end_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/files.dart';

/// Which widget each feature key opens. Keys come from auth/access.dart.
Widget screenFor(String key) {
  switch (key) {
    case 'dashboard':
      return const DashboardScreen();
    case 'students':
      return const StudentsScreen();
    case 'marks':
      return const MarksScreen();
    case 'skills':
      return const SkillsScreen();
    case 'careers':
      return const CareersScreen();
    case 'placement':
      return const PlacementScreen();
    case 'analyzer':
      return const AnalyzerScreen();
    case 'classes':
      return const ClassesScreen();
    case 'staff':
      return const StaffScreen();
    case 'documents':
      return const DocumentsScreen();
    case 'reports':
      return const ReportsScreen();
    case 'yearend':
      return const YearEndScreen();
    case 'bulk':
      return const BulkUploadScreen();
    case 'academic':
      return const AcademicScreen();
    case 'users':
      return const UsersScreen();
    case 'roles':
      return const RolesScreen();
    case 'notifications':
      return const NotificationsScreen();
    default:
      return const Center(child: Text('Coming soon'));
  }
}

/// The signed-in frame: white app bar, dark navigation drawer, and the chosen screen.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _current = 'dashboard';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final visible = session.visibleFeatures;
    final feature = visible.firstWhere((f) => f.key == _current, orElse: () => visible.first);
    final title = featureLabel(feature, session.audience);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          _BellButton(onOpen: () => setState(() => _current = 'notifications')),
          _ProfileButton(session: session),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _NavDrawer(
        current: feature.key,
        onSelect: (key) => setState(() => _current = key),
      ),
      body: KeyedSubtree(key: ValueKey(feature.key), child: screenFor(feature.key)),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<Session>().unread;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onOpen,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        backgroundColor: Brand.error,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: session.user?.name ?? 'Account',
      offset: const Offset(0, 48),
      onSelected: (value) async {
        if (value == 'profile') {
          await push(context, const ProfileScreen());
        } else if (value == 'logout') {
          if (await confirm(context, 'Log out?', okLabel: 'Log out', danger: true)) {
            await session.signOut();
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.text)),
              Text(session.user?.roles.map(pretty).join(', ') ?? '',
                  style: const TextStyle(fontSize: 12, color: Brand.textSoft)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('My profile'))),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(leading: Icon(Icons.logout, color: Brand.error), title: Text('Log out', style: TextStyle(color: Brand.error))),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Avatar(name: session.user?.name, photo: session.user?.photo, radius: 16),
      ),
    );
  }
}

/// The dark sidebar, grouped exactly like the web app's.
class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.current, required this.onSelect});
  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final visible = session.visibleFeatures;
    final byKey = {for (final f in visible) f.key: f};
    final used = <String>{};
    final sections = <(String, List<Feature>)>[];

    menuGroups.forEach((title, keys) {
      final items = keys.where(byKey.containsKey).map((k) {
        used.add(k);
        return byKey[k]!;
      }).toList();
      if (items.isNotEmpty) sections.add((title, items));
    });
    final rest = visible.where((f) => !used.contains(f.key)).toList();
    if (rest.isNotEmpty) sections.add(('More', rest));

    // Students and parents see a handful of screens: a flat list reads better for them.
    final grouped = visible.length > 8;

    return Drawer(
      backgroundColor: Brand.chrome,
      width: 282,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.insights, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Skills Analyzer',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('CAMPUS PLACEMENTS',
                          style: TextStyle(color: Brand.muted, fontSize: 9.5, letterSpacing: 1.1, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Brand.chromeSoft, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: grouped
                    ? [
                        for (final section in sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                            child: Text(
                              section.$1.toUpperCase(),
                              style: const TextStyle(
                                  color: Brand.muted, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w700),
                            ),
                          ),
                          ...section.$2.map((f) => _NavItem(
                                feature: f,
                                audience: session.audience,
                                selected: f.key == current,
                                onTap: () {
                                  Navigator.pop(context);
                                  onSelect(f.key);
                                },
                              )),
                        ]
                      ]
                    : visible
                        .map((f) => _NavItem(
                              feature: f,
                              audience: session.audience,
                              selected: f.key == current,
                              onTap: () {
                                Navigator.pop(context);
                                onSelect(f.key);
                              },
                            ))
                        .toList(),
              ),
            ),
            const Divider(color: Brand.chromeSoft, height: 1),
            ListTile(
              leading: Avatar(name: session.user?.name, photo: session.user?.photo, radius: 15),
              title: Text(session.user?.name ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: Text(session.user?.roles.map(pretty).join(', ') ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.muted, fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right, color: Brand.muted, size: 18),
              onTap: () {
                Navigator.pop(context);
                push(context, const ProfileScreen());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.feature, required this.audience, required this.selected, required this.onTap});
  final Feature feature;
  final Audience audience;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(feature.icon, size: 19, color: selected ? Colors.white : Brand.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      featureLabel(feature, audience),
                      style: TextStyle(
                        color: selected ? Colors.white : const Color(0xFFD1D5DB),
                        fontSize: 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
