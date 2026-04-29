#!/usr/bin/env bash
# Compile the iOS target on macOS without signing or uploading.

set -euo pipefail

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

find_flutter() {
  if [[ -n "${FLUTTER_BIN:-}" ]]; then
    [[ -x "$FLUTTER_BIN" ]] || {
      printf 'ERROR: FLUTTER_BIN is set but not executable\n' >&2
      exit 1
    }
    return
  fi

  if command -v flutter >/dev/null 2>&1; then
    export FLUTTER_BIN="$(command -v flutter)"
    return
  fi

  local candidate
  for candidate in \
    "$HOME/flutter/bin/flutter" \
    "$HOME/development/flutter/bin/flutter" \
    "$HOME/tools/flutter/bin/flutter" \
    "/opt/homebrew/bin/flutter" \
    "/usr/local/bin/flutter"; do
    if [[ -x "$candidate" ]]; then
      export FLUTTER_BIN="$candidate"
      export PATH="$(dirname "$candidate"):$PATH"
      return
    fi
  done

  printf 'ERROR: flutter is not on PATH and FLUTTER_BIN is not set\n' >&2
  exit 1
}

configure_ruby() {
  if [[ -x "/opt/homebrew/opt/ruby/bin/ruby" ]]; then
    export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
  elif [[ -x "/usr/local/opt/ruby/bin/ruby" ]]; then
    export PATH="/usr/local/opt/ruby/bin:$PATH"
  fi

  if ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0") ? 0 : 1' >/dev/null 2>&1; then
    local gem_user_dir
    gem_user_dir="$(ruby -e 'require "rubygems"; print Gem.user_dir')"
    export GEM_HOME="$gem_user_dir"
    export PATH="$gem_user_dir/bin:$(ruby -e 'require "rubygems"; print Gem.bindir'):$PATH"
  fi
}

find_flutter
configure_ruby

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
