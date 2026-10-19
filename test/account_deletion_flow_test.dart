import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:interior_design_recommendation/core/utils/user_errors.dart';
import 'package:interior_design_recommendation/features/auth/data/datasources/account_deletion_datasource.dart';
import 'package:interior_design_recommendation/shared/widgets/delete_account_dialogs.dart';

void main() {
  group('kDeleteAccountPhrase matching', () {
    test('exact phrase passes', () {
      expect(deletionPhraseMatches(kDeleteAccountPhrase), isTrue);
    });

    test('mixed case passes', () {
      expect(deletionPhraseMatches('delete my account'), isTrue);
      expect(deletionPhraseMatches('Delete My Account'), isTrue);
    });

    test('extra whitespace passes', () {
      expect(deletionPhraseMatches('  DELETE MY ACCOUNT  '), isTrue);
      expect(deletionPhraseMatches('\tDELETE MY ACCOUNT\n'), isTrue);
    });

    test('wrong phrase fails', () {
      expect(deletionPhraseMatches(''), isFalse);
      expect(deletionPhraseMatches('DELETE'), isFalse);
      expect(deletionPhraseMatches('DELETE MY ACCOUNTS'), isFalse);
      expect(deletionPhraseMatches('delete my  account'), isFalse);
      expect(deletionPhraseMatches('MY ACCOUNT'), isFalse);
    });
  });

  group('AccountDeletionException', () {
    test('userMessage returns the short message', () {
      const e = AccountDeletionException('That email does not match.');
      expect(e.userMessage, 'That email does not match.');
      expect('$e', contains('AccountDeletionException'));
    });

    test('userMessage(e, fallback) prefers the exception text', () {
      const e = AccountDeletionException('Please sign in first.');
      expect(userMessage(e, fallback: 'generic fallback'),
          'Please sign in first.');
    });

    test('userMessage falls back for unrecognised errors', () {
      expect(userMessage(StateError('raw sdk text'), fallback: 'fallback'),
          'fallback');
      expect(userMessage(StateError('raw sdk text')), contains('wrong'));
    });
  });

  group('DeletionStatus.fromJson', () {
    test('parses status and dates (UTC converted to local)', () {
      final status = DeletionStatus.fromJson({
        'status': 'grace',
        'graceUntil': '2026-10-12T00:00:00Z',
        'purgeAt': '2026-10-12T00:00:00Z',
      });
      expect(status.status, 'grace');
      expect(status.graceUntil, isNotNull);
      expect(status.purgeAt, isNotNull);
      expect(status.purgeAt!.toUtc(),
          DateTime.parse('2026-10-12T00:00:00Z').toUtc());
    });

    test('missing dates stay null', () {
      final status =
          DeletionStatus.fromJson({'status': 'pending_email'});
      expect(status.status, 'pending_email');
      expect(status.graceUntil, isNull);
      expect(status.purgeAt, isNull);
    });

    test('unknown or missing status degrades to none', () {
      expect(DeletionStatus.fromJson({}).status, 'none');
      expect(DeletionStatus.fromJson({'status': 42}).status, 'none');
      expect(
          DeletionStatus.fromJson({
            'status': 'grace',
            'purgeAt': 'not-a-date',
          }).purgeAt,
          isNull);
    });
  });

  group('AccountDeletionDatasource', () {
    AccountDeletionDatasource build(
      Future<http.Response> Function(http.Request request) handler, {
      Future<String?> Function()? idTokenProvider,
    }) {
      return AccountDeletionDatasource(
        client: MockClient(handler),
        idTokenProvider: idTokenProvider ?? () async => 'tok-123',
      );
    }

    test('requestDeletion posts confirmEmail with a Bearer token', () async {
      http.Request? seen;
      final ds = build((req) async {
        seen = req;
        return http.Response(
          '{"status":"pending_email","expiresAt":"2026-10-06T10:00:00Z"}',
          200,
        );
      });

      final status =
          await ds.requestDeletion(confirmEmail: 'me@example.com');

      expect(status.status, 'pending_email');
      expect(seen, isNotNull);
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/account/deletion-request');
      expect(seen!.headers['Authorization'], 'Bearer tok-123');
      expect(jsonDecode(seen!.body), {'confirmEmail': 'me@example.com'});
    });

    test('cancelDeletion posts to the cancel path', () async {
      http.Request? seen;
      final ds = build((req) async {
        seen = req;
        return http.Response('{"status":"cancelled"}', 200);
      });

      final status = await ds.cancelDeletion();

      expect(status.status, 'cancelled');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/api/account/deletion-request/cancel');
      expect(seen!.headers['Authorization'], 'Bearer tok-123');
    });

    test('fetchDeletionStatus parses grace dates', () async {
      final ds = build((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/account/deletion-status');
        return http.Response(
          '{"status":"grace",'
          '"graceUntil":"2026-10-12T00:00:00Z",'
          '"purgeAt":"2026-10-12T00:00:00Z"}',
          200,
        );
      });

      final status = await ds.fetchDeletionStatus();

      expect(status.status, 'grace');
      expect(status.purgeAt!.toUtc(),
          DateTime.parse('2026-10-12T00:00:00Z').toUtc());
    });

    test('400 surfaces the server error sentence', () async {
      final ds = build((req) async =>
          http.Response('{"error":"That email does not match this account."}',
              400));

      await expectLater(
        ds.requestDeletion(confirmEmail: 'x@y.z'),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage',
            'That email does not match this account.')),
      );
    });

    test('409 without a sentence falls back to the short message', () async {
      final ds = build((req) async => http.Response('nope', 409));

      await expectLater(
        ds.cancelDeletion(),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage',
            'Could not cancel the deletion request. Please try again.')),
      );
    });

    test('503 maps to an availability sentence', () async {
      final ds = build((req) async => http.Response('{}', 503));

      await expectLater(
        ds.requestDeletion(confirmEmail: 'a@b.c'),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage',
            'Account deletion is not available right now.')),
      );
    });

    test('network failure maps to a friendly message', () async {
      final ds = build((req) async => throw http.ClientException('down'));

      await expectLater(
        ds.fetchDeletionStatus(),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage',
            'Could not reach the server. Check your connection and try again.')),
      );
    });

    test('missing token fails fast', () async {
      final ds = build((req) async => http.Response('{}', 200),
          idTokenProvider: () async => null);

      await expectLater(
        ds.requestDeletion(confirmEmail: 'a@b.c'),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage', 'Please sign in first.')),
      );
    });

    test('unparseable 200 body falls back to the generic sentence', () async {
      final ds = build((req) async => http.Response('<html>', 200));

      await expectLater(
        ds.requestDeletion(confirmEmail: 'a@b.c'),
        throwsA(isA<AccountDeletionException>().having(
            (e) => e.userMessage, 'userMessage',
            'Could not start account deletion. Please try again.')),
      );
    });
  });

  group('showDeleteAccountFlow', () {
    Future<void> pumpHost(
      WidgetTester tester, {
      required void Function(Future<bool> flow) onFlow,
      String confirmEmail = 'me@example.com',
      Future<void> Function(String email)? onSubmit,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  onFlow(showDeleteAccountFlow(
                    context,
                    confirmEmail: confirmEmail,
                    onSubmit: onSubmit ?? (_) async {},
                  ));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    Future<Finder> openConfirmDialog(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsOneWidget,
          reason: 'dialog 1 (warning) must show first');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm deletion'), findsOneWidget,
          reason: 'dialog 2 (type-to-confirm) must follow the warning');
      return find.widgetWithText(ElevatedButton, 'Request deletion');
    }

    testWidgets(
        'confirm stays disabled until the phrase matches, then submits',
        (tester) async {
      String? submittedEmail;
      Future<bool>? flow;
      await pumpHost(
        tester,
        onFlow: (f) => flow = f,
        onSubmit: (email) async => submittedEmail = email,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('order history'), findsOneWidget,
          reason: 'the warning must say what is kept');
      expect(find.textContaining('7 days'), findsOneWidget,
          reason: 'the warning must say the recovery window');
      expect(find.textContaining('24 hours'), findsOneWidget,
          reason: 'the warning must say the link lifetime');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm deletion'), findsOneWidget);
      final confirm = find.widgetWithText(ElevatedButton, 'Request deletion');
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(confirm).onPressed,
        isNull,
        reason: 'confirm must be disabled before the phrase is typed',
      );

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull,
          reason: 'a wrong phrase must not arm confirm');

      await tester.enterText(find.byType(TextField), '  delete my account ');
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(confirm).onPressed,
        isNotNull,
        reason: 'the matching phrase must arm confirm',
      );

      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(await flow, isTrue);
      expect(submittedEmail, 'me@example.com',
          reason: 'onSubmit must receive the confirmEmail');
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancelling the warning dialog resolves false', (tester) async {
      var submitted = false;
      Future<bool>? flow;
      await pumpHost(
        tester,
        onFlow: (f) => flow = f,
        onSubmit: (_) async => submitted = true,
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await flow, isFalse);
      expect(submitted, isFalse);
    });

    testWidgets('empty email aborts before any dialog', (tester) async {
      Future<bool>? flow;
      await pumpHost(tester, onFlow: (f) => flow = f, confirmEmail: '');

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('No email on file.'), findsOneWidget);
      expect(await flow, isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('submission failure shows a friendly snackbar, resolves false',
        (tester) async {
      Future<bool>? flow;
      await pumpHost(
        tester,
        onFlow: (f) => flow = f,
        onSubmit: (_) async => throw Exception('raw backend text'),
      );

      final confirm = await openConfirmDialog(tester);
      await tester.enterText(find.byType(TextField), 'DELETE MY ACCOUNT');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(await flow, isFalse);
      expect(
        find.text('Could not start account deletion. Please try again.'),
        findsOneWidget,
        reason: 'raw exception text must never surface; only the fallback',
      );
      expect(find.textContaining('Exception'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
