import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pushes [location] unless we are already there, or a push for it just
/// happened.
///
/// A double-tapped row (two quick taps on the same tools entry) stacks two
/// copies of one page, which trips go_router's duplicate-page-key assertion
/// on the next navigation update. The live router configuration is read at
/// tap time — a snapshot from build would be stale after the first push —
/// and the short debounce covers the window before that first push shows up
/// in the configuration.
void pushOnce(BuildContext context, String location) {
  final now = DateTime.now();
  if (_lastLocation == location &&
      now.difference(_lastPushedAt) < const Duration(milliseconds: 400)) {
    return;
  }

  final router = GoRouter.of(context);
  if (router.routerDelegate.currentConfiguration.uri.toString() == location) {
    return;
  }

  _lastLocation = location;
  _lastPushedAt = now;
  router.push(location);
}

String? _lastLocation;
var _lastPushedAt = DateTime.fromMillisecondsSinceEpoch(0);
