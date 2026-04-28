# iCan Agent Handoff

Use this file when starting a fresh Codex session on the iCan app.

## Current State

- Repo: `C:\Users\17733\ican`
- Current iOS build uploaded to App Store Connect: `1.0.0+22`
- Current TestFlight purpose: validate Eye-to-phone BLE image transfer, voice-first command control, scene description quality, and visible diagnostics.
- Build 22 is the post-crash hotfix for build 21:
  - App Store Connect showed build 21 as `VALID` but had no fresh build-21 crash submissions immediately after the user-reported crash.
  - Apple returned only older April 7 crash submissions for app build `1.0.0 (2)`, with a launch-time plugin-registration crash in `AppDelegate.didInitializeImplicitFlutterEngine`.
  - `main.dart` now guards notification, TTS, and STT startup individually and installs a zone error handler before `runApp`.
  - `TtsService.init()` and `resetSpeechDefaults()` now treat native Flutter TTS setup as best-effort, log exact native failures, and keep the app bootable.
  - Build 22 uploaded from the remote Mac on April 27, 2026 with Delivery UUID `cd1043d3-60e8-4083-90ba-42b7a712ebda`.
- Build 21 uploaded from the remote Mac on April 27, 2026 and includes the reliability rebuild:
  - Native vision channel registers from the scene lifecycle after `FlutterViewController` exists, with double-registration protection.
  - Describe defaults to cloud Gemini reliable mode, accumulates complete output before speaking, and retries/report cuts for truncated responses.
  - `VisionHealthService` reports native, Apple Vision, model, cloud, Eye, and blocking reason status.
  - Live Detection has full mode plus degraded Basic Live Mode for Apple Vision OCR/person/scene cues when YOLO/depth are not healthy.
  - Speech engine supports native iOS, ElevenLabs Worker proxy, and auto fallback; TestFlight build uses native iOS fallback unless a Worker URL is supplied.
  - App Store Connect upload used API-key auth from private continuity notes, a locally created iOS Distribution certificate, and a fresh App Store provisioning profile.
  - Upload succeeded with Delivery UUID `b5debe3a-06d0-4e44-b6ad-7feec2859b91`; App Store Connect may still need Apple-side processing before TestFlight shows the build.
- Build 12 uploaded from the remote Mac on April 27, 2026 and includes all Build 11 changes plus:
  - Native SmolVLM GGUF downloader validates exact file sizes and SHA-256 hashes for `SmolVLM-500M-Instruct-Q8_0.gguf` and `mmproj-SmolVLM-500M-Instruct-Q8_0.gguf`.
  - Downloader checks available storage, marks model files excluded from device backup, reports true `downloading` status, and surfaces progress through the Dart event channel.
  - Vision diagnostic screen has a SmolVLM setup panel with Refresh, Download, Load, verified file size, status, and progress.
  - Direct SmolVLM diagnostic now fails clearly when model files are missing instead of silently falling back to the vision-only template.
  - Mac focused tests, iOS debug compile, release archive, and App Store Connect upload all passed for build 12.
- Build 11 uploaded from the remote Mac on April 27, 2026 and includes all Build 10 changes plus:
  - `ios/Frameworks/llama.xcframework` built from remote `~/Desktop/llama.cpp` and committed locally under `ios/Frameworks/`.
  - Runner target links `llama.xcframework` in Debug, Profile, and Release via `$(PROJECT_DIR)/Frameworks`.
  - Release archive verified to compile the real `canImport(llama)` SmolVLM branch; fallback "framework not linked" strings were absent from the archived binary.
- Build 10 uploaded from the remote Mac on April 27, 2026 and includes:
  - Voice command parser fix for `stop live detection` plus natural phrases for describe, safety, reading, detail, local/cloud/auto vision, speech speed, and stop talking.
  - Safe `VoiceIntentResolver` cascade: deterministic rules first, optional local/cloud fallback only through allowlisted `VoiceActionType` values.
  - STT partial/error/no-speech state and safer TTS failure handling.
  - Native TTS voice enumeration, enhanced Apple voice preference, voice choice, pitch, speed, and preview controls.
  - `ScenePromptBuilder` prompt contracts for Brief, Rich, Scene, Safety, Navigation, and Reading modes.
  - Gemini streaming preservation plus `finishReason` capture for `MAX_TOKENS`.
  - Home command-center chips and bottom sheets for Focus, Detail, Vision Source, Voice, and Speech Style.
  - Core ML model diagnostics surfaced through Dart/Swift and truthful Live Detection unavailable wording.
  - Visible label updates: `Detailed` -> `Rich`, `Balanced` -> `Scene`, `Vision only` -> `Local basic vision`, `Auto` -> `Auto: best available`.
