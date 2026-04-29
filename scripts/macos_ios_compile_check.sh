#!/usr/bin/env bash
# Compile the iOS target on macOS without signing or uploading.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -n "${FLUTTER_BIN:-}" ]]; then
  [[ -x "$FLUTTER_BIN" ]] || {
    printf 'ERROR: FLUTTER_BIN is set but not executable\n' >&2
    exit 1
  }
elif command -v flutter >/dev/null 2>&1; then
  export FLUTTER_BIN="$(command -v flutter)"
else
  printf 'ERROR: flutter is not on PATH and FLUTTER_BIN is not set\n' >&2
  exit 1
fi

IOS_BUNDLE_IDENTIFIER="${IOS_BUNDLE_IDENTIFIER:-com.icannavigation.app}"

printf '==> Flutter version\n'
"$FLUTTER_BIN" --version

printf '==> Installing Flutter dependencies\n'
"$FLUTTER_BIN" pub get

printf '==> Checking Dart format\n'
dart format --output=none --set-exit-if-changed lib test

printf '==> Running Flutter analyzer\n'
"$FLUTTER_BIN" analyze --no-fatal-infos --fatal-warnings

printf '==> Running Flutter tests\n'
"$FLUTTER_BIN" test --no-pub

printf '==> Compiling iOS release target without code signing\n'
"$FLUTTER_BIN" build ios \
  --release \
  --no-codesign \
  --no-pub \
  --dart-define=API_KEY=compile_time_placeholder \
  --dart-define=IOS_BUNDLE_IDENTIFIER="$IOS_BUNDLE_IDENTIFIER"
