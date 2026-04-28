# iCan Demo Execution Control

## Mission

Ship a 24-hour demo centered on the iCan Eye and voice-controlled self-tuning.
The app must show that a user can talk to iCan and make the system change how it sees, speaks, and behaves.

This is not a production hardening plan. Production-only breadth loses. Demo-critical reliability wins.

## Demo Spine

The accepted demo flow is:

1. App opens with polished iCan splash and lands on a focused Home command center.
2. Home shows Eye status, current vision mode, prompt focus, live verbosity, and voice state.
3. User can trigger voice without relying only on Eye hardware.
4. User says: "only tell me hazards."
5. App visibly and audibly switches to Safety, Brief, and minimal live announcements.
6. User captures or receives an Eye scene description that follows the new prompt settings.
7. User says: "read signs first" or "use local model."
8. App changes settings truthfully and exposes unavailable offline capability instead of pretending.
9. User can repeat the last description.
10. User can contact caretaker through a demo-safe, explicit flow if and only if it is implemented and tested.

## Scope Decisions

Keep:
- Splash.
- Home.
- Settings needed for voice/self-tuning.
- Help only if it supports demo commands.
- Eye pairing/scanning.
- Voice control.
- Scene description.
- Offline/Local mode status and fallback.

Hide or demote:
- Navigation route. It contains TODO/hardcoded navigation.
- GPS route unless cane telemetry is guaranteed.
- Caretaker role entry unless the caretaker command becomes a tested demo flow.
- Standalone Live Detection screen unless YOLO/CoreML models are present and tested.
- Vision diagnostic route stays hidden behind a deliberate developer gesture.

## Current Truth

Verified:
- `scripts/agent_verify.ps1 -SkipPubGet` passes.
- `scripts/agent_verify.ps1 -SkipPubGet -OfflineVision` passes with warnings.
- VoiceControlService parser/action tests pass.
- Settings mutation layer exists for speed, volume, prompt profile, live verbosity, and vision mode.

Not verified:
- Real microphone-to-command flow on device.
- Real Eye BLE capture end to end.
- Out-of-order image chunk handling.
- Offline SmolVLM iOS inference.
- YOLO/depth model availability.
- Caretaker contact.
- Home UI displaying voice state and changed settings.

Known blockers:
- `ios/Frameworks/llama.xcframework` is missing.
- YOLO/depth CoreML models are not proven present in the Runner target.
- Voice command activation depends on Eye double press only.
- `VoiceCommandService.attachRouter` is empty.
- Several voice actions can falsely confirm success when the target no-ops.
- Only 8 tests exist; this is not enough confidence for the demo.

## Workstreams

### Agent A: Voice Command Center

Owner files:
- `lib/services/voice_command_service.dart`
- `lib/services/voice_control_service.dart`
- `lib/screens/accessible_home_screen.dart`
- `lib/main.dart`
- tests under `test/services/` and `test/widgets/`

Tasks:
- Add visible, accessible Home voice trigger.
- Show listening, processing, recognized text, and last command result.
- Make action confirmations truthful when Eye/Home/offline model is unavailable.
- Wire router-dependent actions or remove confirmations that imply navigation.
- Implement demo-safe caretaker command only if it has a visible, tested result.

Acceptance tests:
- Voice command can be triggered without Eye hardware.
- Recognized command mutates settings and speaks exact confirmation.
- Disconnected Eye commands return truthful failure text.
- Home renders listening/processing state and changed mode chips.

### Agent B: Eye and Offline Readiness

Owner files:
- `lib/services/ble_service.dart`
- `lib/protocol/ble_protocol.dart`
- `protocol/ble_protocol.yaml`
- `ios/Runner/*`
- `ios/Runner/EyePipeline/*`
- tests under `test/protocol/` and `test/services/`

Tasks:
- Add tests for protocol parsing and image chunk assembly.
- Require complete expected image length or JPEG EOI before emitting frames.
- Decide CRC story: implement it or remove stale references.
- Make offline mode deterministic: either restore `llama.xcframework` or force a truthful Vision-only/Foundation fallback.
- Hide or disable live detection if object/depth models are missing.

Acceptance tests:
- Ordered chunks produce a JPEG.
- Duplicate chunks do not corrupt a frame.
- Out-of-order/missing/truncated frames are rejected or handled deterministically.
- Offline service reports unavailable dependencies truthfully.

### Agent C: UI Demo Polish

Owner files:
- `lib/screens/splash_screen.dart`
- `lib/screens/accessible_home_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/core/router.dart`
- `lib/core/app_shell.dart`
- tests under `test/widgets/`