- Build 9 included:
  - Home-screen `Latest Vision Diagnostic` panel with selectable/copyable exact error text.
  - BLE image assembler fixes for chunks arriving before `SIZE:`.
  - Duplicate `END` notification ignored after a completed frame.
  - FlutterBluePlus Eye notifications set up with `onValueReceived`, `cancelWhenDisconnected`, then `setNotifyValue(true)`.
  - Gemini restricted iOS API key support using `X-Ios-Bundle-Identifier`.

Important existing docs:
- `docs/agent_brain.md`
- `docs/demo_execution_control.md`
- `docs/ican_eye_vision_architecture.md`
- `docs/OFFLINE_VISION_VERIFICATION.md`

Private details are intentionally not in this repo doc. Use:

`C:\Users\17733\.codex\memories\ican_private_continuity.md`

Do not paste secrets into final answers, tracked docs, GitHub, or TestFlight notes.

## Verification Gates

Run these from repo root after code changes:

```powershell
dart format lib test
flutter test --no-pub
.\scripts\agent_verify.ps1 -SkipPubGet
```

Known current behavior:
- `agent_verify.ps1 -SkipPubGet` exits 0.
- Analyzer reports many info-level style/deprecation lints. They are existing noise, not a failing gate.

Firmware compile:

```powershell
cd C:\Users\17733\ican\firmware\ican_eye
py -m platformio run -e xiao_esp32s3
```

Firmware flash to the Seeed XIAO ESP32-S3 on COM5:

```powershell
cd C:\Users\17733\ican\firmware\ican_eye
py -m platformio run -e xiao_esp32s3 -t upload --upload-port COM5
```

Last known firmware flash succeeded on COM5. Board MAC printed during upload was `90:70:69:12:53:bc`.

## BLE Protocol

Source of truth:

`protocol/ble_protocol.yaml`

Critical Eye commands:
- `CAPTURE`
- `LIVE_START:{intervalMs}`
- `LIVE_STOP`
- `PROFILE:{index}`
- `STATUS`

Critical Eye control events:
- `CAPTURE:START`
- `SIZE:{bytes}`
- `CRC:{hex}`
- `END:{chunks}`
- `ERR:CAMERA_CAPTURE_FAILED`
- `ERR:STREAM_ABORTED:{sentChunks}:{sentBytes}:{expectedBytes}`
- `ERR:CHUNK_NOTIFY_FAILED:{sequence}`
- `BUTTON:DOUBLE`

App-side implementation:
- `lib/protocol/ble_protocol.dart`
- `lib/protocol/eye_capture_diagnostics.dart`
- `lib/services/ble_service.dart`
- `lib/models/home_view_model.dart`
- `lib/screens/accessible_home_screen.dart`

Firmware-side implementation:
- `firmware/ican_eye/src/main.cpp`
- `firmware/ican_eye/lib/ble_eye/ble_eye.cpp`
- `firmware/shared/include/ble_protocol.h`

Important BLE rules:
- Keep `SIZE`, chunk packets, `CRC`, and `END` compatible with existing firmware.
- iOS can deliver notifications from the image and control characteristics out of order.
- Firmware repeats `END` three times; app must not turn duplicate `END` into a corrupt JPEG diagnostic.
- Use `characteristic.onValueReceived`, not `lastValueStream`, for image assembly.
- For Eye notifications, subscribe first, call `device.cancelWhenDisconnected(subscription)`, then call `setNotifyValue(true)`.
- Cancel old Eye subscriptions on reconnect/disconnect.
- Log MTU safely; iOS does not allow explicit MTU requests the same way Android does.

Current diagnostic codes:
- `Eye E01`: no capture start or `SIZE` from Eye.
- `Eye E02`: image stream stalled, including received/expected byte counts.
- `Eye E03`: corrupt or incomplete JPEG.
- `Eye E04`: CRC mismatch.
- `Eye E05`: firmware reported camera capture failure.
- `Cloud C01`: missing API key/config.
- `Cloud C02`: Gemini HTTP status failure, including status code.
- `Cloud C03`: cloud timeout/network failure.
- `Local L01`: Apple Vision/Core ML failure.

Build 9 shows the latest diagnostic visibly on the Home screen. Use that panel for hardware debugging instead of relying only on TTS.

## Google API Setup

Project:

`ican-490920`

Enabled APIs known relevant:
- `generativelanguage.googleapis.com`
- `aiplatform.googleapis.com`
- `serviceusage.googleapis.com`

Current Gemini API key:
- Display name: `iCan iOS Gemini restricted`
- UID: `692efa07-b2a3-43ad-87c0-5c39c762ea56`
- API restriction: `generativelanguage.googleapis.com`
- iOS bundle restriction: `com.icannavigation.app`

Old key:
- Display name: `API key 1`
- UID: `b2d0ca06-62c6-4028-a430-16a498123cff`
- Status: deleted on 2026-04-27 after replacement.

