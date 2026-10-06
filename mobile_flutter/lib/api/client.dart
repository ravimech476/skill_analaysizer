import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives. Pass --dart-define=API_URL=... for a real device or a server;
/// the defaults assume the API is on this machine (10.0.2.2 is the host from an Android emulator).
String get apiBaseUrl {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (kIsWeb) return 'http://localhost:8080/api/v1';
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8080/api/v1'
      : 'http://localhost:8080/api/v1';
}

/// Tokens are kept in the platform keystore. The web build has no keystore, so there
/// it falls back to shared preferences — which is what a browser can offer anyway.
class TokenStore {
  static const _access = 'sa.access_token';
  static const _refresh = 'sa.refresh_token';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? accessToken;
  String? refreshToken;

  Future<void> load() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      accessToken = prefs.getString(_access);
      refreshToken = prefs.getString(_refresh);
      return;
    }
    try {
      accessToken = await _secure.read(key: _access);
      refreshToken = await _secure.read(key: _refresh);
    } catch (_) {
      // A reinstall can leave an unreadable entry behind; treat it as signed out.
      accessToken = null;
      refreshToken = null;
    }
  }

  Future<void> save(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_access, access);
      await prefs.setString(_refresh, refresh);
      return;
    }
    await _secure.write(key: _access, value: access);
    await _secure.write(key: _refresh, value: refresh);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_access);
      await prefs.remove(_refresh);
      return;
    }
    await _secure.delete(key: _access);
    await _secure.delete(key: _refresh);
  }
}

/// The API client every screen talks to.
///
/// It attaches the access token, and on a 401 refreshes once and replays the request.
/// Refresh tokens rotate on the server, so two parallel refreshes would look like token
/// theft — concurrent 401s therefore wait on the same future.
class ApiClient {
  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      // Let every status through; failures are turned into ApiException below.
      validateStatus: (_) => true,
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokens.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final path = response.requestOptions.path;
        final isAuthCall = path.startsWith('/auth/') && !path.startsWith('/auth/me');
        if (response.statusCode != 401 || isAuthCall || response.requestOptions.extra['retried'] == true) {
          handler.next(response);
          return;
        }
        final fresh = await _refreshOnce();
        if (fresh == null) {
          onSessionExpired?.call();
          handler.next(response);
          return;
        }
        final options = response.requestOptions
          ..extra['retried'] = true
          ..headers['Authorization'] = 'Bearer $fresh';
        try {
          handler.resolve(await dio.fetch(options));
        } catch (_) {
          handler.next(response);
        }
      },
    ));
  }

  late final Dio dio;
  final tokens = TokenStore();

  /// Called when the refresh token is gone or rejected, so the app can show the login screen.
  void Function()? onSessionExpired;

  Future<String?>? _refreshing;

  Future<String?> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refresh = tokens.refreshToken;
    if (refresh == null) return null;
    try {
      final r = await Dio(BaseOptions(baseUrl: apiBaseUrl))
          .post('/auth/refresh', data: {'refresh_token': refresh});
      final data = r.data['data'] as Map<String, dynamic>;
      await tokens.save(data['access_token'] as String, data['refresh_token'] as String);
      return tokens.accessToken;
    } catch (_) {
      await tokens.clear();
      return null;
    }
  }

  // ---- verbs ----
  // Every call returns the `data` field of the API envelope, or throws ApiException.

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      _unwrap(await dio.get(path, queryParameters: _clean(query)));

  Future<Response<dynamic>> getRaw(String path, {Map<String, dynamic>? query, ResponseType? type}) async {
    final r = await dio.get(path,
        queryParameters: _clean(query), options: Options(responseType: type ?? ResponseType.json));
    if (r.statusCode == null || r.statusCode! >= 400) _throw(r);
    return r;
  }

  Future<dynamic> post(String path, [Object? body]) async => _unwrap(await dio.post(path, data: body));
  Future<dynamic> put(String path, [Object? body]) async => _unwrap(await dio.put(path, data: body));
  Future<dynamic> patch(String path, [Object? body]) async => _unwrap(await dio.patch(path, data: body));
  Future<dynamic> delete(String path) async => _unwrap(await dio.delete(path));

  /// A list endpoint, keeping the pagination meta alongside the rows.
  Future<Paged<Map<String, dynamic>>> list(String path, {Map<String, dynamic>? query}) async {
    final r = await dio.get(path, queryParameters: _clean(query));
    if (r.statusCode == null || r.statusCode! >= 400) _throw(r);
    final body = r.data as Map<String, dynamic>;
    final meta = body['meta'] as Map<String, dynamic>?;
    return Paged(
      rows: ((body['data'] ?? []) as List).cast<Map<String, dynamic>>(),
      total: (meta?['total'] as num?)?.toInt() ?? ((body['data'] ?? []) as List).length,
      page: (meta?['page'] as num?)?.toInt() ?? 1,
      pageSize: (meta?['page_size'] as num?)?.toInt() ?? 20,
      extra: body,
    );
  }

  Future<dynamic> upload(String path, String field, MultipartFile file, {Map<String, dynamic>? fields}) async {
    final form = FormData.fromMap({field: file, ...?_clean(fields)});
    final r = await dio.post(path, data: form,
        options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)));
    return _unwrap(r);
  }

  dynamic _unwrap(Response<dynamic> r) {
    if (r.statusCode == null || r.statusCode! >= 400) _throw(r);
    final body = r.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) return body['data'];
    return body;
  }

  Never _throw(Response<dynamic> r) {
    final body = r.data;
    String message = 'Something went wrong';
    String code = 'error';
    if (body is Map && body['error'] is Map) {
      message = (body['error']['message'] as String?) ?? message;
      code = (body['error']['code'] as String?) ?? code;
    } else if (r.statusCode == 404) {
      message = 'Not found';
    }
    throw ApiException(message, status: r.statusCode ?? 0, code: code);
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && v != '') out[k] = v;
    });
    return out;
  }

  /// Full URL for a signed file link, which the API returns relative to its root.
  String fileUrl(String relative, {bool download = false}) =>
      '$apiBaseUrl$relative${download ? '&download=1' : ''}';
}

class Paged<T> {
  Paged({required this.rows, required this.total, required this.page, required this.pageSize, this.extra});
  final List<T> rows;
  final int total;
  final int page;
  final int pageSize;
  final Map<String, dynamic>? extra;
  bool get hasMore => page * pageSize < total;
}

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = 'error'});
  final String message;
  final int status;
  final String code;
  @override
  String toString() => message;
}

/// A readable message for anything that can come back from a call.
String errorMessage(Object? e) {
  if (e is ApiException) return e.message;
  if (e is DioException) {
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server. Is the API running at $apiBaseUrl?';
    }
    return e.message ?? 'Network error';
  }
  return e?.toString() ?? 'Something went wrong';
}

/// The single client instance the app uses.
final api = ApiClient();
