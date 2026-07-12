#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="${FLUTTER_HOME:-/tmp/flutter}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  rm -rf "$FLUTTER_HOME"
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter --version
flutter config --enable-web
flutter pub get

build_args=(--release)
for variable in SUPABASE_URL SUPABASE_ANON_KEY PUBLIC_APP_URL; do
  value="${!variable:-}"
  if [[ -n "$value" ]]; then
    build_args+=("--dart-define=$variable=$value")
  fi
done

flutter build web "${build_args[@]}"
