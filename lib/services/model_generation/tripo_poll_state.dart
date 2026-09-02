/// PURE state machine for the Tripo task poll loop (no Firebase, no IO —
/// unit testable headless).
///
/// A poll iteration takes one [PollStep] and the caller (the generator) maps
/// the returned [PollOutcome] onto the product doc:
///
///  outcome                          │ what the generator does
///  ─────────────────────────────────┼────────────────────────────────────────
///  keepPolling                      │ sleep the poll interval, GET again
///  taskSucceeded                    │ download → rescale → upload → `ready`
///  taskFailedTerminal               │ mark `failed` (clear the task id)
///  timedOutLeftRunning              │ NO write — doc stays `generating` with
///                                    │ its task id (the 5-minute deadline ran
///                                    │ out; the server-side task may still
///                                    │ finish and boot-resume re-polls it)
///  transientCapReached              │ mark `failed` but KEEP the task id so an
///                                    │ explicit Retry re-polls the SAME — paid
///                                    │ for — task instead of a new one
///
/// Transient = network failure / timeout / 5xx / malformed reply (anything a
/// retry could plausibly get past). Consecutive transients reset to zero on
/// any well-formed poll reply. After [maxConsecutiveTransientErrors]
/// consecutive transients the poll stops (capped) instead of polling forever.
library;

/// Result of one poll iteration, to be interpreted as in the class doc.
enum PollOutcome {
  keepPolling,
  taskSucceeded,
  taskFailedTerminal,
  timedOutLeftRunning,
  transientCapReached,
}

/// Consecutive transient poll failures allowed before giving up (fix:
/// a flapping network must not poll forever; the task id survives so a later
/// explicit Retry can resume the same task).
const int maxConsecutiveTransientErrors = 4;

/// One step through the poll state machine.
class PollStep {
  const PollStep({
    required this.outcome,
    required this.consecutiveTransients,
    this.terminalError,
  });

  final PollOutcome outcome;

  /// The new consecutive-transient count to carry into the next iteration.
  final int consecutiveTransients;

  /// Human-readable terminal failure reason when
  /// [outcome] == [PollOutcome.taskFailedTerminal].
  final String? terminalError;

  @override
  String toString() => 'PollStep($outcome, transients: '
      '$consecutiveTransients${terminalError == null ? '' : ', "$terminalError"'})';
}

/// Steps the poll state machine.
///
/// Pure — the caller supplies the observed facts of this iteration:
///  - [deadlineReached]: the overall 5-minute budget is spent (checked first:
///    the task is left running server-side and re-polled later);
///  - [lastRequestTransientFailure]: the GET itself failed transiently
///    (network/timeout/5xx/malformed) rather than returning a status;
///  - [taskStatus]: the `data.status` string from a well-formed reply
///    (`queued` | `running` | `success` | `failed` | `cancelled` | unknown);
///  - [errorMessage]: server-reported failure text for terminal outcomes.
///  - [consecutiveTransients]: transients counted so far (0…cap).
PollStep nextPollStep({
  required int consecutiveTransients,
  required bool deadlineReached,
  required bool lastRequestTransientFailure,
  required String taskStatus,
  String? errorMessage,
}) {
  // 1. Time is up — leave the task running server-side.
  if (deadlineReached) {
    return PollStep(
      outcome: PollOutcome.timedOutLeftRunning,
      consecutiveTransients: consecutiveTransients,
    );
  }

  // 2. A transient request failure — count it, stop after the cap.
  if (lastRequestTransientFailure) {
    final next = consecutiveTransients + 1;
    if (next > maxConsecutiveTransientErrors) {
      return PollStep(
        outcome: PollOutcome.transientCapReached,
        consecutiveTransients: next,
        terminalError: 'Tripo is unreachable after '
            '$maxConsecutiveTransientErrors attempts — the task is still '
            'queued server-side. Retry later to check on it (no new charge).',
      );
    }
    return PollStep(
      outcome: PollOutcome.keepPolling,
      consecutiveTransients: next,
    );
  }

  // 3. A well-formed reply resets the transient streak.
  switch (taskStatus) {
    case 'success':
      return const PollStep(
        outcome: PollOutcome.taskSucceeded,
        consecutiveTransients: 0,
      );
    case 'failed':
    case 'cancelled':
      final message = (errorMessage == null || errorMessage.isEmpty)
          ? 'Tripo generation ${taskStatus == 'cancelled' ? 'was cancelled' : 'failed'}'
          : '$errorMessage (task ${taskStatus == 'cancelled' ? 'cancelled' : 'failed'})';
      return PollStep(
        outcome: PollOutcome.taskFailedTerminal,
        consecutiveTransients: 0,
        terminalError: message,
      );
    case 'queued':
    case 'running':
    default:
      // Unknown / not-yet-terminal statuses keep polling.
      return const PollStep(
        outcome: PollOutcome.keepPolling,
        consecutiveTransients: 0,
      );
  }
}
