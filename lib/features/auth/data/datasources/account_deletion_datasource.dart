import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../../../core/utils/user_errors.dart';

class DeletionStatus {
  const DeletionStatus({required this.status, this.graceUntil, this.purgeAt});

  final String status;
  final DateTime? graceUntil;
  final DateTime? purgeAt;

  factory DeletionStatus.fromJson(Map<String, dynamic> json) {
    return DeletionStatus(
      status: json['status'] is String ? (json['status'] as String) : 'none',
      graceUntil: _parseDate(json['graceUntil']),
      purgeAt: _parseDate(json['purgeAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  String toString() =>
      'DeletionStatus($status, graceUntil: $graceUntil, purgeAt: $purgeAt)';
}

class AccountDeletionException implements Exception, UserFacingException {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String get userMessage => message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

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

  Future<DeletionStatus> requestDeletion({required String confirmEmail}) {
    return _send(
      method: 'POST',
      path: '/api/account/deletion-request',
      body: {'confirmEmail': confirmEmail},
      fallback: 'Could not start account deletion. Please try again.',
    );
  }

  Future<DeletionStatus> cancelDeletion() {
    return _send(
      method: 'POST',
      path: '/api/account/deletion-request/cancel',
      body: const <String, dynamic>{},
      fallback: 'Could not cancel the deletion request. Please try again.',
    );
  }

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

  String? _serverMessage(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) return error.trim();
      }
    } on FormatException {
    }
    return null;
  }

  String _messageForStatus(int status, String fallback) {
    if (status == 401) return 'Your session expired. Please sign in again.';
    if (status == 503) return 'Account deletion is not available right now.';
    return fallback;
  }
}
