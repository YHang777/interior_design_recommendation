/// Dev helper: prints a valid verification token for curl testing.
///
/// Usage (from server/):
///   VERIFY_TOKEN_SECRET=dev-secret dart run tool/make_token.dart `<uid>` `<email>`
library;

import 'dart:io';

import 'package:interior_design_server/verification_token.dart';

void main(List<String> args) {
  final uid = args.isNotEmpty ? args[0] : 'testuid';
  final email = args.length > 1 ? args[1] : 'you@example.com';
  final secret = Platform.environment['VERIFY_TOKEN_SECRET'] ?? 'dev-secret';
  final token = createVerificationToken(uid: uid, email: email, secret: secret);
  stdout.writeln(token);
}
