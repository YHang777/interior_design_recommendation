import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

abstract interface class UserFacingException {
  String get userMessage;
}

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
