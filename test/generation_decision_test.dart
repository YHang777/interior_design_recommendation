// Tests for the pure pipeline decision table (decideGeneration).
//
// Tripo is the ONLY model source — there is no procedural generator and no
// bundled-catalog fallback to decide between anymore. The table decides what
// the SINGLE pipeline does right now: submit a new Tripo task, re-poll a
// persisted one, wait, or record a loud failure / no-model state. The
// billing protections are unit-tested here headlessly:
//  - auto kicks never re-submit for a healthy `ready` model;
//  - a persisted task id always means poll-first (never a second paid task);
//  - brand-new Tripo submissions are capped at autoAttemptsCap for AUTOMATIC
//    kicks while explicit seller actions (force) always may submit;
//  - every refusal names the EXACT missing precondition (API key, photo,
//    dimensions) — never a vague "no model available";
//  - stampProcedural is never produced (the action only survives as a
//    legacy enum value for the supplier screen's exhaustive switch).
//
// Pure Dart — no widgets, no Firebase, no filesystem.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/model_generation/generation_decider.dart';

/// decideGeneration with convenient defaults (every precondition missing)
/// so each test only names what matters.
GenerationDecision decide({
  String status = 'none',
  bool hasTaskId = false,
  int attempts = 0,
  bool hasDimensions = false,
  bool hasNetworkImage = false,
  bool tripoConfigured = false,
  bool force = false,
}) {
  return decideGeneration(
    status: status,
    hasTaskId: hasTaskId,
    attempts: attempts,
    hasDimensions: hasDimensions,
    hasNetworkImage: hasNetworkImage,
    tripoConfigured: tripoConfigured,
    force: force,
  );
}

/// A product that satisfies every precondition (key + photo + at least one
/// seller dimension).
GenerationDecision decideEligible({
  String status = 'none',
  bool hasTaskId = false,
  int attempts = 0,
  bool force = false,
}) {
  return decide(
    status: status,
    hasTaskId: hasTaskId,
    attempts: attempts,
    hasDimensions: true,
    hasNetworkImage: true,
    tripoConfigured: true,
    force: force,
  );
}