Tasks:
- Make Home the command center.
- Show current prompt focus, detail, live verbosity, and vision mode as compact chips.
- Hide weak visible flows for demo.
- Preserve splash identity while respecting reduced motion.
- Keep UI accessible and readable on small iPhone sizes.

Acceptance tests:
- Home disconnected state is clear.
- Home connected/demo mode state exposes Describe, Listen, Repeat, and mode chips.
- Voice listening/processing states render with semantics.
- Settings exposes prompt focus and live verbosity controls.

### Agent D: Verification and Test Harness

Owner files:
- `scripts/agent_verify.ps1`
- `test/**`
- minimal testability seams in `lib/**`

Tasks:
- Add hardware-free tests for protocol, on-device vision channel parsing, settings persistence, voice command orchestration, and Home UI.
- Keep default verification fast.
- Add optional demo preflight profile for iOS/offline/hardware checks.
- Track strict analyzer separately; do not block the 24-hour demo on existing info-level lint debt.

Acceptance tests:
- `scripts/agent_verify.ps1 -SkipPubGet` passes.
- Optional offline preflight prints truthful missing-artifact warnings.
- Tests cover every accepted demo path that can run without hardware.

## Phase Plan

### Phase 0: Control and Baseline

Status: complete.

Outputs:
- Verification script exists and passes.
- VoiceControlService exists and has core tests.
- This control document defines scope and workstreams.

### Phase 1: Make Voice Demoable Without Hardware

Goal:
The user can press a visible Home control, speak a command, and see/hear the app change settings.

Required changes:
- Home Listen button.
- Voice state overlay/pill.
- Last command result.
- Mode chips.
- Truthful no-op failures.
- VoiceCommandService orchestration tests.

Gate:
- Automated tests pass.
- Manual device check: microphone prompt, "only tell me hazards", visible Safety/Brief state.

### Phase 2: Make Eye Capture Trustworthy

Goal:
Eye capture either works end to end or the app exposes a demo fallback without pretending.

Required changes:
- BLE protocol tests.
- Image chunk assembly tests.
- Complete JPEG validation.
- Real Eye smoke checklist.

Gate:
- Automated protocol tests pass.
- Manual Eye checklist passes or fallback mode is enabled.

### Phase 3: Make Offline Truthful

Goal:
Local/offline mode never lies.

Required changes:
- Detect missing SmolVLM/framework/model artifacts.
- Show Local unavailable or Vision-only fallback state.
- Hide live detection screen if YOLO/depth models are absent.

Gate:
- Offline preflight warning is visible and expected.
- App does not claim SmolVLM is running unless the native path is validated.

### Phase 4: Polish the Demo Surface

Goal:
The demo looks intentional.

Required changes:
- Apple-like Home command center.
- Reduce weak route exposure.
- Refine splash motion.
- Add semantics/widget tests for demo states.

Gate:
- Widget tests pass.
- iPhone-size visual check passes.

## Implementation Order

Do this order exactly:

1. Voice Command Center.
2. UI mode chips and visible command state.
3. Protocol/image tests and JPEG validation.
4. Offline truthful fallback.
5. Hide weak routes.
6. Polish splash/home/settings.
7. Run verification.
8. Run real-device smoke checklist.

## Agent Handoff Prompts

### Voice Agent Prompt

You own voice command demoability. Implement a visible Home voice trigger and command state UI. Make commands truthful: no false success when Eye/Home/offline dependencies are unavailable. Add tests for VoiceCommandService orchestration and Home voice state. Do not touch BLE internals or broad UI polish outside Home voice controls.

### Eye Agent Prompt

You own Eye capture reliability. Add protocol/image assembly tests and tighten frame validation. Fix stale CRC references by either implementing CRC or removing claims. Do not touch UI except exposing a truthful unavailable state if necessary.

### UI Agent Prompt

You own demo polish. Make Home the command center with visible mode chips and voice state. Hide weak visible flows for the demo. Preserve accessibility. Add widget/semantics tests. Do not touch BLE internals or voice parser logic.

### Test Agent Prompt

You own confidence. Add missing hardware-free tests, keep `agent_verify.ps1 -SkipPubGet` green, and document any hardware-only checks separately. Do not refactor production code beyond minimal test seams.

## Done Definition

The app is demo-ready only when:
- The accepted demo spine passes.
- Verification passes.
- Missing offline artifacts are handled truthfully.
- Weak routes are hidden.
- A real-device smoke checklist is completed or an explicit fallback is enabled.

