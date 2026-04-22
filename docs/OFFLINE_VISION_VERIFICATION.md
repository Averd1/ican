# Offline Vision Backend Verification

Use the hidden **Vision Diagnostic** screen to test each backend in isolation.

**Access:** Settings > About > long-press on the "Version" row.

---

## Test Checklist

### 1. Cloud Gemini

| Item | Detail |
|------|--------|
| **Prerequisites** | Internet connection, valid `API_KEY` injected via `--dart-define` |
| **Expected first-token latency** | 500–1500 ms (depends on model tier and network) |
| **Known failure modes** | `API_KEY not set` error if built without `--dart-define=API_KEY`; HTTP 429 if rate-limited; empty response on malformed JPEG |

### 2. Apple Foundation Models

| Item | Detail |
|------|--------|
| **Prerequisites** | iOS 26+ device; no download required (system model) |
| **Expected first-token latency** | 300–800 ms on iPhone 13+ |
| **Known failure modes** | Returns immediate error on iOS < 26 (`isFoundationModelsAvailable` returns false, backend is skipped); may produce no tokens on very dark or featureless images — falls back to Layer 1 template |

### 3. Moondream CoreML

| Item | Detail |
|------|--------|
| **Prerequisites** | Moondream CoreML model bundle must be included in the app binary (bundled at build time, not a runtime download) |
| **Expected first-token latency** | 1000–2500 ms on iPhone 13+ (encode + 730-token prefill before first caption token) |
| **Known failure modes** | `isMoondreamAvailable` returns false if model files are missing from the bundle; prefill can fail on corrupt/truncated JPEG — falls back to template; high memory usage (~1.5 GB) may cause eviction on devices with < 4 GB RAM |

### 4. SmolVLM llama.cpp

| Item | Detail |
|------|--------|
| **Prerequisites** | GGUF model file downloaded via the app (Settings or legacy Home > "Download offline model"); model must be loaded into memory (`ModelStatus.loaded`) |
| **Expected first-token latency** | 2000–4000 ms on iPhone 13+ (model load if not already loaded + Metal GPU inference) |
| **Known failure modes** | `ModelStatus.notDownloaded` if file missing (~800 MB download); `loadModel` fails if insufficient RAM (requires ~1 GB free); inference produces no tokens on very small images (< 100 px); `try!` crash in llama.cpp layer if model file is corrupted (see `LlamaService.swift`) |

### 5. Vision-only Template

| Item | Detail |
|------|--------|
| **Prerequisites** | None (always available on any iOS device) |
| **Expected first-token latency** | 200–600 ms (runs Apple Vision framework: OCR + scene classification + person detection + YOLOv3 + Depth Anything V2) |
| **Known failure modes** | Returns generic "The scene could not be clearly identified" if all Vision classifiers return low confidence; depth map unavailable on simulator (CoreML model may not load) |

---

## General Notes

- Pick a well-lit indoor photo with readable text and at least one object for best coverage across all backends.
- Run each backend 2–3 times to get a stable latency reading; the first run often includes model load overhead.
- The diagnostic screen bypasses the fallback chain — if a backend fails, it reports the error instead of falling through to the next backend.
- Use "Copy Result" to capture timing + output for bug reports.
