# iCan — Technical Briefing for QA Review

*Generated: 2026-04-21*

---

## 1. Project Overview

- **App name:** iCan
- **Bundle ID:** `com.example.ican` (default Flutter placeholder — not changed for production)
- **Version:** 1.0.0+3
- **Description:** iCan is an assistive navigation system for visually impaired users. The Flutter mobile app communicates over BLE 5.0 with two ESP32 hardware devices: the **iCan Cane** (sensors, haptics, GPS) and the **iCan Eye** (camera). The app provides real-time scene description (via AI vision models — cloud and on-device), obstacle/hazard alerts, turn-by-turn navigation, telemetry monitoring, and a caretaker dashboard with fall detection. The entire UI is designed accessibility-first with WCAG AAA compliance, full VoiceOver/TalkBack support, and a voice-driven interaction model.
- **Target platform:** iOS (production target). Android, Windows, macOS, Linux, and Web platform directories exist, but iOS is the intended production platform. Windows is used for desktop BLE testing only.
- **Minimum iOS version:** Not explicitly set in Info.plist (inherits Flutter default — typically iOS 12+). Some features (Apple Foundation Models) require iOS 26+.
- **Supported devices:** iPhone. iPad orientations are configured separately.
- **Orientations:** Portrait, Landscape Left, Landscape Right (iPhone). All four orientations on iPad.
- **Xcode project structure:** Standard Flutter-generated `ios/Runner.xcworkspace` with a single `Runner` target. No app extensions (no widgets, no watch app, no share extension). Scene-based lifecycle via `SceneDelegate.swift`. Native Swift code in `ios/Runner/` and `ios/Runner/EyePipeline/` for on-device ML inference.

---

## 2. Tech Stack & Dependencies

### Language(s)

- **Dart** (SDK ^3.11.1) — all app logic
- **Swift** — native iOS platform channel code (6 Swift files in `ios/Runner/`, 6 in `ios/Runner/EyePipeline/`)
- **C** — llama.cpp inference engine (bridged via `Runner-Bridging-Header.h`)

### UI Framework

**Flutter Material** exclusively. No SwiftUI or UIKit views beyond the Flutter engine shell. All screens are Material widgets with extensive `Semantics` wrapping.

### Architecture Pattern

**MVVM** (Model-View-ViewModel) with Provider.

Evidence:
- `HomeViewModel` (`lib/models/home_view_model.dart`) — primary ViewModel for the home screen, extends `ChangeNotifier`
- `SettingsProvider` (`lib/models/settings_provider.dart`) — ViewModel for settings, extends `ChangeNotifier`
- `DeviceState` (`lib/models/device_state.dart`) — app-wide device state model, extends `ChangeNotifier`
- ViewModels are injected into the widget tree via `ChangeNotifierProvider` in the router (`lib/core/router.dart`)
- Services are singletons or injected via constructor

### Dependency Manager

