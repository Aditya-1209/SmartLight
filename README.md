# SmartLight

One Flutter app for the two **Wipro SB22240 CCT + RGB battens** and one **Tapo L920 strip** in your room, using Home Assistant as the bridge. Runs on Android, macOS, and Windows. No accounts, analytics, ads, or additional backend.

**Physical device compatibility is unverified until tested with your actual lights and Home Assistant installation.** The app discovers capabilities from Home Assistant rather than assuming every device supports every control.

## Features

- Responsive Material 3 dashboard, desktop navigation rail, mobile navigation, light/dark/system themes.
- Per-light power, brightness, RGB presets/custom RGB picker, and warm-to-cool temperature controls where supported.
- Room power, brightness, color, and Study/Movie/Chill/Sleep scenes; failures reported per device.
- Secure setup, editable names, and unique mappings to discovered `light.*` entities.
- Live WebSocket updates, exponential reconnect, heartbeat, REST fallback, manual refresh, and resume refresh.
- Demo backend with three lights, live updates, unavailable devices, and server-offline simulation.
- Diagnostics with connection/state details and test controls. Tokens never appear in diagnostics.

## Screenshots

Screenshots of the dashboard, setup, device detail, and dark/mobile layouts can be added here after UI review. No real credentials or personal server addresses should appear in screenshots.

## Architecture

```text
Flutter UI → Riverpod AppController → LightsRepository
                                      ├─ HomeAssistantRepository
                                      │   ├─ REST API /api/
                                      │   └─ WebSocket /api/websocket
                                      └─ MockHomeAssistant
Home Assistant → configured device integrations → physical lights
```

`lib/models` contains defensive parsing, conversions, commands, slots, and scene definitions. `lib/services` contains networking, secure credentials, and the mock. `lib/repositories` owns backend and settings interfaces. `lib/providers/app_controller.dart` coordinates lifecycle, updates, and per-device command results. UI widgets contain no network requests.

