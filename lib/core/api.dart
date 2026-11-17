import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  bool get offline => status == 0;

  @override
  String toString() => message;
}

/// Talks to the CRM workspace API exactly like the web app does: an opaque
/// session cookie plus the workspace Origin header that the server requires
/// on every write. The session lives in the Android Keystore-backed secure
/// store. When the 8-hour session expires the client signs in again with the
/// saved credentials (only when the user chose "Keep me signed in").
class CrmApi {
  CrmApi(this._store);

  final FlutterSecureStorage _store;
  final http.Client _http = http.Client();
  String? _session;
  Future<bool>? _relogin;

  /// Called when the session is gone and cannot be renewed silently.
  void Function()? onSessionLost;

  static const _kSession = 'session';
  static const _kEmail = 'email';
  static const _kPassword = 'password';

  Future<bool> restore() async {
    _session = await _store.read(key: _kSession);
    return _session != null || await _store.read(key: _kPassword) != null;
  }

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('${AppConfig.origin}/api$path');
    return query == null || query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => _request('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _request('POST', path, body: body ?? const {});
  Future<dynamic> patch(String path, Object body) => _request('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _request('PUT', path, body: body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool retry = true,
  }) async {
    if (!AppConfig.isSecureOrigin) {
      throw ApiException(0, 'The CRM workspace must use a secure HTTPS address.');
    }
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Origin': AppConfig.origin,
        if (_session != null) 'Cookie': 'session=$_session',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 25)))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(0, 'The workspace took too long to answer. Check your connection and try again.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'You appear to be offline. Check your internet connection and try again.');
    }

    await _captureSession(res);

    if (res.statusCode == 401 && retry && path != '/auth/login') {
      if (await _renew()) return _request(method, path, body: body, query: query, retry: false);
      onSessionLost?.call();
    }
    if (res.statusCode >= 400) {
      String message = switch (res.statusCode) {
        401 => 'Please sign in to continue.',
        403 => 'You do not have access to this.',
        404 => 'This item could not be found.',
        429 => 'Too many attempts. Please wait a moment and try again.',
        >= 500 => 'The workspace is having trouble right now. Please try again shortly.',
        _ => 'The request could not be completed.',
      };
      try {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        if (data is Map && data['error'] is String && (data['error'] as String).isNotEmpty) {
          message = data['error'] as String;
        }
      } catch (_) {}
      throw ApiException(res.statusCode, message);
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> _captureSession(http.Response res) async {
    final header = res.headers['set-cookie'];
    if (header == null) return;
    final match = RegExp(r'(?:^|[,;]\s*)session=([^;,\s]*)').firstMatch(header);
    if (match == null) return;
    final value = match.group(1) ?? '';
    if (value.isEmpty) {
      _session = null;
      await _store.delete(key: _kSession);
    } else {
      _session = value;
      await _store.write(key: _kSession, value: value);
    }
  }

  Future<CrmUser> login(String email, String password, {required bool remember}) async {
    final data = await _request('POST', '/auth/login', body: {'email': email, 'password': password}, retry: false);
    if (_session == null) throw ApiException(500, 'The workspace did not start a session. Please try again.');
    if (remember) {
      await _store.write(key: _kEmail, value: email);
      await _store.write(key: _kPassword, value: password);
    } else {
      await _store.delete(key: _kPassword);
    }
    return CrmUser.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<String?> savedEmail() => _store.read(key: _kEmail);

  /// One silent sign-in at a time, shared by every request that hit a 401.
  Future<bool> _renew() => _relogin ??= () async {
        try {
          final email = await _store.read(key: _kEmail);
          final password = await _store.read(key: _kPassword);
          if (email == null || password == null) return false;
          await login(email, password, remember: true);
          return true;
        } on ApiException catch (e) {
          // Wrong password now (changed elsewhere): forget it so we stop retrying.
          if (e.status == 401) await _store.delete(key: _kPassword);
          return false;
        } finally {
          _relogin = null;
        }
      }();

  Future<void> logout() async {
    try {
      await _request('POST', '/auth/logout', retry: false);
    } catch (_) {
      // Signing out locally always succeeds.
    }
    _session = null;
    await _store.delete(key: _kSession);
    await _store.delete(key: _kPassword);
  }
}
