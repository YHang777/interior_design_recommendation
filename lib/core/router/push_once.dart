import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
