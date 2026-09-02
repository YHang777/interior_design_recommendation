// Tests for the pure 3D-generation decision table (decideGeneration).
//
// The whole pipeline — product save, seller Retry / "Regenerate 3D" actions,
// boot resume of stuck generations — funnels through this one pure function,
// so the billing / downgrade protections are unit-tested here headlessly:
//  - auto kicks never re-submit for a healthy `ready` model;
//  - a persisted task id always means poll-first (never a second paid task);
//  - brand-new Tripo submissions are capped at autoAttemptsCap for AUTOMATIC
//    kicks while explicit seller actions (force) always may submit;
//  - forcing regeneration of a ready Tripo product never downgrades it to the
//    procedural model when the AI route is unavailable.
//
// Pure Dart — no widgets, no Firebase, no filesystem.

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/services/model_generation/generation_decider.dart';

/// decideGeneration with convenient defaults (all "AI route unavailable"
/// flags) so each test only names what matters.
GenerationDecision decide({
  String status = 'none',
  String source = '',
  bool hasTaskId = false,
  int attempts = 0,
  bool dimsComplete = false,
  bool hasNetworkImage = false,
  bool tripoConfigured = false,
  bool force = false,
}) {
  return decideGeneration(
    status: status,
    source: source,
    hasTaskId: hasTaskId,
    attempts: attempts,
    dimsComplete: dimsComplete,
    hasNetworkImage: hasNetworkImage,
    tripoConfigured: tripoConfigured,
    force: force,
  );
}

/// A product that satisfies every AI-route precondition.
GenerationDecision decideEligible({
  String status = 'none',
  String source = '',
  bool hasTaskId = false,
  int attempts = 0,
  bool force = false,
}) {
  return decide(
    status: status,
    source: source,
    hasTaskId: hasTaskId,
    attempts: attempts,
    dimsComplete: true,
    hasNetworkImage: true,
    tripoConfigured: true,
    force: force,
  );
}

