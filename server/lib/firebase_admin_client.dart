import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class FirebaseAdminException implements Exception {
  const FirebaseAdminException(this.message);

  final String message;

  @override
  String toString() => 'FirebaseAdminException: $message';
}

class FirebaseAdminClient {
  FirebaseAdminClient({
    required this.credentialsFile,
    required String projectId,
  }) : _projectId = projectId;

  final File credentialsFile;
  final String _projectId;

  static const Duration _timeout = Duration(seconds: 20);

  AutoRefreshingAuthClient? _authClient;

  bool get isConfigured => credentialsFile.existsSync();

  Future<void> setEmailVerified(String uid) async {
    final client = await _obtainAuthClient();
    http.Response resp;
    try {
      resp = await client
          .post(
            Uri.parse('https://identitytoolkit.googleapis.com/v1/projects/'
                '$_projectId/accounts:update'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-User-Project': _projectId,
            },
            body: jsonEncode({'localId': uid, 'emailVerified': true}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const FirebaseAdminException('accounts:update timed out');
    } on http.ClientException catch (e) {
      throw FirebaseAdminException('accounts:update network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final snippet =
          resp.body.length > 300 ? resp.body.substring(0, 300) : resp.body;
      throw FirebaseAdminException(
          'accounts:update HTTP ${resp.statusCode}: $snippet');
    }
  }

  Future<AutoRefreshingAuthClient> _obtainAuthClient() async {
    final existing = _authClient;
    if (existing != null) return existing;
    Map<String, dynamic> saJson;
    try {
      saJson = jsonDecode(await credentialsFile.readAsString())
          as Map<String, dynamic>;
    } catch (e) {
      throw FirebaseAdminException('Cannot read service account file: $e');
    }
    final creds = ServiceAccountCredentials.fromJson(saJson);
    final client = await clientViaServiceAccount(
        creds, const ['https://www.googleapis.com/auth/cloud-platform']);
    _authClient = client;
    return client;
  }
}
