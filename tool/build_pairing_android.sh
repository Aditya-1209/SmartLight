#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
FLUTTER_BIN=${SMARTLIGHT_FLUTTER_BIN:-flutter}
# Tuya 7.8.0 assigns the same namespace to several libraries. Scope the AGP
# compatibility switch to this personal SDK build; ordinary builds stay strict.
env 'ORG_GRADLE_PROJECT_android.uniquePackageNames=false' \
  'ORG_GRADLE_PROJECT_disable-abi-filtering=true' \
  ORG_GRADLE_PROJECT_smartlightTuya=true \
  "$FLUTTER_BIN" build apk --release --target-platform android-arm64
mkdir -p build/distributions
cp build/app/outputs/flutter-apk/app-release.apk build/distributions/SmartLight-Android-pairing.apk
