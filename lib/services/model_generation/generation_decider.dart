/// PURE decision module for the auto-3D pipeline (no Firebase, no IO — unit
/// testable headless).
///
/// Every entry point of the pipeline — product save, the seller's Retry /
/// Regenerate actions, boot resume of stuck generations — funnels through
/// [decideGeneration] so the whole decision table lives in ONE place and
/// every path is deterministic:
///
///  - a healthy `ready` model is never re-kicked automatically (re-submitting
///    a paid Tripo task on every product edit would burn credits);
///  - a persisted `taskId` means poll THAT task first — polling is free and
///    never submits a second (paid) task for the same request;
///  - brand-new Tripo submissions are capped at [autoAttemptsCap] for
///    AUTOMATIC kicks (a crash/resume loop must not bill a seller
///    repeatedly); an EXPLICIT seller action (`force: true`) always may
///    submit — a human is deciding to spend;
///  - forcing regeneration of a product whose current model is a ready Tripo
///    model NEVER downgrades it to a procedural one when the AI path is not
///    available — the current AI model is kept.
library;

/// What the pipeline should do right now for one product.
enum GenerationAction {
  /// Do nothing — the doc is already in the desired state (healthy `ready`
  /// model, or an explicit regenerate that must keep the current model).
  none,

  /// Re-check the persisted Tripo `taskId` (free, no billing, no new
  /// submission). Used for `generating` docs and `failed` docs that ended on
  /// a transient error.
  pollExistingTask,

  /// Submit a brand-new Tripo image-to-model task (bills credits; increments
  /// `attempts`).
  submitNewTripo,

  /// Mark `ar3d` ready with the built-in generator as source (instant —
  /// geometry materializes on demand in the AR viewer).
  stampProcedural,

  /// Clear `ar3d` back to `none` (no model possible — typically no
  /// dimensions yet).
  markNoModel,

  /// Mark `ar3d` failed with a human-readable reason. `taskId` is kept only
  /// for transient-cap failures (the trigger clears it otherwise).
  markFailed,
}

/// One outcome of [decideGeneration] — the action plus the message the UI
/// should surface for it.
class GenerationDecision {
  const GenerationDecision(this.action, {this.message = ''});

  final GenerationAction action;

  /// Human-readable explanation for `none` / `markFailed` / `markNoModel`
  /// outcomes (shown in the seller's snackbar).
  final String message;

  bool get isNoOp => action == GenerationAction.none;

  @override
  String toString() => 'GenerationDecision($action, "$message")';
}

/// Maximum number of NEW Tripo tasks an AUTOMATIC kick may submit across the
/// product's lifetime. After that the doc is marked failed with
/// [autoAttemptsCapMessage] — a human must decide (Retry / Regenerate) to
/// spend more.
const int autoAttemptsCap = 2;

/// Permanent failure message once automatic attempts are exhausted.
const String autoAttemptsCapMessage = 'Could not generate 3D model — the '
    'automatic attempt limit was reached. Tap Retry or Regenerate to try '
    'one more time.';

/// Message used when the AI route cannot run because the product lacks a
/// public photo (Tripo must fetch the image server-side).
const String needsNetworkImageMessage =
    'AI 3D generation needs a public product photo (network URL).';

