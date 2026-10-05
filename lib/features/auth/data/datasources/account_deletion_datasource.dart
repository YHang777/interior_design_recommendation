import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../../../core/utils/user_errors.dart';

/// One account-deletion status as the backend reports it.
///
/// `status` is one of `none | pending_email | grace | cancelled | purged`.
/// [graceUntil] / [purgeAt] are only present once the emailed link has been
/// confirmed (status `grace`).
class DeletionStatus {
  const DeletionStatus({required this.status, this.graceUntil, this.purgeAt});

  final String status;
  final DateTime? graceUntil;
  final DateTime? purgeAt;

  /// Parses a `{status, graceUntil?, purgeAt?}` body. Unknown or missing
  /// `status` degrades to `'none'`; bad date strings become null rather than
  /// throwing — a banner with no date is better than a crashed fetch.
  factory DeletionStatus.fromJson(Map<String, dynamic> json) {
    return DeletionStatus(
      status: json['status'] is String ? (json['status'] as String) : 'none',
      graceUntil: _parseDate(json['graceUntil']),
      purgeAt: _parseDate(json['purgeAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    // Compare/display in the device's local time — the ISO text from the
    // server carries a `Z` (UTC) suffix.
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  String toString() =>
      'DeletionStatus($status, graceUntil: $graceUntil, purgeAt: $purgeAt)';
}

/// A deletion-flow failure already phrased for the person waiting on it:
/// short, plain, and free of SDK/stack jargon. UI code may show it as is.
class AccountDeletionException implements Exception, UserFacingException {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

/// Talks to the backend's account-deletion endpoints
/// (`{verificationApiUrl}/api/account/...`).
///
/// Authenticated with the signed-in user's Firebase ID token — the only
/// credential this client ever holds. No third-party key lives in the app.
class AccountDeletionDatasource {
  AccountDeletionDatasource({
    http.Client? client,
    Future<String?> Function()? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;

  static const Duration _timeout = Duration(seconds: 20);

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Asks the backend to start deletion. On success the server emails the
  /// user a confirmation link (valid 24h); the account enters the 7-day
  /// grace window only after that link is opened.
  ///
  /// Throws [AccountDeletionException] — e.g. 400 when [confirmEmail] does
  /// not match the account, 409 when a request is already active.
  Future<DeletionStatus> requestDeletion({required String confirmEmail}) {
    return _send(
      method: 'POST',
      path: '/api/account/deletion-request',
      body: {'confirmEmail': confirmEmail},
      fallback: 'Could not start account deletion. Please try again.',
    );
  }

  /// Cancels an active deletion request (pending or grace) and restores
  /// the account — for suppliers, deactivated listings come back too.
  Future<DeletionStatus> cancelDeletion() {
    return _send(
      method: 'POST',
      path: '/api/account/deletion-request/cancel',
      body: const <String, dynamic>{},
      fallback: 'Could not cancel the deletion request. Please try again.',
    );
  }

  /// The signed-in user's current deletion status.
  Future<DeletionStatus> fetchDeletionStatus() {
    return _send(
      method: 'GET',
      path: '/api/account/deletion-status',
      fallback: 'Could not check your account status. Please try again.',
    );
  }

  Future<DeletionStatus> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required String fallback,
  }) async {
    final base = AppConfig.verificationApiUrl.trim();
    if (base.isEmpty) {
      throw const AccountDeletionException(
          'Account deletion is not available in this build.');
    }
    // Fail fast without a token: an unauthenticated call would only earn
    // a 401 from the server.
    final token = await _idTokenProvider();
    if (token == null || token.isEmpty) {
      throw const AccountDeletionException('Please sign in first.');
    }

    http.Response resp;
    try {
      final uri = Uri.parse('$base$path');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      resp = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(_timeout)
          : await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(_timeout);
    } on TimeoutException {
      throw const AccountDeletionException(
          'The server took too long. Please try again.');
    } on http.ClientException catch (e) {
      debugPrint('[deletion] request failed: $e');
      throw const AccountDeletionException(
          'Could not reach the server. Check your connection and try again.');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // Server sentences are user-ready by contract ({error: string});
      // log the body either way so 409s/502s stay diagnosable.
      debugPrint('[deletion] rejected HTTP ${resp.statusCode}: ${resp.body}');
      throw AccountDeletionException(
          _serverMessage(resp) ?? _messageForStatus(resp.statusCode, fallback));
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return DeletionStatus.fromJson(decoded);
    } on FormatException catch (e) {
      debugPrint('[deletion] unparseable body: $e');
    }
    throw AccountDeletionException(fallback);
  }

  /// The backend's `{error: '...'}` sentence, if the body carries one.
  /// The 400/409/502/503 responses all ship one that is safe to show.
  String? _serverMessage(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) return error.trim();
      }
    } on FormatException {
      // Not JSON — fall through to the status-based sentence.
    }
    return null;
  }

  String _messageForStatus(int status, String fallback) {
    if (status == 401) return 'Your session expired. Please sign in again.';
    if (status == 503) return 'Account deletion is not available right now.';
    return fallback;
  }
}
