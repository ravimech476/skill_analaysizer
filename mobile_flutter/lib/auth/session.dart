import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/endpoints.dart';
import '../api/models.dart';
import 'access.dart';

/// Who is signed in, what they may do, and the screens that follows from it.
/// Every screen reads this through `context.watch<Session>()`.
class Session extends ChangeNotifier {
  SessionUser? user;
  bool loading = true;
  int unread = 0;

  bool get signedIn => user != null;
  Audience get audience => audienceOf(user?.roles ?? const []);
  bool get isStaff => audience == Audience.admin || audience == Audience.staff;

  /// True when the user holds ANY of the permissions. Admins bypass, as on the server.
  bool can(List<String> permissions) {
    if (permissions.isEmpty) return true;
    final u = user;
    if (u == null) return false;
    if (u.roles.contains('admin')) return true;
    return permissions.any(u.permissions.contains);
  }

  bool canAll(List<String> permissions) {
    final u = user;
    if (u == null) return false;
    if (u.roles.contains('admin')) return true;
    return permissions.every(u.permissions.contains);
  }

  /// The features this user should see, in menu order.
  List<Feature> get visibleFeatures => features
      .where((f) => can(f.permissions) && (f.audiences == null || f.audiences!.contains(audience)))
      .toList();

  Feature? feature(String key) {
    for (final f in visibleFeatures) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Restores the session on launch: a stored refresh token is enough, because the
  /// client refreshes the access token on the first 401.
  Future<void> restore() async {
    await api.tokens.load();
    api.onSessionExpired = () => signOut(local: true);
    if (api.tokens.accessToken == null && api.tokens.refreshToken == null) {
      loading = false;
      notifyListeners();
      return;
    }
    try {
      user = await authApi.me();
      unawaited(refreshUnread());
    } catch (_) {
      await api.tokens.clear();
      user = null;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _accept(Map<String, dynamic> tokenResponse) async {
    await api.tokens.save(
      tokenResponse['access_token'] as String,
      tokenResponse['refresh_token'] as String,
    );
    user = SessionUser.fromJson((tokenResponse['user'] as Map).cast<String, dynamic>());
    loading = false;
    notifyListeners();
    unawaited(refreshUnread());
  }

  Future<void> signInWithPassword(String username, String password) async =>
      _accept(await authApi.login(username, password));

  Future<void> signInWithOtp(String identifier, String otp) async =>
      _accept(await authApi.verifyOtp(identifier, otp));

  Future<void> signOut({bool local = false}) async {
    final refresh = api.tokens.refreshToken;
    if (!local && refresh != null) {
      try {
        await authApi.logout(refresh);
      } catch (_) {
        // Signing out locally still matters even when the call fails.
      }
    }
    await api.tokens.clear();
    user = null;
    unread = 0;
    loading = false;
    notifyListeners();
  }

  /// Re-reads the profile, e.g. after changing the photo.
  Future<void> reload() async {
    try {
      user = await authApi.me();
      notifyListeners();
    } catch (_) {
      // Keep the current profile; the next call will surface a real failure.
    }
  }

  void setPhoto(FileLink? photo) {
    final u = user;
    if (u == null) return;
    user = SessionUser(
      id: u.id,
      name: u.name,
      username: u.username,
      roles: u.roles,
      permissions: u.permissions,
      photo: photo,
    );
    notifyListeners();
  }

  Future<void> refreshUnread() async {
    if (!signedIn) return;
    try {
      unread = await notificationsApi.unreadCount();
      notifyListeners();
    } catch (_) {
      // A badge is not worth an error.
    }
  }
}
