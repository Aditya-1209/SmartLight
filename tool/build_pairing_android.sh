#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${SMARTLIGHT_TAPO_IP:?Set SMARTLIGHT_TAPO_IP to the private IPv4 address of your strip}"
FLUTTER_BIN=${SMARTLIGHT_FLUTTER_BIN:-flutter}
# Tuya 7.8.0 assigns the same namespace to several libraries. Scope the AGP
# compatibility switch to this personal SDK build; ordinary builds stay strict.
env 'ORG_GRADLE_PROJECT_android.uniquePackageNames=false' \
  'ORG_GRADLE_PROJECT_disable-abi-filtering=true' \
  ORG_GRADLE_PROJECT_smartlightTuya=true \
  "$FLUTTER_BIN" build apk --release --target-platform android-arm64 \
    --dart-define="SMARTLIGHT_TAPO_IP=$SMARTLIGHT_TAPO_IP"
mkdir -p build/distributions
cp build/app/outputs/flutter-apk/app-release.apk build/distributions/SmartLight-Android-pairing.apk