**pub** (Dart's built-in package manager, via `pubspec.yaml`). No CocoaPods Podfile was found committed. iOS native dependencies appear to be handled via SwiftPM or manual inclusion.

### Third-Party Libraries

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_blue_plus` | 1.33.0 | BLE communication (iOS/Android/macOS) |
| `win_ble` | ^1.1.1 | BLE communication (Windows desktop testing) |
| `flutter_tts` | ^4.2.0 | Text-to-Speech — all voice output |
| `speech_to_text` | ^7.0.0 | Speech-to-Text — voice commands (stub, not yet implemented) |
| `go_router` | ^14.0.0 | Declarative routing with `StatefulShellRoute` |
| `provider` | ^6.1.2 | State management (ChangeNotifier + Provider) |
| `shared_preferences` | ^2.2.0 | Local key-value persistence |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `flutter_dotenv` | ^6.0.0 | Environment variable loading (`.env` file) |
| `http` | ^1.6.0 | HTTP client for Gemini API calls |
| `image` | ^4.5.0 | JPEG decoding/encoding, image enhancement in isolate |
| `flutter_local_notifications` | ^18.0.0 | OS-level fall detection push notifications |
| `path_provider` | ^2.1.0 | File system paths for model storage |
| `objective_c` | 9.1.0 | Objective-C interop (required by some Flutter plugins) |
| `flutter_screenutil` | ^5.9.3 | Responsive sp/dp scaling |
| `flutter_lints` | ^6.0.0 | (dev) Lint rules |
| `flutter_launcher_icons` | ^0.14.3 | (dev) App icon generation |

### Apple Frameworks in Use (via native Swift code)

- **Vision** — OCR, scene classification, human/body detection
- **CoreML** — Moondream 2B VLM, Depth Anything V2, YOLOv3
- **Foundation Models** — Apple's on-device LLM (iOS 26+)
- **CoreBluetooth** — (via flutter_blue_plus)
- **AVFoundation** — (via flutter_tts audio session)
- **Metal** — GPU acceleration for llama.cpp inference

---

## 3. Architecture & Code Organization

### Top-Level Folder Structure

```
lib/
  main.dart                         — App entry point, initializes notifications, runs ICanApp
  core/
    app_router.dart                 — Legacy named-route map (Navigator.pushNamed-based)
    app_shell.dart                  — Bottom tab bar shell (3 tabs: Home, Settings, Help)
    route_constants.dart            — Central Routes class (paths, names, tab indices, screen titles)
    router.dart                     — Active GoRouter configuration with StatefulShellRoute
    theme.dart                      — WCAG AAA design system (AppColors, AppSpacing, ICanTheme)
  models/
    device_state.dart               — ChangeNotifier for cane/eye connection + telemetry state
    home_view_model.dart            — Primary ViewModel: BLE streams, image processing, TTS, description history
    settings_provider.dart          — ChangeNotifier for all user preferences (audio, descriptions, accessibility)
  protocol/
    ble_protocol.dart               — BLE UUIDs, opcodes, packet codecs (mirrors ble_protocol.yaml)
  screens/
    accessible_home_screen.dart     — Main home screen (GoRouter tab 0) — accessibility-first
    caretaker_dashboard_screen.dart — Heart rate, battery, fall detection for caretakers
    connection_error_screen.dart    — BLE connection failure recovery
    device_pairing_screen.dart      — Full-screen BLE pairing flow
    gps_screen.dart                 — Live GPS data from cane
    help_screen.dart                — In-app help & troubleshooting (GoRouter tab 2)
    home_screen.dart                — Legacy home screen (pre-accessibility rewrite)
    nav_screen.dart                 — Placeholder turn-by-turn navigation
    role_selection_screen.dart      — User vs Caretaker role picker
    settings_screen.dart            — Full settings (GoRouter tab 1)
    splash_screen.dart              — Animated splash with BLE auto-connect
  services/
    ble_service.dart                — Singleton BLE manager (~1400 lines), dual-device, image assembly
    connectivity_service.dart       — DNS-based internet reachability check
    device_prefs_service.dart       — SharedPreferences wrapper for saved device IDs
    model_download_service.dart     — VLM model download lifecycle with TTS progress
    nav_service.dart                — Navigation service stub (Mapbox placeholder)
    notification_service.dart       — flutter_local_notifications wrapper for fall alerts
    on_device_vision_service.dart   — Dart client for native Swift MethodChannel (Vision + VLM + FM)
    scene_description_service.dart  — Unified multi-backend scene description with priority fallback
    stt_service.dart                — Speech-to-text service stub (not implemented)
    tts_service.dart                — flutter_tts wrapper with platform-specific audio config
    vertex_ai_service.dart          — Gemini API client (3 model tiers, streaming SSE)
  widgets/
    accessible_button.dart          — Full Semantics button with haptic, focus ring, disabled state
    audio_description_tile.dart     — Dismissible description history tile with swipe gestures
    device_status_card.dart         — BLE device connection/battery status card
    hazard_alert_banner.dart        — Slide-in obstacle alert overlay with auto-dismiss
```

### Module/Layer Breakdown

| Layer | Files |
|-------|-------|
| **Presentation** | `screens/`, `widgets/`, `core/app_shell.dart` |
| **ViewModel** | `models/home_view_model.dart`, `models/settings_provider.dart`, `models/device_state.dart` |
| **Domain/Service** | `services/scene_description_service.dart`, `services/nav_service.dart`, `services/model_download_service.dart` |
| **Data/Communication** | `services/ble_service.dart`, `services/vertex_ai_service.dart`, `services/on_device_vision_service.dart`, `services/connectivity_service.dart`, `services/device_prefs_service.dart` |
| **Protocol** | `protocol/ble_protocol.dart` |
| **Theme/Config** | `core/theme.dart`, `core/router.dart`, `core/route_constants.dart` |

### Dependency Injection Approach

- **Constructor injection** for service dependencies (e.g., `HomeViewModel` receives `SceneDescriptionService` and `TtsService` via constructor)
- **Provider** for widget-tree injection (`ChangeNotifierProvider` wraps screens in the router)
- **Singletons** for infrastructure services: `BleService.instance`, `DevicePrefsService.instance`

### Concurrency Model

- **`async`/`await`** for all asynchronous operations
- **`Stream`** and `StreamController.broadcast()` for real-time BLE data (obstacle, telemetry, image, GPS, capture)
- **`compute()` isolate** for CPU-intensive image enhancement (`_enhanceImageForApi` in `home_view_model.dart`)
- **`EventChannel`** for native→Dart streaming (VLM tokens, FM tokens, download progress)
- No Combine, no GCD, no actors on the Dart side

### State Management

**Provider + ChangeNotifier** throughout:
- `HomeViewModel` — home screen state (processing, paused, description history, BLE streams)
- `SettingsProvider` — all user preferences
- `DeviceState` — device connection/telemetry (not currently used in GoRouter path; superseded by direct `BleService.instance` access)
- `BleService` itself extends `ChangeNotifier` and widgets listen directly via `addListener`

---

## 4. Features (Complete List)

### 4.1 BLE Device Management
- **User-facing:** Scan, connect, auto-reconnect to iCan Cane and iCan Eye over BLE 5.0
- **Key files:** `services/ble_service.dart`, `screens/device_pairing_screen.dart`
- **Notable logic:** Platform-specific BLE transport (flutter_blue_plus vs win_ble), auto-reconnect on disconnect (3s delay), hardcoded Windows fallback device ID `90:70:69:12:53:BD`, device ID persistence via `DevicePrefsService`

### 4.2 AI Scene Description
- **User-facing:** Camera captures a scene, AI describes it aloud via TTS
- **Key files:** `services/scene_description_service.dart`, `services/vertex_ai_service.dart`, `services/on_device_vision_service.dart`, `models/home_view_model.dart`
- **Notable logic:** Five-tier priority fallback (Cloud Gemini → Apple Foundation Models → Moondream CoreML → SmolVLM llama.cpp → Vision-only template). Streaming SSE for cloud. Sentence-splitting TTS loop. Image enhancement in isolate (contrast, sharpening, black bar cropping). Deduplication by fingerprint within 2-second windows.

### 4.3 Obstacle/Hazard Alerts
- **User-facing:** Real-time haptic + audio alerts when cane detects obstacles
- **Key files:** `widgets/hazard_alert_banner.dart`, `protocol/ble_protocol.dart` (`ObstacleSide`, `ObstacleAlert`)
- **Notable logic:** Slide-in banner with auto-dismiss (5s normal, 10s with screen reader active), direction labels (left/right/ahead/above), distance labels (feet/meters), haptic vibrate on show

### 4.4 Telemetry Monitoring
- **User-facing:** Battery level, heart rate, fall detection from cane
- **Key files:** `protocol/ble_protocol.dart` (`TelemetryPacket`), `services/ble_service.dart`, `screens/caretaker_dashboard_screen.dart`
- **Notable logic:** 6-byte little-endian telemetry packet, fall detection rising-edge tracking, OS-level notifications on fall

### 4.5 Caretaker Dashboard
- **User-facing:** Remote monitoring of heart rate, battery, fall history
- **Key files:** `screens/caretaker_dashboard_screen.dart`
- **Notable logic:** Animated heartbeat icon, HR range bar (40-180 BPM), fall alert dialog with acknowledgment, session-based fall history log, debug telemetry strip

### 4.6 Turn-by-Turn Navigation
- **User-facing:** Walking directions with haptic feedback via cane
- **Key files:** `screens/nav_screen.dart`, `services/nav_service.dart`
- **Notable logic:** **Stub implementation only.** NavService returns placeholder steps. Mapbox API key is `YOUR_MAPBOX_API_TOKEN`. No real geocoding or directions API integration exists yet.

### 4.7 GPS Monitoring
- **User-facing:** Live GPS data from cane (coordinates, altitude, speed, satellites)
- **Key files:** `screens/gps_screen.dart`, `protocol/ble_protocol.dart` (`GpsPacket`)
- **Notable logic:** 19-byte GPS packet (float32 lat/lon/alt/speed, uint8 sats/quality/valid), 1 Hz updates

### 4.8 Speech-to-Text (Voice Commands)
- **User-facing:** Voice command input for navigation destinations
- **Key files:** `services/stt_service.dart`
- **Notable logic:** **Stub implementation only.** All `speech_to_text` calls are commented out with TODOs. The service skeleton exists but does nothing.

### 4.9 On-Device VLM Model Management
- **User-facing:** Download, load, unload, delete offline AI models
- **Key files:** `services/model_download_service.dart`, `services/on_device_vision_service.dart`, native `ModelDownloadManager.swift`, `LlamaService.swift`
- **Notable logic:** HuggingFace CDN download with progress callbacks, TTS progress announcements at 25% intervals, Metal GPU acceleration for llama.cpp

### 4.10 Settings
- **User-facing:** Speech rate/volume, voice type, detail level, hazard sensitivity, font scale, high contrast, reduce motion, device management
- **Key files:** `screens/settings_screen.dart`, `models/settings_provider.dart`
- **Notable logic:** All settings persisted via SharedPreferences, live TTS rate adjustment

### 4.11 Device Pairing Flow
- **User-facing:** First-launch guided pairing with scan, timeout, skip option
- **Key files:** `screens/device_pairing_screen.dart`, `core/router.dart` (`_guardNoPairedDevices`)
- **Notable logic:** GoRouter redirect guard checks if any device was ever paired; if not, redirects to pairing screen. 20-second scan timeout. Partial pairing allowed (continue with one device).

---

## 5. Screens & Navigation

### Every Screen

| Screen | File | Purpose |
|--------|------|---------|
| Splash | `splash_screen.dart` | Animated logo, simulated loading, BLE auto-connect, navigates to role selection |
| Role Selection | `role_selection_screen.dart` | "I am the User" vs "I am a Caretaker" choice |
| Home (legacy) | `home_screen.dart` | Legacy home with vision mode picker, AI model picker, camera profile picker |
| Accessible Home | `accessible_home_screen.dart` | **Primary screen** — device status, live description, actions, quick settings |
| Device Pairing | `device_pairing_screen.dart` | Full-screen BLE scan and connect flow |
| Settings | `settings_screen.dart` | Audio, descriptions, devices, accessibility, about |
| Help | `help_screen.dart` | Getting started, home screen, hazard alerts, settings, troubleshooting guides |
| Navigation | `nav_screen.dart` | Placeholder turn-by-turn UI |
| GPS Monitor | `gps_screen.dart` | Live GPS data display |
| Caretaker Dashboard | `caretaker_dashboard_screen.dart` | HR, battery, fall detection, history |
| Connection Error | `connection_error_screen.dart` | Retry/scan/continue offline |
| 404 / Not Found | `router.dart` (`_NotFoundScreen`) | Inline private widget in router |

### Navigation Structure

**Two coexisting routing systems:**

1. **GoRouter (active, `lib/core/router.dart`):**
   - Initial location: `/` (home)
   - Redirect guard: if no devices ever paired → `/device-pairing`
   - `StatefulShellRoute.indexedStack` with 3 branches:
     - Tab 0: `/` → `AccessibleHomeScreen`
     - Tab 1: `/settings` → `SettingsScreen`
     - Tab 2: `/help` → `HelpScreen`
   - Full-screen routes (outside tab shell):
     - `/device-pairing` → `DevicePairingScreen`
     - `/nav` → `NavScreen`
     - `/gps` → `GpsScreen`
   - Every route change announces screen name via `SemanticsService.announce`

2. **Legacy Navigator (partially used, `lib/core/app_router.dart`):**
   - Named routes via `Navigator.pushNamed` / `pushReplacementNamed`
   - Used by: `SplashScreen`, `RoleSelectionScreen`, `CaretakerDashboardScreen`, `ConnectionErrorScreen`
   - Routes: `/splash`, `/role-selection`, `/home`, `/accessible-home`, `/device-pairing`, `/settings`, `/nav`, `/caretaker-dashboard`, `/gps`

**Bottom navigation:** Custom `AppShell` widget with 3 tabs (Home, Settings, Help), 72dp height, haptic feedback on tab switch, full accessibility semantics per tab.

**Modals:** Fall alert dialog (caretaker dashboard), forget device confirmation (settings), troubleshooting help (device pairing).

**Deep links:** Not configured.

---

## 6. Data Layer

### Local Persistence

| Mechanism | Usage |
|-----------|-------|
| **SharedPreferences** | Last connected Eye device ID, last connected Cane device ID, AI model preference, vision mode preference, speech rate, volume, voice type, detail level, hazard sensitivity, font scale, high contrast, reduce motion, camera profile index |
| **File storage** (`path_provider`) | Downloaded GGUF model files for SmolVLM |

No CoreData, SwiftData, Realm, SQLite, or Keychain usage.

### Remote Backend

| Service | Details |
|---------|---------|
| **Google Gemini API** | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` and `:streamGenerateContent?alt=sse` |
| Models: | `gemini-2.5-flash-lite`, `gemini-2.5-flash`, `gemini-2.5-pro` |
| Auth: | API key via `--dart-define=API_KEY=<key>` (compile-time constant) |

No Firebase, Supabase, custom REST, or GraphQL.

### Caching Strategy

- SharedPreferences for settings (read once at startup per ViewModel)
- No HTTP caching, no image caching, no response caching
- BLE service holds `_lastTelemetry` and `_lastGps` in memory

### Sync / Offline Behavior

- **Auto-detection:** `ConnectivityService.hasInternet()` does DNS lookup for `google.com`
- **Offline fallback:** `SceneDescriptionService` selects the best available offline backend (Foundation Models → Moondream → SmolVLM → Vision-only template)
- **No data sync:** No cloud-to-device data synchronization. All state is local.

---

## 7. Authentication & Security

### Auth Providers and Flows

**None.** There is no user authentication, login, registration, or session management.

### Token / Session Handling

**None.** The Gemini API uses a static API key, not OAuth/session tokens.

### Secrets Management

| Secret | Storage | Risk |
|--------|---------|------|
| Gemini API key | `--dart-define=API_KEY=<key>` at compile time | **CRITICAL: A `.env` file exists at the repo root containing the API key in plaintext.** The `.env` file contains: `API_KEY=AQ.Ab8RN6...` (truncated). This file appears to be committed or at least present in the working directory. The `flutter_dotenv` package is a dependency but the code actually reads the key via `String.fromEnvironment('API_KEY')`, not from dotenv. |
| Mapbox token | Hardcoded placeholder `YOUR_MAPBOX_API_TOKEN` in `nav_service.dart` | Not a real key — stub only |

### Sensitive Data Handling

- No Keychain usage
- No encryption of stored data
- Device IDs (BLE MAC addresses) stored in plaintext SharedPreferences
- No biometric authentication
- No certificate pinning

---

## 8. Networking

### HTTP Client

`package:http` (`http.Client`, `http.Request`, `http.post`)

### API Base URLs and Environments

| Environment | URL |
|-------------|-----|
| Production (only) | `https://generativelanguage.googleapis.com/v1beta/models` |

No staging or dev environments configured. Single API endpoint.

### Request/Response Patterns

- **Non-streaming:** `http.post` → JSON response → parse `candidates[0].content.parts[].text`
- **Streaming:** `http.Request` → `client.send()` → SSE stream → parse `data: {json}\n` lines → yield text chunks
- System prompt injection via `system_instruction` field
- Image sent as base64-encoded inline data

### Error Handling Strategy

- HTTP errors: throw `Exception('AI request failed (${statusCode})')` — caught by caller
- Network errors: `catch (_)` returns empty/fallback results
- BLE errors: logged via `debugPrint`, auto-reconnect attempted
- Platform channel errors: `PlatformException` caught, empty results returned
- No structured error types, no error reporting service, no user-visible error codes

---

## 9. Permissions & Capabilities

### Info.plist Usage Description Keys

| Key | Description |
|-----|-------------|
| `NSBluetoothAlwaysUsageDescription` | "iCan uses Bluetooth to communicate with the iCan Cane and iCan Eye devices for navigation assistance and scene description." |
| `NSBluetoothPeripheralUsageDescription` | "iCan uses Bluetooth to communicate with the iCan Cane and iCan Eye devices." |
| `NSMicrophoneUsageDescription` | "iCan uses the microphone for voice commands to control navigation and scene description." |
| `NSLocationWhenInUseUsageDescription` | "iCan uses your location to provide turn-by-turn navigation assistance." |
| `NSSpeechRecognitionUsageDescription` | "iCan uses speech recognition to process your voice commands for hands-free navigation control." |

### Background Modes

- `bluetooth-central` — maintains BLE connections when app is backgrounded

### Entitlements

Not found in codebase (no `.entitlements` file discovered). May be configured in Xcode project settings.

### Other

- No push notification entitlement (local notifications only)
- No App Groups
- No HealthKit, HomeKit, or other framework entitlements

---

## 10. Third-Party Integrations

| Category | Integration | Details |
|----------|-------------|---------|
| **AI/Vision (Cloud)** | Google Gemini API | 3 model tiers via REST API |
| **AI/Vision (On-device)** | Apple Vision framework | OCR, scene classification, human detection |
| **AI/Vision (On-device)** | Depth Anything V2 (CoreML) | Monocular depth estimation |
| **AI/Vision (On-device)** | YOLOv3 (CoreML) | Object detection |
| **AI/Vision (On-device)** | Moondream 2B (CoreML) | On-device VLM with Pointing skill |
| **AI/Vision (On-device)** | SmolVLM-500M (llama.cpp/GGUF) | On-device VLM via Metal GPU |
| **AI/Vision (On-device)** | Apple Foundation Models | iOS 26+ on-device LLM |
| **Analytics** | None | — |
| **Crash reporting** | None | — |
| **Ads** | None | — |
| **Payments** | None | — |

---

## 11. Testing

### Test Targets

- **Unit tests:** `test/widget_test.dart` — single smoke test
- **UI tests:** None
- **Integration tests:** None

### Test Content

```dart
// test/widget_test.dart
testWidgets('iCan app smoke test', (WidgetTester tester) async {
  await tester.pumpWidget(const ICanApp());
  expect(find.text('Say a Location'), findsOneWidget);  // ← likely broken
  expect(find.text('iCan'), findsOneWidget);
});
```

**Issue:** The smoke test expects `'Say a Location'` text on the home screen. The current `AccessibleHomeScreen` does not contain this text (it was in the legacy `HomeScreen`). The GoRouter now routes to `AccessibleHomeScreen`, and the redirect guard may send to `DevicePairingScreen` first. This test is almost certainly broken.

### Test Frameworks

- `flutter_test` (built-in)

### Coverage

**Effectively zero.** One likely-broken smoke test. No service tests, no ViewModel tests, no widget tests, no BLE protocol codec tests, no integration tests.

---

## 12. Build, CI/CD, Distribution

### Build Configurations

- **Android:** `android/app/build.gradle.kts` — namespace `com.example.ican`, Java 17, debug signing for release (no release keystore configured)
- **iOS:** Standard Flutter Runner target, no custom schemes found
- **API key injection:** `flutter run --dart-define=API_KEY=<key>` or `flutter build --dart-define=API_KEY=<key>`

### CI Config

**None.** No `.github/workflows/`, no `fastlane/`, no `Xcode Cloud`, no `bitrise.yml`, no `codemagic.yaml`.

### Signing / Provisioning

Not visible in configuration files. The bundle ID `com.example.ican` suggests provisioning has not been configured for distribution.

---

## 13. Known Issues, TODOs, FIXMEs

### TODOs in Codebase

| File | Line | TODO |
|------|------|------|
| `services/stt_service.dart` | 20 | `// TODO: Initialize speech_to_text plugin` |
| `services/stt_service.dart` | 32 | `// TODO: speech.listen(...)` |
| `services/stt_service.dart` | 44 | `// TODO: speech.stop()` |
| `services/nav_service.dart` | 24 | `// TODO: Replace with actual Mapbox API key` |
| `services/nav_service.dart` | 41 | `// TODO: Implement with Mapbox Directions API` |
| `screens/settings_screen.dart` | 528 | `// TODO: open feedback flow` |
| `screens/nav_screen.dart` | 33 | `// TODO: Cancel navigation in NavService, stop BLE commands` |
| `screens/nav_screen.dart` | 75 | `// TODO: Dynamic based on maneuver` |
| `screens/nav_screen.dart` | 85 | `// TODO: Replace with NavService.currentStep.instruction` |
| `screens/nav_screen.dart` | 96 | `// TODO: Replace with actual distance` |
| `screens/nav_screen.dart` | 124 | `// TODO: Dynamic step count from NavService` |
| `screens/nav_screen.dart` | 142 | `// TODO: Cancel nav, send NAV_STOP to cane` |

### Force-Unwraps in Swift (Risky Spots)

| File | Line | Code |
|------|------|------|
| `ios/Runner/ModelDownloadManager.swift` | 133 | `session!.downloadTask(with: url)` — force-unwrap on optional URLSession |
| `ios/Runner/EyePipeline/MoondreamService.swift` | 139 | `embeddings!.initialize(from: ptr.baseAddress!.assumingMemoryBound(...))` — double force-unwrap |
| `ios/Runner/EyePipeline/MoondreamService.swift` | 489 | `try! MLMultiArray(...)` — force-try on CoreML array creation |

### Deprecated API Usage

None detected in Dart code. No `@deprecated` annotations found.

### Other Issues Identified

1. **Dual routing systems:** `app_router.dart` (legacy Navigator) and `router.dart` (GoRouter) coexist. `SplashScreen` navigates via `Navigator.pushReplacementNamed(context, AppRouter.roleSelection)`, but the GoRouter doesn't know about `/splash` or `/role-selection`. These screens are unreachable from the GoRouter entry point. The splash/role-selection flow is orphaned from the main navigation.

2. **Broken smoke test:** `test/widget_test.dart` expects `'Say a Location'` text which doesn't exist in the current home screen.

3. **`.env` file with API key in repo:** The `.env` file at the repo root contains a Gemini API key in plaintext. If committed to git, this is a secrets leak.

4. **Bundle ID is placeholder:** `com.example.ican` — needs to be changed before App Store submission.

5. **`flutter_dotenv` imported but unused:** The `flutter_dotenv` package is in `pubspec.yaml` dependencies, but the actual API key is read via `String.fromEnvironment('API_KEY')` (compile-time `--dart-define`). The dotenv package appears unused.

6. **`DeviceState` model appears unused by the active navigation path:** `DeviceState` is defined but not provided or consumed in the GoRouter widget tree. The home screen reads directly from `BleService.instance`.

7. **`SplashScreen` accesses `const theme.colorScheme.secondary` on `CircularProgressIndicator`:** Line 141 uses `theme.colorScheme.secondary` inside a `const` widget, which will cause a compile error since theme is not const.

8. **New `TtsService` instances created per tab:** Each `ChangeNotifierProvider` in `router.dart` creates a new `TtsService()..init()`. Settings tab and Home tab each get their own TTS instance. Speech rate changes in Settings don't propagate to Home.

9. **`ConnectivityService` DNS check may fail behind captive portals:** The `google.com` DNS lookup returns success even on captive-portal Wi-Fi, leading to false "online" determination and cloud API calls that will fail.

10. **No timeout on BLE image reassembly:** If chunks arrive out of order or the final chunk is lost, incomplete image data may hang in the buffer indefinitely (only cleared on next capture start or explicit timeout, if one exists in the ~1400 line BLE service).

---

## 14. Main User Flows (Step-by-Step)

### Flow 1: First Launch → Device Pairing → Home

1. `main()` in `main.dart` calls `NotificationService.init()`, then runs `ICanApp`
2. `ICanApp.build()` creates `GoRouter` via `buildRouter()` with initial location `/`
3. GoRouter's `redirect` calls `_guardNoPairedDevices()`:
   - Reads `DevicePrefsService.instance.getLastDeviceId()` and `getLastCaneDeviceId()` from SharedPreferences
   - Both are null (first launch) → returns `/device-pairing`
4. `DevicePairingScreen` displays instructions, "Search for Devices" button
5. User taps "Search for Devices":
   - Calls `BleService.instance.startScan()` and `startScanForCane()`
   - 20-second timeout timer starts
   - BLE listener updates connection state, triggers haptic + semantic announcement on each device connect
6. When at least one device connects, "Continue" button appears
7. User taps "Continue" → `onPairingComplete` callback → `context.goNamed('home')`
8. `AccessibleHomeScreen` loads inside `AppShell` (tab 0)
9. TTS announces "Home screen. Camera and cane active."

### Flow 2: Scene Description (Automatic via BLE Camera)

1. `HomeViewModel._init()` subscribes to `BleService.instance.imageStream`
2. iCan Eye captures an image → BLE service reassembles JPEG from chunked packets → emits on `imageStream`
3. `HomeViewModel._imageSub` receives `Uint8List imageBytes`:
   - Checks `_isPaused` — skip if true
   - Computes fingerprint (head + tail bytes + length)
   - Deduplicates: skip if same fingerprint within 2 seconds
4. `_processImage(imageBytes)`:
   - Validates JPEG header (0xFFD8)
   - Runs `compute(_enhanceImageForApi, imageBytes)` in background isolate (contrast, sharpening, black bar crop)
   - Calls `sceneService.describeScene(enhancedBytes, systemPrompt: _systemPrompt)`
5. `SceneDescriptionService.describeScene()`:
   - `_selectBackend()` checks mode (Auto/Offline/Cloud):
     - Auto: `ConnectivityService.hasInternet()` → cloud if online, else offline fallback
     - Offline fallback priority: Foundation Models → Moondream → SmolVLM → Vision template
   - Yields text chunks via the selected backend's stream
6. `HomeViewModel` accumulates chunks, splits on sentence boundaries (`[.!?](?:\s|$)`), speaks each sentence via `TtsService.speak()`
7. Full text stored in `_lastDescription` and prepended to `_history`
8. `_isProcessing` set to false, `notifyListeners()` updates UI

### Flow 3: Manual "Describe Surroundings Now"

1. User taps "Describe Surroundings Now" button on `AccessibleHomeScreen`
2. Button calls `vm.describeNow()`:
   - Checks `canDescribe` (Eye connected, not processing, not paused)
   - Sets `_isProcessing = true`, calls `notifyListeners()`
   - Calls `BleService.instance.triggerEyeCapture()` — writes a byte to the Eye's capture characteristic
3. Eye firmware captures and streams JPEG chunks back over BLE
4. BLE service reassembles image → emits on `imageStream` → Flow 2 step 3 continues

### Flow 4: Obstacle Hazard Alert

1. Cane firmware detects obstacle → writes obstacle packet (side code + distance) to `obstacleAlertTx` characteristic
2. `BleService` parses packet → emits `ObstacleAlert(side, distanceCm)` on `obstacleStream`
3. `AccessibleHomeScreen._obstacleSub` receives alert:
   - Calls `_alertKey.currentState?.show(side: alert.side, distanceCm: alert.distanceCm)`
4. `HazardAlertBanner.show()`:
   - Constructs text: "Obstacle to your left — 2 feet away"
   - Triggers `HapticFeedback.vibrate()`
   - Slide-in animation (or instant if reduce motion)
   - `SemanticsService.announce(alertText)` for screen readers
   - Auto-dismiss timer: 5s (normal) or 10s (accessibility mode)

### Flow 5: Fall Detection (Caretaker)

1. From Role Selection, caretaker taps "I am a Caretaker" → navigates to `CaretakerDashboardScreen`
2. Dashboard subscribes to `BleService.instance.telemetryStream`
3. Cane detects fall → sets `fallDetected` flag in telemetry packet
4. `_onTelemetry(pkt)`:
   - Detects rising edge (fall flag set, no current `_fallTime`)
   - Records `_FallRecord` in `_fallHistory`
   - Calls `_showFallDialog()` — blocking AlertDialog: "Fall Detected. Check on the user immediately."
   - `NotificationService.showFallAlert()` fires OS-level notification
5. Caretaker taps "Acknowledge":
   - Dialog closes, `_fallAcknowledged = true`
   - Fall history entry marked as acknowledged
   - `NotificationService.cancelFallAlert()` dismisses OS notification
6. When firmware clears fall flag and fall is acknowledged, state resets for next event

---

## 15. Open Questions for the Reviewer

1. **Is the dual routing system intentional?** The GoRouter and legacy Navigator coexist. The splash screen, role selection, and caretaker dashboard are only reachable via the legacy Navigator. The GoRouter's initial route (`/`) bypasses splash entirely. Which flow is the intended production flow?

2. **Is the legacy `HomeScreen` (`home_screen.dart`) still needed?** It's registered in `app_router.dart` but not in the GoRouter. The `AccessibleHomeScreen` appears to be its replacement. Should it be removed?

3. **TTS instance sharing:** Settings and Home tabs each create independent `TtsService` instances. If the user changes speech rate in Settings, does the Home tab pick up the change? (Currently: no — they're separate instances.)

4. **Should `DeviceState` be removed?** It's defined but appears unused in the active navigation path. Both `HomeViewModel` and `CaretakerDashboardScreen` read directly from `BleService.instance`.

5. **What is the `.env` file's intended use?** The codebase uses `--dart-define=API_KEY` for compile-time injection but also has `flutter_dotenv` as a dependency and a `.env` file with the API key. Is this a leftover?

6. **BLE image reassembly timeout:** What happens if BLE chunks are lost mid-transfer? Is there a timeout/cleanup mechanism in the ~1400-line BLE service?

7. **iOS deployment target:** What is the minimum iOS version? Some features (Foundation Models) require iOS 26+. The standard Flutter default is iOS 12.

8. **Notification permissions:** `flutter_local_notifications` requests permissions at init time. Is there a permission-denied fallback?

9. **`speech_to_text` permission:** The microphone and speech recognition permissions are declared in Info.plist, but the STT service is entirely stubbed out. Will the user be prompted for these permissions even though the feature isn't implemented?

10. **Background BLE behavior:** The `bluetooth-central` background mode is enabled. What is the expected behavior when the app is backgrounded? Does image streaming continue? Do obstacle alerts still trigger?

11. **Offline model download size:** SmolVLM is described as ~800 MB. What is the actual download size? Is there a disk space check before download?

12. **Camera profile persistence:** `HomeScreen` saves camera profile to SharedPreferences, but `AccessibleHomeScreen` doesn't expose camera profile selection. Is this accessible to users in the new UI?

13. **Test coverage:** There is essentially no test coverage. What is the testing strategy?
