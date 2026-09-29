import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// An exception whose text is already phrased for the person using the app:
/// short, plain, and free of SDK/stack jargon. UI code may show it as is.
///
/// Exceptions that embed technical detail while they travel up the stack
/// ([MediaStoreException], [VerificationException], …) implement this by
/// returning a *short* [userMessage] — the long form stays available on
/// `message` for logs.
abstract interface class UserFacingException {
  /// Short, plain-language explanation. Never contains SDK or stack text.
  String get userMessage;
}

/// The short, user-safe explanation of [error].
///
/// Never returns `error.toString()`. SDK text like "The supplied auth
/// credential is incorrect, malformed or has expired." is true but useless to
/// a non-technical user, and raw exception dumps leak implementation detail.
/// Unrecognised failures fall back to [fallback], then to a generic line.
String userMessage(Object error, {String? fallback}) {
  if (error is UserFacingException) return error.userMessage;
  if (error is TimeoutException) {
    return 'This is taking too long. Check your connection and try again.';
  }
  if (error is SocketException) {
    return 'No internet connection. Check your network and try again.';
  }
  if (error is http.ClientException) {
    return 'Could not reach the server. Check your connection and try again.';
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
