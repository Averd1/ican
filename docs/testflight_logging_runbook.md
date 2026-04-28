# TestFlight Logging Runbook

## What This Build Captures

- Dart `debugPrint` output is captured into a 400-line local ring buffer.
- The same sanitized lines are forwarded to iOS unified logging through
  subsystem `com.icannavigation.app`, category `AppLog`.
- The Vision Diagnostic dev screen has `Copy App Logs` for handoff when the
  device is not connected to a Mac.
- API keys, bearer tokens, and Gemini query-key patterns are redacted before
  persistence or iOS logging.

Do not add image bytes, screenshots, raw Gemini request bodies, Apple account
data, or API keys to app logs.

## Live Logs From A Connected iPhone

Apple TestFlight crash reports are not live stdout. For live logs, connect the
iPhone to the remote Mac and stream device logs.

Preferred GUI path:

1. Connect and trust the iPhone on the Mac.
2. Open Console.app.
3. Select the iPhone under Devices.
4. Start streaming.
5. Filter for `subsystem:com.icannavigation.app` or `AppLog`.

CLI path when `devicectl` is available:

```bash
xcrun devicectl list devices
xcrun devicectl device log stream --device <DEVICE_UUID> \
  --predicate 'subsystem == "com.icannavigation.app" OR eventMessage CONTAINS "AppLog"'
```

Save logs locally on the Mac:

```bash
mkdir -p "$HOME/ican_logs"
xcrun devicectl device log stream --device <DEVICE_UUID> \
  --predicate 'subsystem == "com.icannavigation.app" OR eventMessage CONTAINS "AppLog"' \
  > "$HOME/ican_logs/build_23_live.log"
```

## Crash Reports

- Keep the uploaded archive at `build/ios/archive/Runner.xcarchive`.
- TestFlight crash reports are available through Xcode Organizer and App Store
  Connect feedback. They may lag behind the real device event.
- If Organizer does not show the crash, collect device diagnostics directly from
  the iPhone or ask the tester to submit TestFlight feedback.

## Manual Tester Handoff

If live streaming is not possible:

1. Open the hidden Vision Diagnostic dev path.
2. Tap `Copy App Logs`.
3. Paste the copied logs into a private note or message.
4. Include build number, iOS version, Eye firmware version, and exact action
   sequence. Do not include secrets or Apple account data.
