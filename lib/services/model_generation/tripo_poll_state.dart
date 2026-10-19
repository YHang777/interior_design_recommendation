library;

enum PollOutcome {
  keepPolling,
  taskSucceeded,
  taskFailedTerminal,
  timedOutLeftRunning,
  transientCapReached,
}

const int maxConsecutiveTransientErrors = 4;

class PollStep {
  const PollStep({
    required this.outcome,
    required this.consecutiveTransients,
    this.terminalError,
  });

  final PollOutcome outcome;

  final int consecutiveTransients;

  final String? terminalError;

  @override
  String toString() => 'PollStep($outcome, transients: '
      '$consecutiveTransients${terminalError == null ? '' : ', "$terminalError"'})';
}

PollStep nextPollStep({
  required int consecutiveTransients,
  required bool deadlineReached,
  required bool lastRequestTransientFailure,
  required String taskStatus,
  String? errorMessage,
}) {
  if (deadlineReached) {
    return PollStep(
      outcome: PollOutcome.timedOutLeftRunning,
      consecutiveTransients: consecutiveTransients,
    );
  }

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
      return const PollStep(
        outcome: PollOutcome.keepPolling,
        consecutiveTransients: 0,
      );
  }
}
