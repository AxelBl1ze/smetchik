#!/usr/bin/env bash
set -euo pipefail

rm -rf build/marketing
mkdir -p build/marketing/assets/brand build/marketing/assets/fonts
cp -R marketing/. build/marketing/
cp assets/brand/smetchik_icon.svg build/marketing/assets/brand/smetchik_icon.svg
cp assets/fonts/Inter-Regular.ttf assets/fonts/Inter-SemiBold.ttf \
  assets/fonts/Inter-ExtraBold.ttf assets/fonts/Inter-Black.ttf build/marketing/assets/fonts/
