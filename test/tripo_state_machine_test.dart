// Tests for the pure Tripo poll-loop state machine (nextPollStep).
//
// The generator's poll loop calls nextPollStep once per iteration with the
// observed facts (deadline / transient failure / server status) and maps the
// returned PollOutcome onto the product doc:
//  - the 5-minute deadline is checked FIRST and leaves the doc `generating`
//    with its task id (server-side task may still finish; boot-resume re-polls
//    the same task — free);
//  - consecutive transient failures count and, after
//    maxConsecutiveTransientErrors, stop the loop (task id survives so an
//    explicit Retry re-polls the same — already paid for — task);
//  - any well-formed reply resets the transient streak;
//  - `success` / `failed` / `cancelled` are terminal; everything else keeps
//    polling.
//
// Pure Dart — no widgets, no Firebase, no filesystem.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/model_generation/tripo_poll_state.dart';

/// nextPollStep with convenient defaults for a healthy iteration.
PollStep step({
  int consecutiveTransients = 0,
  bool deadlineReached = false,
  bool lastRequestTransientFailure = false,
  String taskStatus = 'running',
  String? errorMessage,
}) {
  return nextPollStep(
    consecutiveTransients: consecutiveTransients,
    deadlineReached: deadlineReached,
    lastRequestTransientFailure: lastRequestTransientFailure,
    taskStatus: taskStatus,
    errorMessage: errorMessage,
  );
}

void main() {
  group('the deadline is checked first (fix: 5-minute budget leaves the '
      'task running)', () {
    test('deadline + terminal-looking status -> timedOut, no terminal write',
        () {
      final s = step(deadlineReached: true, taskStatus: 'success');
      expect(s.outcome, PollOutcome.timedOutLeftRunning);
      expect(s.terminalError, isNull);
    });

    test('deadline + server failure status -> timedOut (never fails a doc '
        'whose task may still be billed)', () {
      final s = step(deadlineReached: true, taskStatus: 'failed');
      expect(s.outcome, PollOutcome.timedOutLeftRunning);
    });

    test('deadline + transient request failure -> timedOut', () {
      final s = step(
        deadlineReached: true,
        lastRequestTransientFailure: true,
      );
      expect(s.outcome, PollOutcome.timedOutLeftRunning);
    });

    test('deadline keeps the consecutive-transient count for the next poll',
        () {
      final s = step(deadlineReached: true, consecutiveTransients: 3);
      expect(s.outcome, PollOutcome.timedOutLeftRunning);
      expect(s.consecutiveTransients, 3);
    });
  });

  group('transient request failures count and cap (fix: no infinite flapping '
      'poll)', () {
    test('first transient -> keepPolling with count 1', () {
      final s = step(lastRequestTransientFailure: true);
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 1);
    });

    test('transient at 3 consecutive -> keepPolling with count 4', () {
      final s = step(
        consecutiveTransients: 3,
        lastRequestTransientFailure: true,
      );
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 4);
    });

    test('4th consecutive transient (5th hit) -> transientCapReached', () {
      final s = step(
        consecutiveTransients: maxConsecutiveTransientErrors,
        lastRequestTransientFailure: true,
      );
      expect(s.outcome, PollOutcome.transientCapReached);
      expect(s.consecutiveTransients, maxConsecutiveTransientErrors + 1);
      expect(s.terminalError, contains('Retry later'));
      expect(s.terminalError, contains('no new charge'));
    });

    test('transient takes precedence over a stale status field', () {
      final s = step(
        lastRequestTransientFailure: true,
        taskStatus: 'success',
      );
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 1);
    });
  });

  group('well-formed replies reset the transient streak', () {
    test('after two transients, a queued reply -> keepPolling with count 0',
        () {
      final s = step(
        consecutiveTransients: 2,
        taskStatus: 'queued',
      );
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 0);
    });

    test('after two transients, running resets the streak too', () {
      final s = step(
        consecutiveTransients: 2,
        taskStatus: 'running',
      );
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 0);
    });
  });

  group('success is terminal', () {
    test('success -> taskSucceeded, streak reset, no error', () {
      final s = step(
        consecutiveTransients: 2,
        taskStatus: 'success',
      );
      expect(s.outcome, PollOutcome.taskSucceeded);
      expect(s.consecutiveTransients, 0);
      expect(s.terminalError, isNull);
    });
  });

  group('server terminal failures', () {
    test('failed without a message -> default failure text', () {
      final s = step(taskStatus: 'failed');
      expect(s.outcome, PollOutcome.taskFailedTerminal);
      expect(s.consecutiveTransients, 0);
      expect(s.terminalError, 'Tripo generation failed');
    });

    test('failed with a message -> message + "(task failed)"', () {
      final s = step(taskStatus: 'failed', errorMessage: 'Bad mesh');
      expect(s.outcome, PollOutcome.taskFailedTerminal);
      expect(s.terminalError, contains('Bad mesh'));
      expect(s.terminalError, contains('(task failed)'));
    });

    test('cancelled without a message -> default cancellation text', () {
      final s = step(taskStatus: 'cancelled');
      expect(s.outcome, PollOutcome.taskFailedTerminal);
      expect(s.terminalError, 'Tripo generation was cancelled');
    });

    test('cancelled with a message -> message + "(task cancelled)"', () {
      final s = step(
        taskStatus: 'cancelled',
        errorMessage: 'User aborted',
      );
      expect(s.outcome, PollOutcome.taskFailedTerminal);
      expect(s.terminalError, contains('User aborted'));
      expect(s.terminalError, contains('(task cancelled)'));
    });
  });

  group('still-pending statuses keep polling', () {
    test('queued -> keepPolling', () {
      expect(step(taskStatus: 'queued').outcome, PollOutcome.keepPolling);
    });

    test('running -> keepPolling', () {
      expect(step(taskStatus: 'running').outcome, PollOutcome.keepPolling);
    });

    test('unknown status -> keepPolling (treats it as not-yet-terminal)', () {
      final s = step(taskStatus: 'processing');
      expect(s.outcome, PollOutcome.keepPolling);
      expect(s.consecutiveTransients, 0);
    });
  });
}
