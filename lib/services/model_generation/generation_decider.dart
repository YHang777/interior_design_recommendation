/// PURE decision module for the auto-3D pipeline (no Firebase, no IO — unit
/// testable headless).
///
/// Tripo is the ONLY model source for products: this table no longer decides
/// BETWEEN model sources (that cascade — Tripo → procedural generator →
/// category-default dimensions → bundled catalog — is gone). It decides only
/// what the single pipeline should do right now: SUBMIT a new Tripo task,
/// POLL the persisted task, WAIT, or record a loud failure / no-model state.
///
/// Guarantees, all unit-tested in generation_decision_test.dart:
///  - a healthy `ready` model is never re-kicked automatically (re-submitting
///    a paid Tripo task on every product edit would burn credits);
///  - a persisted `taskId` means poll THAT task first — polling is free and
///    never submits a second (paid) task for the same request;
///  - brand-new Tripo submissions are capped at [autoAttemptsCap] for
///    AUTOMATIC kicks (a crash/resume loop must not bill a seller
///    repeatedly); an EXPLICIT seller action (`force: true`) always may
///    submit — a human is deciding to spend;
///  - an explicit regenerate on a non-eligible product keeps the current
///    ready model instead of clobbering it;
///  - every refusal names the EXACT missing precondition(s) (service, photo,
///    dimensions) so the operator knows what to fix.
library;

/// What the pipeline should do right now for one product.
enum GenerationAction {
  /// Do nothing — the doc is already in the desired state (healthy `ready`
  /// model, or an explicit regenerate that must keep the current model).
  none,

  /// Re-check the persisted Tripo `taskId` (free, no billing, no new
  /// submission). Used for `generating` docs and `failed` docs that still
  /// carry a pollable task.
  pollExistingTask,

  /// Submit a brand-new Tripo image-to-model task (bills credits; increments
  /// `attempts`).
  submitNewTripo,

  /// LEGACY — never produced anymore. Kept only because
  /// `product_management_screen.dart` (supplier UI, outside this change's
  /// ownership) switches exhaustively over [GenerationAction] and would fail
  /// to compile without it. The procedural product-model path was deleted;
  /// do NOT start returning this value.
  stampProcedural,

  /// Clear `ar3d` back to `none` (no model possible — typically no seller
  /// dimensions yet).
  markNoModel,

