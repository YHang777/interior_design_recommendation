library;

enum GenerationAction {
  none,

  pollExistingTask,

  submitNewTripo,

  stampProcedural,

  markNoModel,

  markFailed,
}

class GenerationDecision {
  const GenerationDecision(this.action, {this.message = ''});

  final GenerationAction action;

  final String message;

  bool get isNoOp => action == GenerationAction.none;

  @override
  String toString() => 'GenerationDecision($action, "$message")';
}

const int autoAttemptsCap = 2;

const String autoAttemptsCapMessage = '3D generation failed after multiple '
    'attempts. Tap Retry to try again, or edit the product to add '
    'Width/Height/Depth (meters) and a clear product photo.';

const String needsNetworkImageMessage =
    '3D generation needs a clear, public product photo (uploaded as a URL). '
    'Re-upload the image and try again.';

const String tripoUnavailableMessage =
    '3D generation is not set up yet. Try again later.';

const String needsDimensionsMessage =
    '3D generation needs the product size: set Width/Height/Depth (meters) '
    'in the product form. AR will not place a model at a guessed size.';

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
    return GenerationDecision(GenerationAction.markFailed, message: why);
  }

  // ── 5. Automatic kicks that cannot run ─────────────────────────────────
  if (status == 'generating') {
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
