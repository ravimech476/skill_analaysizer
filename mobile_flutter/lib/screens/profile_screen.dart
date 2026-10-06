import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../auth/access.dart';
import '../auth/session.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/files.dart';

/// The signed-in user's own account: photo, roles, password and where the app points.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    if (user == null) return const SubPage(title: 'My profile', child: EmptyView('Not signed in'));

    return SubPage(
      title: 'My profile',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Avatar(name: user.name, photo: user.photo, radius: 36),
                  const SizedBox(height: 12),
                  Text(user.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(user.username, style: const TextStyle(fontSize: 12.5, color: Brand.textSoft)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: user.roles
                        .map((r) => Tag(pretty(r), color: roleColors[r] ?? Brand.textSoft))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'Photo',
            child: FileSlot(
              category: 'profile_photo',
              current: user.photo,
              onChanged: (fileId, _) async {
                final photo = await filesApi.setMyPhoto(fileId);
                session.setPhoto(photo);
              },
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'Password',
            subtitle: 'Changing it signs you out of other devices the next time they refresh.',
            child: OutlinedButton.icon(
              onPressed: () => showFormSheet<bool>(context, 'Change password', (ctx) => const _PasswordForm()),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Change password'),
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'What you can open',
            child: Column(
              children: session.visibleFeatures
                  .map((f) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(f.icon, size: 18, color: Brand.textSoft),
                        title: Text(featureLabel(f, session.audience), style: const TextStyle(fontSize: 13.5)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'About',
            child: Column(
              children: [
                DetailRow('Server', apiBaseUrl),
                DetailRow('Signed in as', '${user.name} (${user.username})'),
                DetailRow('Permissions', '${user.permissions.length} granted'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Brand.error),
            onPressed: () async {
              if (await confirm(context, 'Log out?', okLabel: 'Log out', danger: true)) {
                await session.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm();

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Field('Current password', child: TextField(controller: _current, obscureText: true)),
          Field('New password', child: TextField(controller: _next, obscureText: true)),
          Field('Confirm new password', child: TextField(controller: _confirm, obscureText: true)),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_next.text != _confirm.text) {
                      toast(context, 'The new passwords do not match', error: true);
                      return;
                    }
                    setState(() => _busy = true);
                    final ok = await runAction(
                      context,
                      () => authApi.changePassword(_current.text, _next.text),
                      success: 'Password changed',
                    );
                    if (mounted) setState(() => _busy = false);
                    if (ok && mounted) Navigator.pop(context, true);
                  },
            child: const Text('Change password'),
          ),
        ],
      );
}