Retrieve the current key string without printing it:

```powershell
$env:ICAN_RESTRICTED_KEY = gcloud services api-keys get-key-string `
  692efa07-b2a3-43ad-87c0-5c39c762ea56 `
  --project=ican-490920 `
  --location=global `
  --format='value(keyString)'
```

The app must be built with:

```text
--dart-define=API_KEY="$ICAN_RESTRICTED_KEY"
--dart-define=IOS_BUNDLE_IDENTIFIER=com.icannavigation.app
```

The app sends `X-Ios-Bundle-Identifier: com.icannavigation.app` from `VertexAiService`. That header is required for the iOS-restricted API key.

Validation pattern:
- Request with the iOS bundle header should return HTTP `200`.
- Same key without the iOS bundle header should return HTTP `403`.

The class is named `VertexAiService`, but the current app endpoint is Gemini Developer API:

`https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`

Do not switch to Vertex AI OAuth/service-account auth inside the iOS app. If Vertex AI is required later, use a backend proxy.

## Remote Mac Build Machine

Remote Mac usage is required for iOS archive/upload.

Non-secret facts:
- Repo path on Mac: `/Users/user293913/ican`
- Flutter path on Mac: `/Users/user293913/flutter/bin/flutter`
- CocoaPods installed user-local under `~/.gem/ruby/2.6.0/bin`
- App Store Connect signing credential exists on the Mac under `~/.appstoreconnect/private_keys/`.
- App Store Connect API key ID and issuer ID are stored only in private continuity notes.
- Build 21 upload used manual IPA export plus `xcrun altool --upload-app` with App Store Connect API-key auth.
- The Mac keychain now has a local `iPhone Distribution: Saber Garibi (YP6X8QPR44)` identity created through the App Store Connect Certificates API.
- IPA output path: `/Users/user293913/ican/build/ios/ipa/iCan.ipa`
- Archive path: `/Users/user293913/ican/build/ios/archive/Runner.xcarchive`

Sensitive host/user/password details are in:

`C:\Users\17733\.codex\memories\ican_private_continuity.md`

Recommended remote build command after pushing changed files to the Mac:

```bash
export PATH="$HOME/flutter/bin:$HOME/.gem/ruby/2.6.0/bin:$PATH"
export ICAN_API_KEY="<retrieved restricted key>"
cd "$HOME/ican"
flutter pub get
rm -rf build/ios/archive build/ios/ipa
flutter build ipa \
  --release \
  --build-number=<next_build_number> \
  --export-method app-store \
  --dart-define=API_KEY="$ICAN_API_KEY" \
  --dart-define=IOS_BUNDLE_IDENTIFIER=com.icannavigation.app
```

Recommended upload command on the Mac after manual export:

```bash
cd "$HOME/ican"
xcrun altool --upload-app \
  -f "$HOME/ican/build/ios/ipa/iCan.ipa" \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" \
  --p8-file-path "$ASC_P8_FILE_PATH"
```

Expected success line:

`UPLOAD SUCCEEDED with no errors`

## TestFlight And Hardware Acceptance

Do not call the BLE fix complete until it is proven on real phone plus Eye hardware.

Acceptance for each "describe the scene" attempt:
- Either a real scene description is spoken and shown, or
- The Home screen shows an exact diagnostic code with stage/bytes/chunks/cloud/local status.

Minimum hardware pass:
- Flash current firmware.
- Install latest TestFlight build.
- Use Balanced profile.
- Run at least 3 consecutive `describe the scene` captures.
- Cloud-only mode must either describe via Gemini or show/speak exact cloud failure.

If it fails:
1. Read/copy the Home-screen `Latest Vision Diagnostic`.
2. If `Eye E02`, focus on byte counts and chunk counts.
3. If `Eye E03`, inspect JPEG start/end validity.
4. If `Eye E04`, compare expected and actual CRC.
5. If `Cloud C02`, inspect status code and API key/header setup.

## Recent Files Changed For Build 9

- `lib/protocol/eye_capture_diagnostics.dart`
- `lib/services/ble_service.dart`
- `lib/models/home_view_model.dart`
- `lib/screens/accessible_home_screen.dart`
- `test/protocol/eye_capture_diagnostics_test.dart`
- `test/widgets/accessible_home_voice_command_test.dart`
- `pubspec.yaml`

## Security Rules

- Never commit new API keys, Mac passwords, App Store credentials, or Google service-account material.
- Keep API keys build-time only via `--dart-define`.
- Keep Mac credentials in the local private memory file only.
- Before final answers, do not echo raw secrets.
- Before commits/pushes, run a credential scan for API keys, auth tokens, passwords, and signing material.
- Treat any match in tracked files as a blocker unless it is already-known historical material that the user explicitly accepts.