  /// Mark `ar3d` failed with a human-readable reason. Only chosen when there
  /// is no pollable task left (or the seller must fix a precondition), so
  /// clearing `taskId` here never discards a resumable generation.
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
const String autoAttemptsCapMessage = '3D generation failed after multiple '
    'attempts. Tap Retry to try again, or edit the product to add '
    'Width/Height/Depth (meters) and a clear product photo.';

/// Message used when the AI route cannot run because the product lacks a
/// public photo (Tripo must fetch the image server-side).
const String needsNetworkImageMessage =
    '3D generation needs a clear, public product photo (uploaded as a URL). '
    'Re-upload the image and try again.';

/// Message used when there is no 3D-generation service to call — either this
/// build has no backend URL, or the backend answered "not set up". The Tripo
/// key itself is a server-side env var (TRIPO_API_KEY on Render); a seller
/// cannot set it and is not asked to.
const String tripoUnavailableMessage =
    '3D generation is not set up yet. Try again later.';

/// Message used when the seller declared no dimension at all — AR needs the
/// product's real size and never guesses one.
const String needsDimensionsMessage =
    '3D generation needs the product size: set Width/Height/Depth (meters) '
    'in the product form. AR will not place a model at a guessed size.';

/// Names exactly which precondition(s) are absent, e.g.
/// `'the 3D generation service, Width/Height/Depth (meters)'`.
/// Empty string when nothing is missing.
String missingGenerationReasons({
  required bool tripoConfigured,
  required bool hasNetworkImage,
  required bool hasDimensions,
}) {
  final missing = <String>[];
  if (!tripoConfigured) missing.add('the 3D generation service');
  if (!hasNetworkImage) {
    missing.add('a clear public product photo (image URL)');
  }
  if (!hasDimensions) missing.add('Width/Height/Depth (meters)');
  return missing.join(', ');
}

/// The single, specific message for "these preconditions are missing".
String missingPreconditionsMessage({
  required bool tripoConfigured,
  required bool hasNetworkImage,
  required bool hasDimensions,
}) {
  final missing = missingGenerationReasons(
    tripoConfigured: tripoConfigured,
    hasNetworkImage: hasNetworkImage,
    hasDimensions: hasDimensions,
  );
  if (missing.isEmpty) return '';
  if (!hasDimensions && tripoConfigured && hasNetworkImage) {
    return needsDimensionsMessage;
  }
  if (!tripoConfigured) return '$tripoUnavailableMessage Missing: $missing.';
  if (!hasNetworkImage) return '$needsNetworkImageMessage Missing: $missing.';
  return '3D generation cannot run — missing: $missing.';
}

/// Decides the next pipeline action for a product snapshot.
///
/// Pure: all inputs are scalars, so the full table is unit-testable without
/// Firebase.
///
/// - [status]: `ar3d.status` or `'none'` when no ar3d record exists.
/// - [hasTaskId]: whether a Tripo task was persisted and may be re-polled.
/// - [attempts]: how many NEW Tripo tasks have been submitted so far.
/// - [hasDimensions]: the seller declared at least one of W/H/D > 0 (the
///   rescaler sizes from whichever axes exist; none → refuse).
/// - [hasNetworkImage]: `image` starts with http(s) — Tripo fetches it
///   server-side.
/// - [tripoConfigured]: this build has a 3D-generation backend to call (the
///   Tripo key itself lives in that backend's env, not here).
/// - [force]: an EXPLICIT seller action (Retry chip, "Regenerate 3D" menu,
///   re-save with the AI switch on). Bypasses the automatic-attempt cap.
GenerationDecision decideGeneration({
  required String status,
  required bool hasTaskId,
  required int attempts,
  required bool hasDimensions,
  required bool hasNetworkImage,
  required bool tripoConfigured,
  required bool force,
}) {
  final eligible = tripoConfigured && hasNetworkImage && hasDimensions;
  final capReached = attempts >= autoAttemptsCap;

  // ── 1. Healthy ready model ─────────────────────────────────────────────
  // Automatic kicks never touch it. An explicit force-regenerate submits a
  // fresh Tripo task when eligible; when NOT eligible it keeps the current
  // model (never clobbers a healthy model with a failure) and says which
  // precondition is missing.
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
    return GenerationDecision(
      GenerationAction.none,
      message: 'Keeping the current AI model — regenerating needs: '
          '${missingGenerationReasons(
            tripoConfigured: tripoConfigured,
            hasNetworkImage: hasNetworkImage,
            hasDimensions: hasDimensions,
          )}.',
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
  if (eligible) {
    if (force || !capReached) {
      return GenerationDecision(
        GenerationAction.submitNewTripo,
        message: force
            ? 'Submitting a new AI 3D generation task…'
            : 'Starting AI 3D generation…',
      );
    }
    return const GenerationDecision(
      GenerationAction.markFailed,
      message: autoAttemptsCapMessage,
    );
  }

  // ── 4. Not eligible — every refusal names the missing precondition(s) ──
  final why = missingPreconditionsMessage(
    tripoConfigured: tripoConfigured,
    hasNetworkImage: hasNetworkImage,
    hasDimensions: hasDimensions,
  );
  if (force) {
    // Explicit seller action: record the failure loudly so the chip shows
    // WHY (there is no other model source to settle for).
    return GenerationDecision(GenerationAction.markFailed, message: why);
  }

  // ── 5. Automatic kicks that cannot run ─────────────────────────────────
  if (status == 'generating') {
    // A generation that started but can no longer continue (no task id to
    // poll, no way to submit) must not sit in `generating` forever.
    return GenerationDecision(
      GenerationAction.markFailed,
      message: capReached ? autoAttemptsCapMessage : why,
    );
  }

  if (status == 'failed') {
    return GenerationDecision(
      GenerationAction.markFailed,
      message: capReached ? autoAttemptsCapMessage : why,
    );
  }

  // ── 6. No record yet (`none`) or an unknown status ─────────────────────
  if (status == 'none') {
    return GenerationDecision(
      GenerationAction.markNoModel,
      message: why.isEmpty
          ? 'No 3D model yet — tap Regenerate 3D to create one. Without it, '
              'customers can\'t view this product in AR.'
          : why,
    );
  }
  return GenerationDecision(
    GenerationAction.markFailed,
    message: 'The 3D model state "$status" is invalid — edit and save the '
        'product to regenerate it. Check $why',
  );
}
