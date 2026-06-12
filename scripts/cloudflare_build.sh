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
flutter build web --release