Only the supported [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/) and [WebSocket API](https://developers.home-assistant.io/docs/api/websocket/) are used. Capabilities come from [light entity attributes](https://developers.home-assistant.io/docs/core/entity/light/). Custom scenes can later be added using `LightScene` and its slot-to-command map; a scene editor is outside this MVP.

## Requirements and Flutter setup

- Flutter **3.47.5 stable** / Dart **3.13.4** (CI pins this version; `pubspec.lock` is committed).
- Git, and optionally GitHub CLI for CI inspection.
- Android: Android Studio, Android SDK and accepted licenses; use Android Studio's bundled JDK or JDK 17+ compatible with Gradle 9.3.1.
- macOS: Xcode with command-line tools and CocoaPods when required by Flutter plugins. Apple Silicon supported; no Rosetta runtime dependency.
- Windows 11 x64: Visual Studio 2022 with Desktop development with C++, Windows SDK, CMake, and C++ ATL libraries. Enable Developer Mode for plugin symlinks.
- A reachable Home Assistant server and three configured `light.*` entities for real operation.

Install [Flutter](https://docs.flutter.dev/get-started/install), add its `bin` directory to PATH, then:

```sh
git clone https://github.com/Aditya-1209/SmartLight.git
cd SmartLight
flutter --version
flutter doctor -v
flutter pub get
```

## Home Assistant setup and mapping

1. Add each physical light to Home Assistant and verify its controls work there.
2. For Tapo, use the official [TP-Link Smart Home integration](https://www.home-assistant.io/integrations/tplink/), which lists the L920-5. Firmware and third-party compatibility settings can affect availability; follow that integration's instructions.
3. For Wipro, verify which supported integration exposes your particular SB22240 firmware. If the devices are supported and paired through Smart Life/Tuya Smart, consult the official [Tuya integration](https://www.home-assistant.io/integrations/tuya/). Wipro-branded account compatibility is **not assumed**. Do not reset/re-pair devices without checking the integration requirements. A working HA light entity is a prerequisite; SmartLight does not implement proprietary Wipro/Tuya or Tapo protocols.
4. In your Home Assistant profile's Security area, create a long-lived access token. Keep it private.
5. Open SmartLight → Settings. Enter the server origin (for example `http://192.168.1.10:8123`) and token, then **Test connection**.
6. Select a different discovered light entity for Wipro Tube 1, Wipro Tube 2, and Tapo Strip. Edit names if desired, then **Save**.

The URL must be an HTTP(S) origin, with no username/password, query, fragment, or proxy subpath. The token and server URL are stored together in secure storage. Names, mappings, theme, and demo selection are stored in preferences.

## Run

```sh
flutter run -d macos       # on macOS
flutter run -d windows     # on Windows
flutter devices
flutter run -d <device-id> # Pixel 8 with USB debugging enabled
```

With no server configured, choose **Try demo**. You can also enable it in Settings → Developer settings. Diagnostics can make individual demo lights unavailable or simulate an offline server. Demo mappings do not overwrite real mappings; disabling demo restores the saved configuration. An existing real configuration does not automatically switch to demo.

## Platform notes and builds

### Android / Pixel 8

```sh
flutter doctor --android-licenses
flutter build apk --debug
flutter build apk --release
```

APKs: `build/app/outputs/flutter-apk/`. The app declares Internet and network-state permissions and disables backups for encrypted credentials. The debug-only network policy allows arbitrary LAN HTTP addresses. Release denies cleartext by default, with one exception for `homeassistant.local`; use a trusted HTTPS URL or that local hostname for release. If you need a specific LAN hostname in production, add that exact hostname to `android/app/src/main/res/xml/network_security_config.xml` rather than allowing cleartext globally.

The release APK uses the generated **debug signing key for local testing only**. Configure your own private signing key outside Git before distributing a production release. CI APKs are debug/test artifacts.

### macOS / Apple Silicon

```sh
flutter build macos
open build/macos/Build/Products/Release/SmartLight.app
```

Both debug and release entitlements permit outbound networking. The local-network usage description and local-network ATS exception are configured. Allow the Local Network permission if macOS requests it. Credentials use the macOS login Keychain (`usesDataProtectionKeychain: false`), without cross-app Keychain Sharing or a provisioning-profile requirement, following the [storage plugin's macOS guidance](https://pub.dev/packages/flutter_secure_storage). Build artifacts are for local testing; notarization/distribution signing is not configured.

### Windows 11

```powershell
flutter build windows
```

Run `build/windows/x64/runner/Release/smart_light.exe` with **all adjacent DLLs and the data directory**. Windows cannot be cross-compiled on macOS; CI builds on `windows-latest` and uploads the entire Release folder. Install the Microsoft Visual C++ runtime if required on a clean target PC.

## Test

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter test --coverage
flutter test integration_test/demo_flow_test.dart -d macos
# Or run the same integration test with -d <android-device-id> / -d windows.
```

Unit tests cover safe parsing, brightness round trips, RGB/temperature serialization, scenes, mapping validation, persistence, partial failure, and recovery. HTTP tests use mocked responses. WebSocket tests run a local loopback server, including auth, subscription, malformed events, reconnect, and disposal. Widget tests cover setup, dashboard, controls, scenes, diagnostics, offline behavior, and phone/desktop sizes. Native integration tests exercise the complete demo flow without physical lights or real credentials.

Use [REAL_DEVICE_TESTING.md](REAL_DEVICE_TESTING.md) for hardware validation. Successful API responses confirm Home Assistant accepted a request; actual electrical/visual output still needs that checklist.

## GitHub Actions and artifacts

[Workflow runs](https://github.com/Aditya-1209/SmartLight/actions) run on pushes to `main`, pull requests, and manual dispatch. The checks job resolves dependencies, verifies formatting, analyzes, and tests. Separate Ubuntu/Windows/macOS jobs build their native targets.

Download successful artifacts from a run: `SmartLight-Android-debug`, `SmartLight-Windows` (complete runtime folder), `SmartLight-macOS` (zipped app bundle), and `SmartLight-Test-Coverage`. These are test builds, not app-store packages. See [VALIDATION.md](VALIDATION.md) for the tested snapshot and limitations.

## Security

- No token in source, preferences, diagnostics, logs, environment files, or CI. Secure storage uses platform protection; plaintext HTTP still exposes traffic on the network, so use it only on a trusted LAN.
- REST redirects are rejected so bearer credentials are not forwarded to another endpoint. TLS verification is never bypassed.
- Use a suitable Home Assistant user account; revoke/replace its token in HA if a device is lost. This MVP has no in-app token revocation UI.
- `.gitignore` excludes caches, credentials, private keys, Android signing material, and local configuration. Never add your real URL/token to tests or screenshots.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Invalid URL | Enter the origin only, with `http://` or `https://` and the correct port. |
| Unauthorized | Recreate/check the full long-lived token. Save again to restart the realtime session. |
| Offline / timeout | Check HA availability, LAN/VPN, firewall, DNS, and the device's Local Network permission. Private LAN URLs do not work outside the LAN without a VPN or secure remote access. |
| Release Android HTTP fails | Use HTTPS or `homeassistant.local`; arbitrary IP HTTP is enabled only in debug. |
| No color/temperature controls | Check `supported_color_modes` in Diagnostics and the device's HA integration. Unsupported controls are hidden. |
| One light fails | The others can still succeed. Read the named failure and inspect that light in HA. |
| WebSocket reconnecting | REST refresh stays available; check proxy WebSocket forwarding and authentication. |
| Secure storage fails | Unlock/check the system Keychain or OS credential store; do not replace it with plaintext storage. |
| Android Java error | Run `flutter doctor -v`; point Flutter to a compatible JDK with `flutter config --jdk-dir=<path>`. |
| macOS iOS simulator warning | iOS is not a target; this warning does not itself prevent macOS builds. |