void main() {
  group('healthy ready model is never re-kicked automatically', () {
    test('ready + full eligibility -> none', () {
      final d = decideEligible(status: 'ready');
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('already has a 3D model'));
    });

    test('ready + nothing configured -> still none (no automatic work)', () {
      final d = decide(status: 'ready');
      expect(d.action, GenerationAction.none);
    });

    test('ready + partial dims -> none', () {
      final d = decide(
        status: 'ready',
        hasDimensions: true,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.none);
    });
  });

  group('force-regenerate of a ready model', () {
    test('ready + force + eligible -> submit a fresh task', () {
      final d = decideEligible(status: 'ready', force: true);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('ready + force + no API key -> KEEP the model, name the key', () {
      final d = decide(
        status: 'ready',
        hasDimensions: true,
        hasNetworkImage: true,
        tripoConfigured: false,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
      expect(d.message, contains('TRIPO_API_KEY'));
    });

    test('ready + force + no network image -> KEEP, name the photo', () {
      final d = decide(
        status: 'ready',
        hasDimensions: true,
        hasNetworkImage: false,
        tripoConfigured: true,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
      expect(d.message, contains('photo'));
    });

    test('ready + force + no seller dimensions -> KEEP, name the dims', () {
      final d = decide(
        status: 'ready',
        hasDimensions: false,
        hasNetworkImage: true,
        tripoConfigured: true,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
      expect(d.message, contains('Width/Height/Depth'));
    });
  });

  group('a persisted task id always polls first (never double-bills)', () {
    test('generating + taskId -> pollExistingTask', () {
      final d = decide(
        status: 'generating',
        hasTaskId: true,
        attempts: 1,
        hasDimensions: true,
      );
      expect(d.action, GenerationAction.pollExistingTask);
      expect(d.message, contains('Continuing the generation'));
    });

    test('failed + taskId (transient-cap / timeout) -> pollExistingTask',
        () {
      final d = decide(
        status: 'failed',
        hasTaskId: true,
        attempts: 2,
        hasDimensions: true,
      );
      expect(d.action, GenerationAction.pollExistingTask);
    });

    test('even when every precondition is met, polling wins over submit',
        () {
      final d = decideEligible(
        status: 'generating',
        hasTaskId: true,
        attempts: 1,
      );
      expect(d.action, GenerationAction.pollExistingTask);
    });

    test('force + taskId still polls (an explicit retry re-checks the '
        'already-paid task)', () {
      final d = decideEligible(
        status: 'failed',
        hasTaskId: true,
        attempts: 1,
        force: true,
      );
      expect(d.action, GenerationAction.pollExistingTask);
    });
  });

  group('automatic submissions are capped (resume cannot bill forever)',
      () {
    test('eligible auto kick, attempts 0 -> submit', () {
      final d = decideEligible(status: 'none');
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('eligible auto kick, attempts 1 (under cap) -> submit', () {
      final d = decideEligible(status: 'none', attempts: 1);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('eligible auto kick at the cap -> markFailed with cap message',
        () {
      final d = decideEligible(status: 'none', attempts: autoAttemptsCap);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });

    test('capped auto kick on a failed doc -> markFailed with cap message',
        () {
      final d = decideEligible(status: 'failed', attempts: autoAttemptsCap);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });

    test('capped auto kick with missing dims -> markNoModel naming the dims',
        () {
      // The cap only guards SUBMISSIONS. With no seller dimensions nothing
      // could be submitted anyway, so the honest outcome is "no model" plus
      // the exact missing precondition — not a vague cap failure.
      final d = decide(
        status: 'none',
        attempts: autoAttemptsCap,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markNoModel);
      expect(d.message, needsDimensionsMessage);
      expect(d.message, contains('Width/Height/Depth'));
    });
  });

  group('an explicit seller action bypasses the cap', () {
    test('force submit beyond the cap is allowed', () {
      final d = decideEligible(status: 'none', attempts: 7, force: true);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('force retry of a failed doc beyond the cap is allowed', () {
      final d = decideEligible(status: 'failed', attempts: 7, force: true);
      expect(d.action, GenerationAction.submitNewTripo);
    });
  });

  group('refusals name the exact missing precondition', () {
    test('force + no API key -> key message', () {
      final d = decide(
        status: 'failed',
        force: true,
        hasDimensions: true,
        hasNetworkImage: true,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.markFailed);
      // The message is the constant plus a "Missing: …" tail naming the
      // precondition(s) precisely.
      expect(d.message, startsWith(needsTripoKeyMessage));
      expect(d.message, contains('Missing: TRIPO_API_KEY'));
    });

    test('force + no seller dimensions -> dimensions message', () {
      final d = decide(
        status: 'failed',
        force: true,
        hasDimensions: false,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, needsDimensionsMessage);
      expect(d.message, contains('Width/Height/Depth'));
    });

    test('force + no network image -> photo message', () {
      final d = decide(
        status: 'failed',
        force: true,
        hasDimensions: true,
        hasNetworkImage: false,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, startsWith(needsNetworkImageMessage));
      expect(d.message, contains('Missing: a clear public product photo'));
    });

    test('force + several missing -> message lists every one', () {
      final d = decide(status: 'failed', force: true);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('TRIPO_API_KEY'));
      expect(d.message, contains('Width/Height/Depth'));
      expect(d.message, contains('photo'));
    });
  });

  group('generating docs must not wedge forever', () {
    test('generating + no taskId + capped -> failed with cap message', () {
      final d = decide(
        status: 'generating',
        attempts: autoAttemptsCap,
        hasDimensions: true,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });

    test('generating + no taskId + preconditions gone -> failed, explains '
        'why', () {
      final d = decide(
        status: 'generating',
        attempts: 0,
        hasDimensions: false,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, isNotEmpty);
      expect(d.message, contains('TRIPO_API_KEY'));
    });
  });

  group('products with no ar3d record yet', () {
    test('none + eligible + under cap -> submit', () {
      final d = decideEligible(status: 'none', attempts: 0);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('none + no dimensions (everything else fine) -> markNoModel with '
        'the dimensions message', () {
      final d = decide(
        status: 'none',
        attempts: 0,
        hasDimensions: false,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markNoModel);
      expect(d.message, needsDimensionsMessage);
    });

    test('none + dims + no key -> markNoModel naming the key', () {
      final d = decide(
        status: 'none',
        attempts: 0,
        hasDimensions: true,
        hasNetworkImage: true,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.markNoModel);
      expect(d.message, contains('TRIPO_API_KEY'));
    });
  });

  group('unknown states fall back safely', () {
    test('unknown status + no preconditions -> markFailed invalid state',
        () {
      final d = decide(status: 'bogus', attempts: 0, hasDimensions: false);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('invalid'));
      expect(d.message, contains('bogus'));
    });

    test('unknown status + eligible -> submit (the pipeline can still '
        'run)', () {
      final d = decideEligible(status: 'bogus', attempts: 0);
      expect(d.action, GenerationAction.submitNewTripo);
    });
  });

  group('stampProcedural is never produced', () {
    test('no combination of inputs returns the legacy procedural action',
        () {
      final statuses = ['none', 'generating', 'ready', 'failed', 'bogus'];
      for (final status in statuses) {
        for (final hasTaskId in [false, true]) {
          for (final attempts in [0, 1, 99]) {
            for (final hasDimensions in [false, true]) {
              for (final force in [false, true]) {
                final d = decide(
                  status: status,
                  hasTaskId: hasTaskId,
                  attempts: attempts,
                  hasDimensions: hasDimensions,
                  hasNetworkImage: true,
                  tripoConfigured: true,
                  force: force,
                );
                expect(
                  d.action,
                  isNot(GenerationAction.stampProcedural),
                  reason: 'the procedural model source was deleted — '
                      'status=$status taskId=$hasTaskId attempts=$attempts '
                      'dims=$hasDimensions force=$force',
                );
              }
            }
          }
        }
      }
    });
  });
}