void main() {
  group('healthy ready model is never re-kicked automatically', () {
    test('ready Tripo + full eligibility -> none', () {
      final d = decideEligible(status: 'ready', source: 'tripo');
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('already has a 3D model'));
    });

    test('ready procedural + complete dims -> none', () {
      final d = decide(
        status: 'ready',
        source: 'procedural',
        dimsComplete: true,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.none);
    });

    test('ready model with no dims and no AI -> none', () {
      final d = decide(status: 'ready', source: 'procedural');
      expect(d.action, GenerationAction.none);
    });
  });

  group('force-regenerate of a ready model (fix: never downgrade AI)', () {
    test('ready + force + AI route available -> submit a fresh task', () {
      final d = decideEligible(status: 'ready', source: 'tripo', force: true);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('ready procedural + force + AI available -> submit too', () {
      final d =
          decideEligible(status: 'ready', source: 'procedural', force: true);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('ready Tripo + force + Tripo unconfigured -> keep the AI model', () {
      final d = decide(
        status: 'ready',
        source: 'tripo',
        dimsComplete: true,
        hasNetworkImage: true,
        tripoConfigured: false,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
    });

    test('ready Tripo + force + no network image -> keep the AI model', () {
      final d = decide(
        status: 'ready',
        source: 'tripo',
        dimsComplete: true,
        hasNetworkImage: false,
        tripoConfigured: true,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
    });

    test('ready Tripo + force + incomplete dims -> keep the AI model', () {
      final d = decide(
        status: 'ready',
        source: 'tripo',
        dimsComplete: false,
        hasNetworkImage: true,
        tripoConfigured: true,
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('Keeping the current AI model'));
    });

    test('ready procedural + force + no AI + dims -> re-stamp procedural', () {
      final d = decide(
        status: 'ready',
        source: 'procedural',
        dimsComplete: true,
        hasNetworkImage: false,
        force: true,
      );
      expect(d.action, GenerationAction.stampProcedural);
    });

    test('ready procedural + force + no AI + no dims -> keep current', () {
      final d = decide(
        status: 'ready',
        source: 'procedural',
        force: true,
      );
      expect(d.action, GenerationAction.none);
      expect(d.message, contains('set Width/Height/Depth'));
    });
  });

  group('a persisted task id always polls first (never double-bills)', () {
    test('generating + taskId -> pollExistingTask', () {
      final d = decide(
        status: 'generating',
        hasTaskId: true,
        attempts: 1,
        dimsComplete: true,
      );
      expect(d.action, GenerationAction.pollExistingTask);
      expect(d.message, contains('Continuing the generation'));
    });

    test('failed + taskId (transient-cap) -> pollExistingTask', () {
      final d = decide(
        status: 'failed',
        hasTaskId: true,
        attempts: 2,
        dimsComplete: true,
      );
      expect(d.action, GenerationAction.pollExistingTask);
    });

    test('even when the AI route is fully available, polling wins', () {
      final d = decideEligible(
        status: 'generating',
        hasTaskId: true,
        attempts: 1,
      );
      expect(d.action, GenerationAction.pollExistingTask);
    });
  });

  group('automatic submissions are capped (fix: resume cannot bill forever)',
      () {
    test('eligible auto kick, attempts 0 -> submit', () {
      final d = decideEligible(status: 'none');
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('eligible auto kick, attempts 1 (under cap) -> submit', () {
      final d = decideEligible(status: 'none', attempts: 1);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('eligible auto kick at the cap -> no submission (dims -> stamp)',
        () {
      final d = decideEligible(status: 'none', attempts: autoAttemptsCap);
      expect(d.action, GenerationAction.stampProcedural);
      expect(d.message, contains('built-in model'));
    });

    test('capped auto kick on a failed doc -> markFailed with cap message',
        () {
      final d = decideEligible(status: 'failed', attempts: autoAttemptsCap);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });

    test('capped auto kick, no dims -> markFailed with cap message', () {
      final d = decide(
        status: 'none',
        attempts: autoAttemptsCap,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });
  });

  group('an explicit seller action bypasses the cap', () {
    test('force submit beyond the cap is allowed', () {
      final d = decideEligible(
        status: 'none',
        attempts: 7,
        force: true,
      );
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('force retry of a failed doc beyond the cap is allowed', () {
      final d = decideEligible(
        status: 'failed',
        attempts: 7,
        force: true,
      );
      expect(d.action, GenerationAction.submitNewTripo);
    });
  });

  group('explicit retry that cannot reach the AI route', () {
    test('force + no AI + complete dims -> procedural fallback', () {
      final d = decide(
        status: 'none',
        force: true,
        dimsComplete: true,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.stampProcedural);
    });

    test('force + dims missing + photo present -> dims failure message', () {
      final d = decide(
        status: 'failed',
        force: true,
        dimsComplete: false,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('Width/Height/Depth'));
    });

    test('force + dims missing + no photo -> network-image message', () {
      final d = decide(
        status: 'failed',
        force: true,
        dimsComplete: false,
        hasNetworkImage: false,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, needsNetworkImageMessage);
    });
  });

  group('generating docs must not wedge forever', () {
    test('generating + no taskId + capped -> failed with cap message', () {
      final d = decide(
        status: 'generating',
        attempts: autoAttemptsCap,
        dimsComplete: true,
        hasNetworkImage: true,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, autoAttemptsCapMessage);
    });

    test('generating + no taskId + AI unavailable -> failed, explains why',
        () {
      final d = decide(
        status: 'generating',
        attempts: 0,
        dimsComplete: false,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('could not continue'));
    });
  });

  group('failed docs recover with the free generator when possible', () {
    test('failed + dims complete + under cap -> stampProcedural', () {
      final d = decide(
        status: 'failed',
        attempts: 1,
        dimsComplete: true,
        hasNetworkImage: false,
        tripoConfigured: true,
      );
      expect(d.action, GenerationAction.stampProcedural);
      expect(d.message, contains('built-in model'));
    });

    test('failed + dims missing + under cap -> dims failure message', () {
      final d = decide(
        status: 'failed',
        attempts: 0,
        dimsComplete: false,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('Set Width/Height/Depth'));
    });
  });

  group('products with no ar3d record yet', () {
    test('none + dims complete + AI unavailable -> stampProcedural', () {
      final d = decide(
        status: 'none',
        dimsComplete: true,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.stampProcedural);
    });

    test('none + dims complete + AI available + under cap -> submit', () {
      final d = decideEligible(status: 'none', attempts: 0);
      expect(d.action, GenerationAction.submitNewTripo);
    });

    test('none + no dims + under cap -> markNoModel with explanation', () {
      final d = decide(status: 'none', attempts: 0);
      expect(d.action, GenerationAction.markNoModel);
      expect(d.message, contains('No 3D model yet'));
    });
  });

  group('unknown states fall back safely', () {
    test('unknown status + no dims + auto -> markFailed invalid state', () {
      final d = decide(status: 'bogus', attempts: 0, dimsComplete: false);
      expect(d.action, GenerationAction.markFailed);
      expect(d.message, contains('state is invalid'));
    });

    test('unknown status + complete dims -> stampProcedural (no AI)', () {
      final d = decide(
        status: 'bogus',
        attempts: 0,
        dimsComplete: true,
        hasNetworkImage: false,
        tripoConfigured: false,
      );
      expect(d.action, GenerationAction.stampProcedural);
    });
  });
}
