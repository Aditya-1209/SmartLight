#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
FLUTTER_BIN="${SMARTLIGHT_FLUTTER_BIN:-flutter}"
"$FLUTTER_BIN" build macos --release "$@"
APP=build/macos/Build/Products/Release/SmartLight.app
# Some incremental Flutter builds replace App.framework after Xcode seals the
# enclosing app. Reseal personal ad-hoc builds only; preserve developer signing.
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
  if codesign -d --verbose=2 "$APP" 2>&1 | /usr/bin/grep -q '^Signature=adhoc$'; then
    codesign --force --sign - --entitlements macos/Runner/Release.entitlements "$APP"
  else
    echo 'Signature verification failed. Rebuild with your configured signing identity.' >&2
    exit 1
  fi
fi
codesign --verify --deep --strict "$APP"