/// Decides the next pipeline action for a product snapshot.
///
/// Pure: all inputs are scalars, so the full table is unit-testable without
/// Firebase.
///
/// - [status]: `ar3d.status` or `'none'` when no ar3d record exists.
/// - [source]: `ar3d.source` (`''` | `'procedural'` | `'tripo'`).
/// - [hasTaskId]: whether a Tripo task was persisted and may be re-polled.
/// - [attempts]: how many NEW Tripo tasks have been submitted so far.
/// - [dimsComplete]: the product carries full W×H×D meters.
/// - [hasNetworkImage]: `image` starts with http(s) — Tripo fetches it
///   server-side.
/// - [tripoConfigured]: an API key is configured.
/// - [force]: an EXPLICIT seller action (Retry chip, "Regenerate 3D" menu,
///   re-save with the AI switch on). Bypasses the automatic-attempt cap.
GenerationDecision decideGeneration({
  required String status,
  required String source,
  required bool hasTaskId,
  required int attempts,
  required bool dimsComplete,
  required bool hasNetworkImage,
  required bool tripoConfigured,
  required bool force,
}) {
  final eligible =
      tripoConfigured && hasNetworkImage && dimsComplete;
  final capReached = attempts >= autoAttemptsCap;

  // ── 1. Healthy ready model ─────────────────────────────────────────────
  // Automatic kicks never touch it. An explicit force-regenerate may ask for
  // a fresh model (tripo) or a re-stamp (procedural) — but NEVER downgrades
  // a ready Tripo model to procedural when the AI route is unavailable.
  if (status == 'ready') {
    if (!force) {
      return const GenerationDecision(
        GenerationAction.none,
        message: 'The product already has a 3D model.',
      );
    }
    if (eligible) {
      return const GenerationDecision(
        GenerationAction.submitNewTripo,
        message: 'Submitting a new AI 3D generation task…',
      );
    }
    if (source == 'tripo') {
      return const GenerationDecision(
        GenerationAction.none,
        message: 'Keeping the current AI model — regenerating needs Tripo '
            'configured, a public product photo and complete dimensions.',
      );
    }
    if (dimsComplete) {
      return const GenerationDecision(
        GenerationAction.stampProcedural,
        message: 'Regenerating with the built-in model…',
      );
    }
    return const GenerationDecision(
      GenerationAction.none,
      message: 'Keeping the current model — set Width/Height/Depth to '
          'regenerate it.',
    );
  }

  // ── 2. A persisted Tripo task is always polled first (never re-billed) ──
  if (hasTaskId) {
    return const GenerationDecision(
      GenerationAction.pollExistingTask,
      message: 'Continuing the generation already in progress…',
    );
  }

  // ── 3. A new Tripo submission — automatic only under the attempt cap ────
  if (eligible && (force || !capReached)) {
    return GenerationDecision(
      GenerationAction.submitNewTripo,
      message: force
          ? 'Submitting a new AI 3D generation task…'
          : 'Starting AI 3D generation…',
    );
  }

  // ── 4. Explicit seller retry that cannot reach the AI route ────────────
  if (force) {
    if (dimsComplete) {
      return const GenerationDecision(
        GenerationAction.stampProcedural,
        message: 'AI generation is not available — using the built-in model.',
      );
    }
    if (hasNetworkImage) {
      return const GenerationDecision(
        GenerationAction.markFailed,
        message: 'Retry needs complete Width/Height/Depth (meters).',
      );
    }
    return const GenerationDecision(
      GenerationAction.markFailed,
      message: needsNetworkImageMessage,
    );
  }

  // ── 5. Automatic kicks, AI route unavailable or capped ─────────────────
  if (status == 'generating') {
    // A generation that started but can no longer continue (no task id to
    // poll, no way to submit) must not sit in `generating` forever.
    return GenerationDecision(
      GenerationAction.markFailed,
      message: capReached
          ? autoAttemptsCapMessage
          : 'AI generation could not continue — it needs Tripo configured, '
              'a public product photo and complete dimensions.',
    );
  }

  if (status == 'failed') {
    if (capReached) {
      return const GenerationDecision(
        GenerationAction.markFailed,
        message: autoAttemptsCapMessage,
      );
    }
    if (dimsComplete) {
      // Product is saveable without an AI model — recover with the free
      // deterministic generator (attempts stay under the cap, so a later
      // save with the AI route restored submits again).
      return const GenerationDecision(
        GenerationAction.stampProcedural,
        message: 'AI generation is not available — using the built-in model.',
      );
    }
    return const GenerationDecision(
      GenerationAction.markFailed,
      message: 'Set Width/Height/Depth (meters) to generate the 3D model.',
    );
  }

  // ── 6. No record yet (`none`) or an unknown status ─────────────────────
  if (dimsComplete) {
    return const GenerationDecision(
      GenerationAction.stampProcedural,
      message: 'AI generation is not available — using the built-in model.',
    );
  }
  if (capReached) {
    return const GenerationDecision(
      GenerationAction.markFailed,
      message: autoAttemptsCapMessage,
    );
  }
  if (status == 'none') {
    return const GenerationDecision(
      GenerationAction.markNoModel,
      message: 'No 3D model yet — add real-world Width/Height/Depth '
          '(meters) to generate one.',
    );
  }
  return const GenerationDecision(
    GenerationAction.markFailed,
    message: 'The 3D model state is invalid — edit and save the product '
        'to regenerate it.',
  );
}
