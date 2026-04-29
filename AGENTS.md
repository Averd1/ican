# iCan Agent Operating Rules

## Demo Priority
- The release blocker is Describe stability on iPhone with iCan Eye.
- Splash must land on Home. Caretaker and role-selection paths stay hidden unless opened through a tested dev path.
- Auto vision mode is cloud-first. Local/native fallback is allowed only after native Vision health checks prove it is usable.

## Workstream Ownership
- Crash/Describe: `lib/models/home_view_model.dart`, `lib/services/scene_description_service.dart`, `lib/services/scene_prompt_builder.dart`, Describe tests.
- BLE/Firmware: `lib/services/ble_service.dart`, `lib/protocol/*`, `protocol/ble_protocol.yaml`, `firmware/ican_eye`, protocol tests.
- UI/Speech: `lib/screens/accessible_home_screen.dart`, `lib/screens/settings_screen.dart`, `lib/screens/splash_screen.dart`, `lib/services/tts_service.dart`, widget/settings tests.
- Verification/CI: `.github/workflows/*`, `scripts/*`, `docs/*`, regression matrix.

Agents should not edit another active workstream unless the task explicitly requires it.

## Forbidden Shortcuts
- Do not mark Eye connected before required Eye notifications are subscribed.
- Do not speak partial Gemini output as a complete scene description.
- Do not enable local/offline vision fallback in Auto when native Vision health is unavailable.
- Do not route startup to caretaker or role selection for the demo path.
- Do not claim hardware validation without real-device notes.

## Required Gates
Run the narrowest relevant tests while working, then run:

```powershell
dart format lib test
flutter test --no-pub
.\scripts\agent_verify.ps1 -SkipPubGet
.\scripts\agent_verify.ps1 -SkipPubGet -OfflineVision
```

Before TestFlight upload also run firmware and iOS gates listed in `docs/regression_matrix.md`.

## Release Automation
- Use `docs/release_pipeline.md` as the source of truth for iOS compile checks and TestFlight releases.
- The Mac release path is GitHub Actions first: push code, then trigger `iOS Compile Check` for Swift/Xcode validation or push an `ios-v<version>-<build>` tag with `.\scripts\release_testflight.ps1 -BuildNumber <build> -Watch` for TestFlight.
- The self-hosted Mac runner must have labels `macOS` and `ican-ios`; do not bypass the runner by committing Mac credentials.
- Secrets belong only in GitHub Actions environment/repository secrets or local untracked shell state. Never print or commit Gemini keys, App Store Connect key material, Apple signing files, SSH keys, passwords, or `.env` files.
- For TestFlight, rely on App Store Connect API key auth through Fastlane. Do not automate raw Apple ID password flows.
- For native iOS/Swift confidence before upload, run `gh workflow run "iOS Compile Check" --repo saberrg/ican --ref main` and watch it with `gh run watch --repo saberrg/ican`.

## Crash Collection
Keep symbolicated crash logs and Apple account output private/local. Store handoff notes without secrets, API keys, Apple IDs, or user data.
