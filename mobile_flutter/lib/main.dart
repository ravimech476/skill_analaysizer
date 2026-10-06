import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/session.dart';
import 'screens/login_screen.dart';
import 'shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkillsAnalyzerApp());
}

class SkillsAnalyzerApp extends StatelessWidget {
  const SkillsAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session()..restore(),
      child: MaterialApp(
        title: 'Skills Analyzer',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

/// Shows the splash while the stored session is checked, then the app or the login screen.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (session.loading) {
      return const Scaffold(
        backgroundColor: Brand.chrome,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights, color: Brand.accent, size: 40),
              SizedBox(height: 18),
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          ),
        ),
      );
    }
    return session.signedIn ? const AppShell() : const LoginScreen();
  }
}

/// Shared helper for pushing a sub-screen with its own app bar.
Future<T?> push<T>(BuildContext context, Widget child) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => child));

/// A page with a title bar — every screen opened from a list uses this.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.child, this.actions, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, overflow: TextOverflow.ellipsis),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: Brand.textSoft, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: actions,
        ),
        body: child,
      );
}
